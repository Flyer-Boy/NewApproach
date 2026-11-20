"""
Web API for the Procurement Assistant UI (see DESIGN_procurement_ui.md).

A thin layer over agent/procurement.py: the same recommendations, guard rails and governed Cypher the AI agent uses,
with prepare/commit as two HTTP calls so the browser can show its own review step. The browser never talks to Aura;
this process holds the connection and each person's session. Every PO written here records Source: "ui".

Behind the scenes, two kinds of help, both advisory:
  - demand suggestions: the "Recent demand for products" template (Cypher; no AI);
  - justification drafts: Claude, from facts this server gathers, on request. Only what the person submits is recorded.

Run (from the Neo4jRelate folder, with .env filled in and SIMULATION_MODE=agents):
  uvicorn api.main:app --port 8000
Then open http://localhost:8000 (the built UI), or run the UI's dev server (ui/: npm run dev).
"""
from __future__ import annotations

import os
import secrets
import sys
import threading
import time
from pathlib import Path
from typing import Any, Callable

from fastapi import Cookie, FastAPI, HTTPException, Response
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parent.parent
for sub in ("agent", "kb"):
    sys.path.insert(0, str(ROOT / sub))

import procurement  # noqa: E402
from model_templates import ModelTemplates  # noqa: E402

COOKIE = "nwplus_ui"
PREVIEW_TTL_S = 15 * 60          # a review older than this has to be done again: the graph will have moved on
SESSION_TTL_S = 8 * 3600
DRAFT_MODEL = os.environ.get("DRAFT_MODEL") or "claude-sonnet-5-5"   # the agent's model; override in .env

ASSISTANTS = """
MATCH (:RolE {Title:"Procurement Assistant"})-[ar:IS_ACTIVE_ROLE]->(e:Employee)-[:HAS_PERSON]->(p:Person)
WHERE ar.EndDate IS NULL
RETURN e.EmployeeID AS employeeId, p.FirstName + " " + p.LastName AS name
ORDER BY toInteger(e.EmployeeID)"""

DRAFT_SYSTEM = """You draft the justification a Northwind procurement assistant will submit with a purchase order.
Write 1-3 plain sentences, first person plural ("we"), no greeting, no bullet points, under 60 words.
Use ONLY the facts given. Never invent numbers, customers, dates or reasons. Prefer the concrete facts: open customer
orders waiting, stock against the restock threshold, recent demand, and for a resubmission, how the new PO answers the
rejecter's comment. If a quantity differs from the recommendation, say why only if the facts give a reason (for
example the demand figures); otherwise just state the quantity. Never suggest splitting a PO. Return only the text."""


class UISession:
    """What procurement.Procurement needs from a session; no input(), no chat Interaction."""

    def __init__(self, aura, templates, employee_id: str, user: dict, mode: str):
        self.aura, self.kb, self.employee_id, self.user, self.mode = aura, templates, employee_id, user, mode
        self.interaction_id = None
        self.procurement = procurement.Procurement(self, source="ui")
        self.previews: dict[str, dict] = {}
        self.touched = time.time()


class SignIn(BaseModel):
    employeeId: str


class Item(BaseModel):
    productId: str
    qty: int


class PO(BaseModel):
    supplierId: str
    items: list[Item]
    justification: str = ""


class Resubmission(BaseModel):
    rejectedPO: str
    items: list[Item]
    justification: str = ""


class Cancellation(BaseModel):
    rejectedPO: str
    justification: str = ""


class Commit(BaseModel):
    previewId: str


class DemandRequest(BaseModel):
    items: list[Item]
    windowDays: float | None = None
    coverDays: float | None = None


class DraftRequest(BaseModel):
    kind: str = Field(pattern="^(create|resubmit|cancel)$")
    supplierId: str | None = None
    rejectedPO: str | None = None
    items: list[Item] = []


def _public(entries: list[dict]) -> list[dict]:
    """The review entries without the raw request copy kept for commit."""
    return [{k: v for k, v in e.items() if k != "p"} for e in entries]


def _answer(result: dict) -> dict:
    """Refusals and errors become HTTP errors the UI shows as they are; anything else is returned."""
    if "refused" in result:
        raise HTTPException(409, result["refused"])
    if "error" in result:
        raise HTTPException(502, result["error"])
    return result


def default_llm() -> Callable[[str, str], str] | None:
    if not os.environ.get("ANTHROPIC_API_KEY"):
        return None
    import anthropic
    client = anthropic.Anthropic()

    def call(system: str, prompt: str) -> str:
        # A generous cap: the draft itself is short, but a model that reasons first can use up a tight budget
        # before writing any text, and the reply then comes back empty.
        msg = client.messages.create(model=DRAFT_MODEL, max_tokens=2048, system=system,
                                     messages=[{"role": "user", "content": prompt}])
        text = "".join(b.text for b in msg.content if getattr(b, "type", "") == "text").strip()
        if not text:
            kinds = ", ".join(sorted({getattr(b, "type", "?") for b in msg.content})) or "none"
            raise RuntimeError(f"no text in the reply from {DRAFT_MODEL} (stop reason: {msg.stop_reason}; "
                               f"content blocks: {kinds})")
        return text
    return call


def create_app(aura=None, templates=None, llm: Callable[[str, str], str] | None | str = "default",
               mode: str | None = None) -> FastAPI:
    """aura/templates/llm can be replaced (the tests use a relate stand-in for Aura and a fake LLM)."""
    if aura is None:
        from dotenv import load_dotenv
        load_dotenv(ROOT / ".env")
        from aura import Aura
        aura = Aura()
    templates = templates or ModelTemplates()
    if llm == "default":
        llm = default_llm()
    run_mode = (mode or os.environ.get("SIMULATION_MODE") or "full").strip().lower()

    app = FastAPI(title="NorthWind PLUS Procurement UI API")
    sessions: dict[str, UISession] = {}
    lock = threading.Lock()

    def current(token: str | None) -> UISession:
        with lock:
            for t in [t for t, s in sessions.items() if time.time() - s.touched > SESSION_TTL_S]:
                sessions.pop(t, None)
            s = sessions.get(token or "")
        if not s:
            raise HTTPException(401, "Not signed in.")
        s.touched = time.time()
        return s

    def preview(s: UISession, kind: str, prep: dict) -> dict:
        if "entries" not in prep:
            _answer(prep)
        pid = secrets.token_urlsafe(12)
        s.previews = {k: v for k, v in s.previews.items() if time.time() - v["at"] < PREVIEW_TTL_S}
        s.previews[pid] = {"kind": kind, "entries": prep["entries"], "at": time.time()}
        return {"previewId": pid, "header": prep["header"], "entries": _public(prep["entries"])}

    def take(s: UISession, kind: str, pid: str) -> list[dict]:
        p = s.previews.pop(pid, None)
        if not p or p["kind"] != kind:
            raise HTTPException(409, "This review isn't valid any more. Review the POs again before confirming.")
        if time.time() - p["at"] > PREVIEW_TTL_S:
            raise HTTPException(409, "This review is more than 15 minutes old. Review the POs again before confirming.")
        return p["entries"]

    # ---------------- session and status ----------------

    @app.get("/api/config")
    def config():
        return {"mode": run_mode, "drafts": llm is not None, "database": getattr(aura, "database", None)}

    @app.get("/api/employees")
    def employees():
        r = aura.read(ASSISTANTS, {})
        return _answer(r)["rows"]

    @app.post("/api/session")
    def sign_in(body: SignIn, response: Response):
        try:
            user = aura.whoami(body.employeeId)
        except SystemExit as e:
            raise HTTPException(404, str(e))
        if not user:
            raise HTTPException(404, f"No Employee {body.employeeId}.")
        s = UISession(aura, templates, body.employeeId, user, run_mode)
        token = secrets.token_urlsafe(24)
        with lock:
            sessions[token] = s
        response.set_cookie(COOKIE, token, httponly=True, samesite="strict")
        access = s.procurement.check_access()
        return {"user": user, "mode": run_mode, "canUseProcurement": access is None,
                "reason": access["refused"] if access else None}

    @app.delete("/api/session")
    def sign_out(response: Response, nwplus_ui: str | None = Cookie(default=None)):
        with lock:
            sessions.pop(nwplus_ui or "", None)
        response.delete_cookie(COOKIE)
        return {"signedOut": True}

    @app.get("/api/status")
    def status(nwplus_ui: str | None = Cookie(default=None)):
        s = current(nwplus_ui)
        p = s.procurement
        running = p.loops_running()
        return {"user": s.user, "mode": run_mode, "limits": p._limits(), "loops": running,
                "access": (p.check_access() or {}).get("refused")}

    # ---------------- recommendations and demand ----------------

    def with_demand(p, rows: list[dict]) -> None:
        for r in rows:
            items = [{"productId": l["ProductID"], "qty": l.get("RecommendedQt") or 0} for l in r["Lines"]
                     if l.get("RecommendedQt")]
            r["demand"] = p.demand(items) if items else None

    @app.get("/api/restock")
    def restock(nwplus_ui: str | None = Cookie(default=None)):
        p = current(nwplus_ui).procurement
        result = _answer(p.recommend_restock({}))
        with_demand(p, result.get("rows", []))
        return result

    @app.get("/api/resubmissions")
    def resubmissions(nwplus_ui: str | None = Cookie(default=None)):
        p = current(nwplus_ui).procurement
        result = _answer(p.recommend_resubmissions({}))
        with_demand(p, result.get("rows", []))
        return result

    @app.post("/api/demand")
    def demand(body: DemandRequest, nwplus_ui: str | None = Cookie(default=None)):
        p = current(nwplus_ui).procurement
        return _answer(p.demand([i.model_dump() for i in body.items], body.windowDays, body.coverDays))

    # ---------------- prepare / commit ----------------

    @app.post("/api/purchase-orders/preview")
    def create_preview(pos: list[PO], nwplus_ui: str | None = Cookie(default=None)):
        s = current(nwplus_ui)
        return preview(s, "create", s.procurement.prepare_create({"purchaseOrders": [p.model_dump() for p in pos]}))

    @app.post("/api/purchase-orders")
    def create_commit(body: Commit, nwplus_ui: str | None = Cookie(default=None)):
        s = current(nwplus_ui)
        return _answer(s.procurement.commit_create(take(s, "create", body.previewId)))

    @app.post("/api/resubmissions/preview")
    def resubmit_preview(subs: list[Resubmission], nwplus_ui: str | None = Cookie(default=None)):
        s = current(nwplus_ui)
        return preview(s, "resubmit", s.procurement.prepare_resubmit({"resubmissions": [x.model_dump() for x in subs]}))

    @app.post("/api/resubmissions")
    def resubmit_commit(body: Commit, nwplus_ui: str | None = Cookie(default=None)):
        s = current(nwplus_ui)
        return _answer(s.procurement.commit_resubmit(take(s, "resubmit", body.previewId)))

    @app.post("/api/cancellations/preview")
    def cancel_preview(cancels: list[Cancellation], nwplus_ui: str | None = Cookie(default=None)):
        s = current(nwplus_ui)
        return preview(s, "cancel", s.procurement.prepare_cancel({"cancellations": [c.model_dump() for c in cancels]}))

    @app.post("/api/cancellations")
    def cancel_commit(body: Commit, nwplus_ui: str | None = Cookie(default=None)):
        s = current(nwplus_ui)
        return _answer(s.procurement.commit_cancel(take(s, "cancel", body.previewId)))

    # ---------------- justification drafts (Claude, on request) ----------------

    @app.post("/api/justification-draft")
    def draft(body: DraftRequest, nwplus_ui: str | None = Cookie(default=None)):
        s = current(nwplus_ui)
        p = s.procurement
        if (refusal := p.check_access()):
            _answer(refusal)
        if llm is None:
            raise HTTPException(503, "Drafts need ANTHROPIC_API_KEY in .env.")
        facts = draft_facts(p, body)
        try:
            text = llm(DRAFT_SYSTEM, facts)
        except Exception as e:                      # Anthropic API errors: credit, key, model name, network
            msg = getattr(e, "message", None) or str(e)
            print(f"  Justification draft failed ({type(e).__name__}): {msg}", flush=True)
            raise HTTPException(502, f"The AI draft failed ({type(e).__name__}): {msg[:300]}")
        if not text:
            raise HTTPException(502, "The AI draft came back empty. Try again, or write the justification yourself.")
        return {"draft": text, "model": DRAFT_MODEL, "facts": facts}

    # ---------------- audit ----------------

    @app.get("/api/audit")
    def audit(hours: float = 24, nwplus_ui: str | None = Cookie(default=None)):
        return _answer(current(nwplus_ui).procurement.audit(hours))

    # ---------------- the built UI, if present ----------------

    dist = ROOT / "ui" / "dist"
    if dist.is_dir():
        app.mount("/assets", StaticFiles(directory=dist / "assets"), name="assets")

        @app.get("/{path:path}", include_in_schema=False)
        def spa(path: str):
            f = dist / path
            if path and f.is_file():
                return FileResponse(f)
            # index.html names the current build's hashed assets: browsers must re-check it, or after a rebuild they
            # keep running the previous UI from cache. (The hashed files under /assets can be cached freely.)
            return FileResponse(dist / "index.html", headers={"Cache-Control": "no-cache"})

    app.state.sessions = sessions
    return app


def draft_facts(p: procurement.Procurement, body: DraftRequest) -> str:
    """The facts a draft may use, gathered here from the session's own recommendation and the demand template, so
    the browser can't feed the model anything else."""
    lines: list[str] = []
    items = {i.productId: i.qty for i in body.items}
    if body.kind == "create":
        rec = p.restock.get(body.supplierId or "")
        if not rec:
            raise HTTPException(409, "Load the restock recommendation first.")
        lines.append(f"New purchase order to supplier {rec['supplier']}.")
        recl = rec["lines"]
    else:
        rec = p.resub.get(body.rejectedPO or "")
        if not rec:
            raise HTTPException(409, "Load the rejected POs first.")
        rej = rec.get("Rejection") or {}
        verb = "Resubmitting" if body.kind == "resubmit" else "Cancelling"
        lines.append(f"{verb} rejected purchase order {body.rejectedPO} to supplier {rec.get('Supplier')}.")
        if rej.get("RejectedBy"):
            lines.append(f"It was rejected at {rej.get('Level')} by {rej.get('RejectedBy')}, comment: "
                         f"\"{rej.get('Comment') or 'none'}\".")
        recl = {l["ProductID"]: l for l in rec["Lines"]}
        if body.kind == "cancel":
            for l in rec["Lines"]:
                lines.append(f"- {l['Product']}: rejected quantity {l.get('RejectedQt')}, still needed now "
                             f"{l.get('RecommendedQt') or 0}, product {'orderable' if l.get('Orderable') else 'not orderable from this supplier'}.")
            return "\n".join(lines)
    planned = [{"productId": pid, "qty": q} for pid, q in items.items() if pid in recl]
    dem = {r["ProductID"]: r for r in (p.demand(planned).get("rows") or [])} if planned else {}
    for pid, q in items.items():
        l = recl.get(pid)
        if not l:
            continue
        d = dem.get(pid, {})
        parts = [f"- {l['Product']}: ordering {q} (recommended {l.get('RecommendedQt')})",
                 f"in stock {l.get('UnitsInStock')}, already on active POs {l.get('OnActivePOs')}, "
                 f"promised to open customer orders {l.get('OpenOrderQty')}, restock threshold {l.get('StockThreshold')}"]
        if d.get("Orders"):
            parts.append(f"customers ordered {d['UnitsOrdered']} units in {d['Orders']} orders over the last "
                         f"{d['DaysObserved']} days (about {d['UnitsPerDay']} a day); this order covers about "
                         f"{d['DaysOfCoverAfterPO']} days")
        else:
            parts.append("no customer orders in the demand window")
        lines.append("; ".join(parts) + ".")
    return "\n".join(lines)


def __getattr__(name: str) -> Any:
    """`uvicorn api.main:app` builds the real app on first use, so importing this module (the tests do) needs no Aura."""
    if name == "app":
        globals()["app"] = create_app()
        return globals()["app"]
    raise AttributeError(name)
