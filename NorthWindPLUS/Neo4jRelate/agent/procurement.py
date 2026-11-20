"""
Procurement Assistant tools (model v2.3.3): recommend restocking and resubmissions, then create, resubmit or cancel POs.

Offered only to an employee holding the "Procurement Assistant" role. The recommendations are read templates with the
same rules and formulas as the simulation loops they replace. The writes are the governed templates from the import
script's **Procurement Assistant** section: fixed Cypher that re-checks the role, locks the products, recomputes what
is still needed, and records Date, Justification, Source ("agent" here, "ui" from the web UI) and RecommendedQt.
A person confirms every write.

Guard rails here, in code (the Cypher repeats the ones that matter):
  - recommend before writing: create/resubmit need a recommendation from this session (the write re-checks anyway);
  - one justification per PO, required;
  - one PO per Supplier per batch: splitting a PO to fit under a lower approval limit isn't allowed;
  - quantities far from the recommendation (over 3x or under a third) are flagged in the confirmation.
"""
from __future__ import annotations

import os

ROLE = "Procurement Assistant"
RESTOCK_TITLE = "Restock recommendation"
RESUBMISSION_TITLE = "Resubmission recommendation"
CREATE_TITLE = "Create a Purchase Order (governed)"
RESUBMIT_TITLE = "Resubmit a rejected Purchase Order (governed)"
CANCEL_TITLE = "Cancel a rejected Purchase Order (governed)"
DEMAND_TITLE = "Recent demand for products"
ACTIVITY_TITLE = "PO activity by front end"
DECISIONS_TITLE = "Procurement Assistant decisions"
LARGE_CHANGE = 3.0
LOOP_WINDOW_MINUTES = 3     # the PO Creation loop runs once a minute: any simulated PO this recent means it's still on

# Is a simulation loop still doing this job? (SIMULATION_MODE=agents expects the PO Creation loop stopped and the PO
# Vetting loop started with --no-resubmit; run_loops_agents.bat does both.)
LOOP_CHECK = """OPTIONAL MATCH (:PurchaseOrder)-[c:PO_CREATED_BY {Source:"simulation"}]->(:Employee)
WHERE c.Date > datetime() - duration({minutes: $m})
WITH count(c) AS created
OPTIONAL MATCH (:PurchaseOrder)-[h:HAS_PREVIOUS_PO {Source:"simulation"}]->(:PurchaseOrder)
WHERE h.Date > datetime() - duration({minutes: $m})
RETURN created, count(h) AS resubmitted"""

LIMITS = """MATCH (l1:RolE {Title:"Level1Approver"}), (l2:RolE {Title:"Level2Approver"}), (l3:RolE {Title:"Level3Approver"})
RETURN l1.ApprovalLimit AS l1, l2.ApprovalLimit AS l2, l3.ApprovalLimit AS l3"""

_ITEMS = {"type": "array", "items": {"type": "object", "properties": {
    "productId": {"type": "string"}, "qty": {"type": "integer", "description": "Whole number of units, above 0."}},
    "required": ["productId", "qty"]}}

TOOLS = [
    {
        "name": "recommend_restock",
        "description": ("Procurement Assistant: which available products need a new PO now, grouped by Supplier, with the "
                        "recommended quantity (the simulation's own rule), estimated cost and the approval level each PO "
                        "will need. Read-only. Run it before create_purchase_orders."),
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "recommend_resubmissions",
        "description": ("Procurement Assistant: rejected POs not yet resubmitted or cancelled -- who rejected each, at which "
                        "level and why -- and what is still needed now (recommended quantities). A PO with nothing still "
                        "needed is a candidate for cancelling. Read-only."),
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "create_purchase_orders",
        "description": ("Procurement Assistant: create the POs the user accepted, one per Supplier, each with the user's "
                        "justification. Quantities may differ from the recommendation. Shows the final list and asks the "
                        "user to confirm (a prompt under the notebook cell, or in the terminal) before anything is written. "
                        "Lines no longer needed when written are left out and reported."),
        "input_schema": {"type": "object", "properties": {"purchaseOrders": {"type": "array", "items": {
            "type": "object", "properties": {
                "supplierId": {"type": "string"}, "items": _ITEMS,
                "justification": {"type": "string", "description": "The user's reason for this PO, in their words."}},
            "required": ["supplierId", "items", "justification"]}}}, "required": ["purchaseOrders"]},
    },
    {
        "name": "resubmit_purchase_orders",
        "description": ("Procurement Assistant: resubmit rejected POs as new POs (same Supplier, products from the rejected "
                        "PO), each with the user's justification. Confirmation as for create_purchase_orders."),
        "input_schema": {"type": "object", "properties": {"resubmissions": {"type": "array", "items": {
            "type": "object", "properties": {
                "rejectedPO": {"type": "string"}, "items": _ITEMS,
                "justification": {"type": "string", "description": "Why it's resubmitted and what changed, in the user's words."}},
            "required": ["rejectedPO", "items", "justification"]}}}, "required": ["resubmissions"]},
    },
    {
        "name": "cancel_rejected_purchase_orders",
        "description": ("Procurement Assistant: cancel rejected POs that shouldn't be resubmitted (they move to "
                        "CancelledPoS), each with the user's reason. Asks the user to confirm first."),
        "input_schema": {"type": "object", "properties": {"cancellations": {"type": "array", "items": {
            "type": "object", "properties": {
                "rejectedPO": {"type": "string"},
                "justification": {"type": "string", "description": "Why it's cancelled, in the user's words."}},
            "required": ["rejectedPO", "justification"]}}}, "required": ["cancellations"]},
    },
]
NAMES = {t["name"] for t in TOOLS}

RULES = """
Procurement Assistant work (this user holds the role):
- "What needs restocking?" -> recommend_restock. Present the POs as a numbered list: Supplier, products with
  recommended quantities, estimated cost, and the approval level each PO will need. Take every count and total
  (POs per approval level, total cost) from the result's "summary"; never count or add them up yourself. Name the
  template the result gives as the source.
- The user accepts all, some, or changes quantities ("accept 1 and 3; for 2 make Chai 50"). Ask for one
  justification per PO if they haven't given one; use their words. Then call create_purchase_orders with only the
  accepted POs. It shows the final list and asks the user to confirm; nothing is written before that.
- Rejected POs -> recommend_resubmissions. For each, the user resubmits (resubmit_purchase_orders, with recomputed
  quantities they may change) or cancels (cancel_rejected_purchase_orders), each with a justification.
- Never suggest splitting a PO, or trimming quantities, to fit under a lower approval limit; decline if asked.
  Splitting POs to avoid an approval level is a procurement control failure. Show the level a PO needs, nothing more.
- If a quantity is far from the recommendation, say so and make sure the justification explains it.
- After writing, report the PO numbers, any lines left out (and why), and the approval level each PO goes to.
- Only say a PO was created, resubmitted or cancelled when the tool result lists it. If the user asks for a write,
  call the tool (it asks them to confirm); never describe a write that didn't happen. If a tool writes nothing,
  say so plainly and give its reason.
- Overlaps: use the result's summary.overlaps, never your own reading of the rows. A product listed there is needed
  once but appears on several rejected POs; suggest resubmitting one PO per product. Resubmitting both is not a
  double order: each write re-checks what is still needed, so the later PO's overlapping lines are left out and
  reported. POs not listed in an overlap have no overlap.
- A rejected PO marked "nothing is still needed" can't be resubmitted: say why from its lines (units in stock, units
  already on active POs, quantities promised to open orders) and offer to cancel it instead.
"""


class Procurement:
    """Bound to a session: needs .aura, .kb, .user, .employee_id and .mode; .confirm() and .interaction_id only for the
    agent's one-call tools (the web UI calls prepare_* and commit_* and confirms in the browser)."""

    SOURCES = ("agent", "ui")

    def __init__(self, session, source: str = "agent"):
        """source is the front end the person is using, recorded as Source on every PO written: "agent" or "ui"."""
        if source not in self.SOURCES:
            raise ValueError(f"source must be one of {self.SOURCES} (got {source!r})")
        self.s = session
        self.source = source
        kb = session.kb
        self.t_restock = kb.template_by_title(RESTOCK_TITLE)
        self.t_resub = kb.template_by_title(RESUBMISSION_TITLE)
        self.t_create = kb.template_by_title(CREATE_TITLE)
        self.t_resubmit = kb.template_by_title(RESUBMIT_TITLE)
        self.t_cancel = kb.template_by_title(CANCEL_TITLE)
        self.t_demand = kb.template_by_title(DEMAND_TITLE)
        self.t_activity = kb.template_by_title(ACTIVITY_TITLE)
        self.t_decisions = kb.template_by_title(DECISIONS_TITLE)
        self.restock: dict[str, dict] = {}        # supplierId -> {"supplier", "lines": {productId: line}}
        self.resub: dict[str, dict] = {}          # rejected PONumber -> recommendation row

    def allowed(self) -> bool:
        """The tools are offered to a Procurement Assistant, and only in SIMULATION_MODE=agents. In full mode the
        simulation's own loops create and resubmit POs, and the agent must not compete with them."""
        return ROLE in self.s.user["roles"] and self.s.mode == "agents"

    def loops_running(self) -> dict:
        """Simulated POs created or resubmitted in the last few minutes: the loop this agent replaces is still on."""
        rows = self.s.aura.read(LOOP_CHECK, {"m": LOOP_WINDOW_MINUTES}).get("rows") or [{}]
        return {"created": rows[0].get("created") or 0, "resubmitted": rows[0].get("resubmitted") or 0}

    def _loop_refusal(self, job: str) -> dict | None:
        running = self.loops_running()
        n = running["created" if job == "create" else "resubmitted"]
        if not n:
            return None
        loop = "PO Creation loop" if job == "create" else "PO Vetting loop's resubmission (po_resubmit)"
        fix = ("stop it; run_loops_agents.bat doesn't start it" if job == "create"
               else "restart the PO Vetting loop with --no-resubmit, as run_loops_agents.bat does")
        return {"refused": f"The {loop} still seems to be running: the simulation wrote {n} in the last "
                           f"{LOOP_WINDOW_MINUTES} minutes. Two writers would order the same need twice, so {fix}, "
                           f"then try again in a few minutes."}

    def check_access(self) -> dict | None:
        """The role and mode check every entry point runs first, whichever front end calls it."""
        if ROLE not in self.s.user["roles"]:
            return {"refused": f"{self.s.user['name']} does not hold the {ROLE} role, so procurement tools can't be "
                               f"used in this session."}
        if self.s.mode != "agents":
            return {"refused": "SIMULATION_MODE is 'full': the simulation's loops create and resubmit POs. Set "
                               "SIMULATION_MODE=agents and run run_loops_agents.bat to hand those jobs to the agent."}
        return None

    def handle(self, name: str, args: dict) -> dict:
        return self.check_access() or getattr(self, name)(args)

    # ---------------- recommendations ----------------

    @staticmethod
    def _summary(rows: list[dict], cost_key: str = "EstimatedCost") -> dict:
        """Counts and totals computed here, so the model never adds them up itself."""
        by_level: dict[str, dict] = {}
        for r in rows:
            lvl = r.get("ApprovalLevelNeeded") or "?"
            entry = by_level.setdefault(lvl, {"POs": 0, "estimatedCost": 0.0, "suppliers": []})
            entry["POs"] += 1
            entry["estimatedCost"] = round(entry["estimatedCost"] + (r.get(cost_key) or 0), 2)
            entry["suppliers"].append(r.get("Supplier"))
        return {"POs": len(rows), "estimatedCost": round(sum(r.get(cost_key) or 0 for r in rows), 2),
                "lines": sum(len(r.get("Lines") or []) for r in rows), "byApprovalLevel": by_level}

    def recommend_restock(self, args: dict) -> dict:
        if (refusal := self.check_access()):
            return refusal
        result = self.s.aura.read(self.t_restock["cypher"])
        result["template"] = self.t_restock["title"]
        if "rows" in result:
            result["summary"] = self._summary(result["rows"])
        if (warning := self._loop_refusal("create")):
            result["warning"] = warning["refused"] + " Recommendations shown, but POs can't be created until then."
        if "rows" in result:
            self.restock = {r["SupplierID"]: {"supplier": r["Supplier"], "lines": {l["ProductID"]: l for l in r["Lines"]}}
                            for r in result["rows"]}
            self._use(self.t_restock)
        return result

    def recommend_resubmissions(self, args: dict) -> dict:
        if (refusal := self.check_access()):
            return refusal
        result = self.s.aura.read(self.t_resub["cypher"])
        result["template"] = self.t_resub["title"]
        if "rows" in result:
            result["summary"] = self._summary(result["rows"])
            result["summary"]["resubmittable"] = [r["RejectedPO"] for r in result["rows"] if r.get("EstimatedCost")]
            result["summary"]["nothingStillNeeded"] = [r["RejectedPO"] for r in result["rows"] if not r.get("EstimatedCost")]
            # Each rejected PO is evaluated on its own, so a product on two of them shows the same need twice.
            needed: dict[str, list[str]] = {}
            names: dict[str, str] = {}
            for r in result["rows"]:
                for l in r["Lines"]:
                    if l.get("RecommendedQt"):
                        needed.setdefault(l["ProductID"], []).append(r["RejectedPO"])
                        names[l["ProductID"]] = l["Product"]
            result["summary"]["overlaps"] = [{"product": names[p], "rejectedPOs": pos} for p, pos in needed.items() if len(pos) > 1]
        if (warning := self._loop_refusal("resubmit")):
            result["warning"] = warning["refused"] + " Recommendations shown, but POs can't be resubmitted until then."
        if "rows" in result:
            self.resub = {r["RejectedPO"]: r for r in result["rows"]}
            self._use(self.t_resub)
        return result

    # ---------------- shared checks and display ----------------

    @staticmethod
    def _bad_items(items: list[dict]) -> str | None:
        if not items:
            return "a PO needs at least one line"
        for it in items:
            q = it.get("qty")
            if not isinstance(q, int) or isinstance(q, bool) or q <= 0:
                return f"quantity for product {it.get('productId')} must be a whole number above 0 (got {q!r})"
        if len({it["productId"] for it in items}) != len(items):
            return "a product appears twice on the same PO"
        return None

    def _level(self, cost: float | None, limits: dict) -> str:
        if cost is None:
            return "unknown (a line wasn't in the recommendation)"
        for lvl in ("l1", "l2", "l3"):
            if cost <= limits[lvl]:
                return lvl.upper()
        return "above the L3 limit: no level can approve it"

    def _lines(self, items: list[dict], recommended: dict[str, dict]) -> tuple[list[dict], float | None, list[str]]:
        """Each requested line with its recommendation, cost estimate and flags."""
        lines, total, flags = [], 0.0, []
        for it in items:
            rec = recommended.get(it["productId"])
            rq = rec.get("RecommendedQt") if rec else None
            # LineCost / RecommendedQt is closer to Aura's exact price than UnitCost, which is rounded to cents.
            unit = ((rec["LineCost"] / rq) if rq and rec.get("LineCost") else rec.get("UnitCost")) if rec else None
            line = {"productId": it["productId"], "product": rec.get("Product") if rec else f"product {it['productId']}",
                    "qty": it["qty"], "recommendedQt": rq if rq else None}
            if not rq:
                flags.append(f"{line['product']}: not in the current recommendation (it will be left out if it isn't needed)")
            elif it["qty"] > LARGE_CHANGE * rq or it["qty"] * LARGE_CHANGE < rq:
                flags.append(f"{line['product']}: {it['qty']} vs {rq} recommended ({it['qty'] / rq:.1f}x)")
            if unit is None or total is None:
                total = None
            else:
                total += unit * it["qty"]
            lines.append(line)
        return lines, (round(total, 2) if total is not None else None), flags

    def _limits(self) -> dict:
        rows = self.s.aura.read(LIMITS).get("rows") or [{}]
        return rows[0]

    def _show(self, header: str, entries: list[dict]) -> None:
        print(f"\n  >>> {header}")
        for i, e in enumerate(entries, 1):
            if e["level"] == "-":          # a cancellation: no cost, no approval level
                print(f"      {i}. {e['title']}")
            else:
                print(f"      {i}. {e['title']}  |  est. {e['cost'] if e['cost'] is not None else '?'}  |  needs {e['level']}")
            for l in e.get("lines", []):
                rec = f" (recommended {l['recommendedQt']})" if l["recommendedQt"] not in (None, l["qty"]) else ""
                print(f"         - {l['product']}: {l['qty']}{rec}")
            for f in e.get("flags", []):
                print(f"         ! {f}")
            print(f"         Justification: {e['justification']}")

    # ---------------- demand and audit (reads; used by the web UI, the agent reaches them through search) ----------------

    def demand(self, lines: list[dict], window_days: float | None = None, cover_days: float | None = None) -> dict:
        """Recent demand for the products of one planned PO, and what the cover-based suggestion would do to it.
        lines: [{"productId": "1", "qty": 55}, ...]. All figures come from the Cypher; the cost and approval level of the
        PO with the suggested quantities are the same arithmetic the review step uses. Advisory: nothing is written."""
        if (refusal := self.check_access()):
            return refusal
        window = float(window_days or os.environ.get("DEMAND_WINDOW_DAYS") or 7)
        cover = float(cover_days or os.environ.get("DEMAND_COVER_DAYS") or 7)
        clean = [{"productId": str(l["productId"]), "qty": int(l.get("qty") or 0)} for l in lines]
        r = self.s.aura.read(self.t_demand["cypher"], {"lines": clean, "windowDays": window, "coverDays": cover})
        if "error" in r:
            return r
        rows = r.get("rows") or []
        limits = self._limits()
        cost_now = round(sum(x["PlannedQt"] * x["UnitCost"] for x in rows), 2)
        cost_sugg = round(sum((x["SuggestedQt"] or x["PlannedQt"]) * x["UnitCost"] for x in rows), 2)
        return {"rows": rows, "windowDays": window, "coverDays": cover,
                "po": {"estimatedCost": cost_now, "approvalLevel": self._level(cost_now, limits),
                       "anySuggestion": any(x["SuggestedQt"] for x in rows),
                       "estimatedCostWithSuggestions": cost_sugg, "approvalLevelWithSuggestions": self._level(cost_sugg, limits)}}

    def audit(self, hours: float = 24) -> dict:
        """POs created, resubmitted and cancelled by front end, and the people's decisions (agent and UI)."""
        if (refusal := self.check_access()):
            return refusal
        act = self.s.aura.read(self.t_activity["cypher"], {"hours": hours})
        dec = self.s.aura.read(self.t_decisions["cypher"], {})
        if "error" in act or "error" in dec:
            return {"error": act.get("error") or dec.get("error")}
        return {"activity": act.get("rows") or [], "decisions": dec.get("rows") or [], "hours": hours}

    # ---------------- writes ----------------
    #
    # Each write is two steps, so any front end can put its own confirmation in between:
    #   prepare_*  validates against the guard rails and computes cost, approval level and flags. Writes nothing.
    #   commit_*   runs the governed Cypher on the prepared entries (re-checking the loop guard first: time passes
    #              between a preview and its confirmation).
    # The agent's tools below are prepare -> _show -> confirm in the terminal/notebook -> commit. The web UI's API
    # calls prepare for its review screen and commit when the person clicks to confirm.

    def _use(self, template: dict) -> None:
        """Provenance in the knowledge store, when this is a chat with an Interaction (the web UI has none)."""
        if getattr(self.s, "interaction_id", None):
            self.s.kb.record_use(self.s.interaction_id, template["name"])

    def prepare_create(self, args: dict) -> dict:
        if (refusal := self.check_access()):
            return refusal
        pos = args.get("purchaseOrders") or []
        if not pos:
            return {"refused": "No POs given."}
        if not self.restock:
            return {"refused": "Run recommend_restock first, so the POs are checked against the current recommendation."}
        if (refusal := self._loop_refusal("create")):
            return refusal
        suppliers = [p["supplierId"] for p in pos]
        if len(set(suppliers)) != len(suppliers):
            return {"refused": "One PO per Supplier per batch. Splitting a Supplier's order into several POs (for example "
                               "to stay under a lower approval limit) isn't allowed; combine the lines into one PO."}
        limits, entries = self._limits(), []
        for p in pos:
            if not (p.get("justification") or "").strip():
                return {"refused": f"PO for Supplier {p['supplierId']} has no justification. Ask the user for one."}
            if (bad := self._bad_items(p["items"])):
                return {"refused": f"PO for Supplier {p['supplierId']}: {bad}."}
            rec = self.restock.get(p["supplierId"], {})
            lines, cost, flags = self._lines(p["items"], rec.get("lines", {}))
            entries.append({"title": f"New PO for {rec.get('supplier', 'Supplier ' + p['supplierId'])}", "lines": lines,
                            "cost": cost, "level": self._level(cost, limits), "flags": flags,
                            "justification": p["justification"].strip(), "p": p})
        return {"header": f"Create {len(entries)} purchase order(s) as {self.s.user['name']}:", "entries": entries}

    def commit_create(self, entries: list[dict]) -> dict:
        if (refusal := self.check_access()):
            return refusal
        if (refusal := self._loop_refusal("create")):
            return refusal
        limits = self._limits()
        created, left_out = [], []
        for e in entries:
            p = e["p"]
            items = [{"productId": l["productId"], "qty": l["qty"], "recommendedQt": l["recommendedQt"]} for l in e["lines"]]
            r = self.s.aura.run_governed(self.t_create["cypher"], {
                "requesterId": self.s.employee_id, "supplierId": p["supplierId"], "items": items,
                "justification": e["justification"], "source": self.source})
            if "error" in r:
                return {"error": r["error"], "created": created, "left_out": left_out}
            row = (r.get("rows") or [None])[0]
            written = set(row["ProductIDs"]) if row else set()
            for l in e["lines"]:
                if l["productId"] not in written:
                    left_out.append({"supplierId": p["supplierId"], "product": l["product"],
                                     "reason": "not needed any more (already covered by a PO, above the restock threshold, "
                                               "not supplied by this Supplier, or not available)"})
            if row:
                created.append({**row, "supplierId": p["supplierId"], "approvalLevel": self._level(row["EstimatedCost"], limits)})
        if created:
            self._use(self.t_create)
            self.restock = {}            # stale now: ask for a fresh recommendation before the next batch
        return {"created": created, "left_out": left_out}

    def create_purchase_orders(self, args: dict) -> dict:
        prep = self.prepare_create(args)
        if "entries" not in prep:
            return prep
        self._show(prep["header"], prep["entries"])
        if not self.s.confirm("      Create them? [y/N] "):
            return {"refused": "The user did not confirm. Nothing was written."}
        return self.commit_create(prep["entries"])

    def prepare_resubmit(self, args: dict) -> dict:
        if (refusal := self.check_access()):
            return refusal
        subs = args.get("resubmissions") or []
        if not subs:
            return {"refused": "No resubmissions given."}
        if not self.resub:
            return {"refused": "Run recommend_resubmissions first."}
        if (refusal := self._loop_refusal("resubmit")):
            return refusal
        limits, entries = self._limits(), []
        for sbm in subs:
            rec = self.resub.get(sbm["rejectedPO"])
            if not rec:
                return {"refused": f"{sbm['rejectedPO']} isn't in the current resubmission recommendation."}
            if not (sbm.get("justification") or "").strip():
                return {"refused": f"{sbm['rejectedPO']} has no justification. Ask the user for one."}
            if not any(l.get("RecommendedQt") for l in rec["Lines"]):
                why = "; ".join(f"{l['Product']}: {l.get('UnitsInStock')} in stock, {l.get('OnActivePOs')} on active POs, "
                                f"{l.get('OpenOrderQty')} promised to open orders, threshold {l.get('StockThreshold')}"
                                for l in rec["Lines"])
                return {"refused": f"{sbm['rejectedPO']} can't be resubmitted: nothing on it is still needed ({why}). "
                                   f"Offer to cancel it instead. Nothing was written."}
            if (bad := self._bad_items(sbm["items"])):
                return {"refused": f"{sbm['rejectedPO']}: {bad}."}
            recd = {l["ProductID"]: l for l in rec["Lines"]}
            lines, cost, flags = self._lines(sbm["items"], recd)
            entries.append({"title": f"Resubmit {sbm['rejectedPO']} ({rec['Supplier']})", "lines": lines, "cost": cost,
                            "level": self._level(cost, limits), "flags": flags,
                            "justification": sbm["justification"].strip(), "p": sbm})
        return {"header": f"Resubmit {len(entries)} rejected PO(s) as {self.s.user['name']}:", "entries": entries}

    def commit_resubmit(self, entries: list[dict]) -> dict:
        if (refusal := self.check_access()):
            return refusal
        if (refusal := self._loop_refusal("resubmit")):
            return refusal
        limits = self._limits()
        done, left_out, refused = [], [], []
        for e in entries:
            items = [{"productId": l["productId"], "qty": l["qty"], "recommendedQt": l["recommendedQt"]} for l in e["lines"]]
            r = self.s.aura.run_governed(self.t_resubmit["cypher"], {
                "requesterId": self.s.employee_id, "rejectedPO": e["p"]["rejectedPO"], "items": items,
                "justification": e["justification"], "source": self.source})
            if "error" in r:
                return {"error": r["error"], "resubmitted": done, "left_out": left_out}
            row = (r.get("rows") or [None])[0]
            if not row:
                refused.append({"rejectedPO": e["p"]["rejectedPO"], "reason": "nothing written: the PO was already resubmitted "
                                "or cancelled, or none of its lines is still needed"})
                continue
            written = set(row["ProductIDs"])
            left_out += [{"rejectedPO": e["p"]["rejectedPO"], "product": l["product"], "reason": "not needed any more"}
                         for l in e["lines"] if l["productId"] not in written]
            done.append({**row, "approvalLevel": self._level(row["EstimatedCost"], limits)})
        if done:
            self._use(self.t_resubmit)
        self.resub = {}
        return {"resubmitted": done, "left_out": left_out, "not_resubmitted": refused}

    def resubmit_purchase_orders(self, args: dict) -> dict:
        prep = self.prepare_resubmit(args)
        if "entries" not in prep:
            return prep
        self._show(prep["header"], prep["entries"])
        if not self.s.confirm("      Resubmit them? [y/N] "):
            return {"refused": "The user did not confirm. Nothing was written."}
        return self.commit_resubmit(prep["entries"])

    def prepare_cancel(self, args: dict) -> dict:
        if (refusal := self.check_access()):
            return refusal
        cancels = args.get("cancellations") or []
        if not cancels:
            return {"refused": "No cancellations given."}
        for c in cancels:
            if not (c.get("justification") or "").strip():
                return {"refused": f"{c['rejectedPO']} has no justification. Ask the user for one."}
        def title(po: str) -> str:
            rec = self.resub.get(po)
            if not rec:
                return f"Cancel {po}"
            rej = rec.get("Rejection") or {}
            by = f", rejected at {rej.get('Level')} by {rej.get('RejectedBy')}" if rej.get("RejectedBy") else ""
            return f"Cancel {po} ({rec.get('Supplier')}{by})"
        entries = [{"title": title(c["rejectedPO"]), "cost": None, "level": "-", "justification": c["justification"].strip(),
                    "lines": [], "flags": [], "p": c} for c in cancels]
        return {"header": f"Cancel {len(entries)} rejected PO(s) as {self.s.user['name']}:", "entries": entries}

    def commit_cancel(self, entries: list[dict]) -> dict:
        if (refusal := self.check_access()):
            return refusal
        done, refused = [], []
        for e in entries:
            po = e["p"]["rejectedPO"]
            r = self.s.aura.run_governed(self.t_cancel["cypher"], {
                "requesterId": self.s.employee_id, "rejectedPO": po, "justification": e["justification"],
                "source": self.source})
            if "error" in r:
                return {"error": r["error"], "cancelled": done}
            if r.get("rows"):
                done.append(po)
            else:
                refused.append({"rejectedPO": po, "reason": "not in RejectedPoS, or already resubmitted"})
        if done:
            self._use(self.t_cancel)
        return {"cancelled": done, "not_cancelled": refused}

    def cancel_rejected_purchase_orders(self, args: dict) -> dict:
        prep = self.prepare_cancel(args)
        if "entries" not in prep:
            return prep
        self._show(prep["header"], prep["entries"])
        if not self.s.confirm("      Cancel them? [y/N] "):
            return {"refused": "The user did not confirm. Nothing was written."}
        return self.commit_cancel(prep["entries"])
