"""
Offline tests of the web UI's API (api/main.py): no Anthropic API, no Neo4j Aura.
Aura is replaced by relate holding the small procurement graph (tests/toy_procurement.py), and Claude by a fake that
records what it was given. Same stand-in as tests/test_procurement_offline.py.

  python tests/test_procurement_api.py
"""
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
for sub in ("agent", "kb", "tests", "sandbox", ""):
    sys.path.insert(0, str(ROOT / sub) if sub else str(ROOT))

from fastapi.testclient import TestClient  # noqa: E402

from api.main import create_app, DRAFT_SYSTEM  # noqa: E402
from test_procurement_offline import ProcurementAura, q  # noqa: E402

os.environ.pop("DEMAND_WINDOW_DAYS", None)
os.environ.pop("DEMAND_COVER_DAYS", None)


OPENED = []


class ThreadedAura:
    """The relate stand-in for Aura, with every call on one thread: relate connections are thread-affine, and FastAPI
    runs endpoints on a thread pool. (The real Neo4j driver is thread-safe; this is a test-only concern.)"""

    def __init__(self):
        self._pool = ThreadPoolExecutor(max_workers=1)
        self._inner = self._pool.submit(ProcurementAura).result()
        self.database = self._inner.database
        outer = self

        class Conn:
            def execute(self, cypher, params=None):
                return outer._pool.submit(lambda: list(outer._inner.conn.execute(cypher, params or {}))).result()
        self.conn = Conn()
        OPENED.append(self)

    def close(self):
        self._pool.submit(self._inner.conn.close).result()
        self._pool.shutdown()

    def __getattr__(self, name):
        fn = getattr(self._inner, name)
        return lambda *a, **k: self._pool.submit(fn, *a, **k).result()


class FakeLLM:
    def __init__(self):
        self.calls = []

    def __call__(self, system, prompt):
        self.calls.append((system, prompt))
        return "We need Chai for open demand."


def main():
    checks = []

    def check(name, cond):
        checks.append(bool(cond))
        print(f"{'PASS' if cond else 'FAIL'}  {name}")

    aura, llm = ThreadedAura(), FakeLLM()
    app = create_app(aura=aura, llm=llm, mode="agents")
    c = TestClient(app)

    # Sign-in and access
    check("not signed in: 401", c.get("/api/restock").status_code == 401)
    check("the sign-in picker lists the Procurement Assistants", [e["employeeId"] for e in c.get("/api/employees").json()] == ["16", "17"])
    cfg = c.get("/api/config").json()
    check("config says agents mode and that drafts are available", cfg["mode"] == "agents" and cfg["drafts"] is True)
    gl = TestClient(app)
    g = gl.post("/api/session", json={"employeeId": "12"}).json()
    check("an L1 approver can sign in but can't use procurement, with the reason",
          g["canUseProcurement"] is False and "Procurement Assistant" in g["reason"])
    check("...and is refused (409) by every procurement endpoint", gl.get("/api/restock").status_code == 409
          and gl.post("/api/cancellations/preview", json=[{"rejectedPO": "PO-R1", "justification": "x"}]).status_code == 409)
    check("an unknown employee gets 404", c.post("/api/session", json={"employeeId": "999"}).status_code == 404)
    me = c.post("/api/session", json={"employeeId": "16"}).json()
    check("Albert Camus signs in with procurement access", me["user"]["name"] == "Albert Camus" and me["canUseProcurement"])
    st = c.get("/api/status").json()
    check("status: mode, approval limits and the loop check", st["mode"] == "agents" and st["limits"]["l1"] == 5000.0
          and st["loops"]["created"] == 0 and st["access"] is None)

    # Restock with demand
    rs = c.get("/api/restock").json()
    by = {r["SupplierID"]: r for r in rs["rows"]}
    d1 = by["1"]["demand"]
    check("restock: the agent's recommendation (Chai 55, Aniseed Syrup 45)",
          [l["RecommendedQt"] for l in by["1"]["Lines"]] == [55] and [l["RecommendedQt"] for l in by["2"]["Lines"]] == [45])
    check("each recommended PO comes with recent demand: Chai 450/day, suggestion 3145, which would need L3",
          d1["rows"][0]["UnitsPerDay"] == 450.0 and d1["rows"][0]["SuggestedQt"] == 3145
          and d1["po"]["approvalLevel"] == "L1" and d1["po"]["approvalLevelWithSuggestions"] == "L3")
    dm = c.post("/api/demand", json={"items": [{"productId": "1", "qty": 3145}]}).json()
    check("changing the quantity recomputes cover: 3145 more Chai covers the 7 days, no further suggestion",
          dm["rows"][0]["DaysOfCoverAfterPO"] == 7.0 and dm["rows"][0]["SuggestedQt"] is None and dm["po"]["approvalLevel"] == "L3")

    # Justification draft: facts gathered by the server, nothing written
    dr = c.post("/api/justification-draft", json={"kind": "create", "supplierId": "1", "items": [{"productId": "1", "qty": 200}]}).json()
    system, prompt = llm.calls[-1]
    check("a draft comes back from the model, with the facts it was given", dr["draft"].startswith("We need Chai") and dr["facts"] == prompt)
    check("the facts are the graph's: supplier, quantity vs recommendation, stock and demand",
          "Exotic Liquids" in prompt and "ordering 200 (recommended 55)" in prompt and "about 450.0 a day" in prompt)
    check("the system prompt forbids invented facts and splitting", system == DRAFT_SYSTEM and "ONLY the facts" in system and "splitting" in system)
    check("a draft for a supplier not in the recommendation is refused",
          c.post("/api/justification-draft", json={"kind": "create", "supplierId": "99", "items": []}).status_code == 409)
    check("drafting writes nothing", q(aura, "MATCH (:NewPoS)-->(po) RETURN count(po) AS n")[0]["n"] == 0)

    # Preview and commit
    split = c.post("/api/purchase-orders/preview", json=[
        {"supplierId": "2", "items": [{"productId": "3", "qty": 20}], "justification": "a"},
        {"supplierId": "2", "items": [{"productId": "3", "qty": 25}], "justification": "b"}])
    check("splitting a Supplier's PO is refused with the agent's message", split.status_code == 409 and "Splitting" in split.json()["detail"])
    nojust = c.post("/api/purchase-orders/preview", json=[{"supplierId": "1", "items": [{"productId": "1", "qty": 55}]}])
    check("a PO without a justification is refused", nojust.status_code == 409 and "justification" in nojust.json()["detail"])
    pv = c.post("/api/purchase-orders/preview", json=[
        {"supplierId": "1", "items": [{"productId": "1", "qty": 200}], "justification": "We need Chai for open demand."}]).json()
    e = pv["entries"][0]
    check("preview: cost, level, recommended vs ordered, a flag for 3.6x, no raw request copy",
          e["cost"] == 1400.0 and e["level"] == "L1" and e["lines"][0]["recommendedQt"] == 55 and e["flags"] and "p" not in e)
    check("preview writes nothing", q(aura, "MATCH (:NewPoS)-->(po) RETURN count(po) AS n")[0]["n"] == 0)
    check("committing with an unknown review id is refused", c.post("/api/purchase-orders", json={"previewId": "nope"}).status_code == 409)
    check("a review can't be committed as another kind (cancel)", c.post("/api/cancellations", json={"previewId": pv["previewId"]}).status_code == 409)
    pv = c.post("/api/purchase-orders/preview", json=[
        {"supplierId": "1", "items": [{"productId": "1", "qty": 200}], "justification": "We need Chai for open demand."}]).json()
    done = c.post("/api/purchase-orders", json={"previewId": pv["previewId"]}).json()
    row = q(aura, """MATCH (po:PurchaseOrder {PONumber:$n})-[c:PO_CREATED_BY]->(e:Employee), (po)-[it:HAS_PO_ITEM]->()
                     RETURN c.Source AS s, e.EmployeeID AS by, c.Justification AS j, it.POqt AS qt, it.RecommendedQt AS rec""",
            {"n": done["created"][0]["PONumber"]})
    check("commit writes the PO: Source 'ui', the signed-in assistant, the submitted justification, 200 vs 55",
          row == [{"s": "ui", "by": "16", "j": "We need Chai for open demand.", "qt": 200, "rec": 55}])
    check("a review can only be committed once", c.post("/api/purchase-orders", json={"previewId": pv["previewId"]}).status_code == 409)
    old = c.post("/api/purchase-orders/preview", json=[
        {"supplierId": "2", "items": [{"productId": "3", "qty": 45}], "justification": "x"}])
    check("after a commit, a new batch needs a fresh recommendation (as for the agent)", old.status_code == 409)

    # Stale review and the loop guard at commit time
    c.get("/api/restock")
    pv2 = c.post("/api/purchase-orders/preview", json=[
        {"supplierId": "2", "items": [{"productId": "3", "qty": 45}], "justification": "Open order 90001 waiting."}]).json()
    s = next(iter(x for x in app.state.sessions.values() if x.employee_id == "16"))
    s.previews[pv2["previewId"]]["at"] -= 16 * 60
    check("a review older than 15 minutes must be done again", c.post("/api/purchase-orders", json={"previewId": pv2["previewId"]}).status_code == 409)
    c.get("/api/restock")
    pv3 = c.post("/api/purchase-orders/preview", json=[
        {"supplierId": "2", "items": [{"productId": "3", "qty": 45}], "justification": "Open order 90001 waiting."}]).json()
    q(aura, """MATCH (s:Supplier {SupplierID:"1"}), (e:Employee {EmployeeID:"17"})
               CREATE (po:PurchaseOrder {PONumber:"PO-SIM", PODate:datetime()})-[:PO_FOR_SUPPLIER]->(s),
                      (po)-[:PO_CREATED_BY {Date:datetime(), Source:"simulation"}]->(e)""")
    late = c.post("/api/purchase-orders", json={"previewId": pv3["previewId"]})
    check("the loop guard is re-checked at commit: 409 with the reason", late.status_code == 409 and "still seems to be running" in late.json()["detail"])
    check("status shows the loop as running", c.get("/api/status").json()["loops"]["created"] == 1)
    q(aura, "MATCH (:PurchaseOrder {PONumber:'PO-SIM'})-[c:PO_CREATED_BY]->() SET c.Date = datetime() - duration({minutes: 10})")

    au1 = c.get("/api/audit").json()
    check("the audit separates the front ends: the UI's PO and the simulation's",
          {(r["Source"], r["Action"]): r["POs"] for r in au1["activity"]} == {("simulation", "created"): 1, ("ui", "created"): 1})

    # Resubmit and cancel, as another assistant, on a fresh graph (Albert's 200 Chai above covers what PO-R1 needed)
    aura2 = ThreadedAura()
    app2 = create_app(aura=aura2, llm=llm, mode="agents")
    b = TestClient(app2)
    b.post("/api/session", json={"employeeId": "17"})
    rr = b.get("/api/resubmissions").json()
    check("rejected POs come with who rejected them, and demand for what's still needed",
          {r["RejectedPO"]: r["Rejection"]["RejectedBy"] for r in rr["rows"]} == {"PO-R1": "Gloria Gaynor", "PO-R2": "Gloria Gaynor"}
          and next(r for r in rr["rows"] if r["RejectedPO"] == "PO-R1")["demand"]["rows"][0]["Product"] == "Chai"
          and next(r for r in rr["rows"] if r["RejectedPO"] == "PO-R2")["demand"] is None)
    check("each rejected PO says who raised it (Bernard Shaw, 17), even when the PO predates Source",
          {r["RejectedPO"]: r["RaisedBy"] for r in rr["rows"]}["PO-R1"] == {"EmployeeID": "17", "Name": "Bernard Shaw", "Source": None})
    b.post("/api/justification-draft", json={"kind": "resubmit", "rejectedPO": "PO-R1", "items": [{"productId": "1", "qty": 25}]})
    check("a resubmission draft gets the rejecter's level and comment", "rejected at L1 by Gloria Gaynor" in llm.calls[-1][1]
          and "Quantity too high for current demand." in llm.calls[-1][1])
    b.post("/api/justification-draft", json={"kind": "cancel", "rejectedPO": "PO-R2"})
    check("a cancellation draft gets what's still needed and whether it can be ordered", "not orderable" in llm.calls[-1][1])
    rp = b.post("/api/resubmissions/preview", json=[{"rejectedPO": "PO-R1", "items": [{"productId": "1", "qty": 25}],
                                                     "justification": "Lower quantity, as L1 asked."}]).json()
    rd = b.post("/api/resubmissions", json={"previewId": rp["previewId"]}).json()
    cp = b.post("/api/cancellations/preview", json=[{"rejectedPO": "PO-R2", "justification": "Discontinued."}]).json()
    cd = b.post("/api/cancellations", json={"previewId": cp["previewId"]}).json()
    check("resubmit and cancel through the API", len(rd["resubmitted"]) == 1 and cd["cancelled"] == ["PO-R2"])
    au = b.get("/api/audit").json()
    acts = {(r["Source"], r["Action"]): r["POs"] for r in au["activity"]}
    check("the audit counts the resubmission and the cancellation as the UI's", acts == {("ui", "cancelled"): 1, ("ui", "resubmitted"): 1})
    check("the decisions list shows who did each, and Source 'ui'",
          {(d["Action"], d["By"], d["Source"]) for d in au["decisions"]} ==
          {("resubmitted", "Bernard Shaw", "ui"), ("cancelled", "Bernard Shaw", "ui")})

    # Sign-out, full mode, and no API key
    b.delete("/api/session")
    check("after signing out: 401", b.get("/api/status").status_code == 401)
    full = TestClient(create_app(aura=ThreadedAura(), llm=None, mode="full"))
    f = full.post("/api/session", json={"employeeId": "16"}).json()
    check("full mode: a Procurement Assistant signs in, but procurement is refused, with the reason",
          f["canUseProcurement"] is False and "full" in f["reason"] and full.get("/api/restock").status_code == 409)
    nokey = TestClient(create_app(aura=ThreadedAura(), llm=None, mode="agents"))
    nokey.post("/api/session", json={"employeeId": "16"})
    nokey.get("/api/restock")
    check("without an API key: config says no drafts, and the draft endpoint answers 503",
          nokey.get("/api/config").json()["drafts"] is False
          and nokey.post("/api/justification-draft", json={"kind": "create", "supplierId": "1", "items": []}).status_code == 503)

    for a in OPENED:
        a.close()
    def broken(system, prompt):
        raise RuntimeError("Your credit balance is too low to access the Anthropic API.")
    bad = TestClient(create_app(aura=ThreadedAura(), llm=broken, mode="agents"))
    bad.post("/api/session", json={"employeeId": "16"})
    bad.get("/api/restock")
    r = bad.post("/api/justification-draft", json={"kind": "create", "supplierId": "1", "items": [{"productId": "1", "qty": 55}]})
    check("a failing AI call answers 502 with the API's own reason, so the UI can show it",
          r.status_code == 502 and "credit balance is too low" in r.json()["detail"])

    print(f"\n{sum(checks)}/{len(checks)} checks passed")
    return all(checks)


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
