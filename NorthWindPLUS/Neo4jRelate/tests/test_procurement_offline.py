"""
Offline tests of the Procurement Assistant agent and its web-UI path (model v2.3.3): no Anthropic API, no Neo4j Aura.
Aura is replaced by relate holding a small procurement graph (tests/toy_procurement.py); a scripted client stands in
for Claude. The governed Cypher runs as written, minus the APOC lock lines (relate has no APOC).

  python tests/test_procurement_offline.py
"""
import io
import itertools
import os
import shutil
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
for sub in ("agent", "kb", "tests", "sandbox"):
    sys.path.insert(0, str(ROOT / sub))

import relate  # noqa: E402
import agent as agent_mod  # noqa: E402
import procurement  # noqa: E402
import whatif  # noqa: E402
from build_kb import build  # noqa: E402
from kb_query import KnowledgeBase  # noqa: E402
from model_templates import ModelTemplates  # noqa: E402
from toy_procurement import TOY_PROCUREMENT  # noqa: E402
from toy_vetting import TOY_VETTING  # noqa: E402
import test_agent_offline as base  # noqa: E402

os.environ["SIMULATION_MODE"] = "agents"       # the mode these tools belong to; section 9 tests "full"
TMP = Path(tempfile.mkdtemp(prefix="proc-test-"))
STORE = TMP / "kb.rl"
_COPIES = itertools.count()


class ProcurementAura(base.RelateAura):
    def __init__(self, graph=TOY_PROCUREMENT):
        self.database = "toy"
        self.conn = relate.connect(":memory:")
        self.conn.execute(graph)


def session(employee_id, steps=None, answers=None, aura=None):
    s = agent_mod.Session.__new__(agent_mod.Session)
    s.client, s.model = base.ScriptedClient(steps or []), "scripted"
    own = TMP / f"kb-{employee_id}-{next(_COPIES)}.rl"     # relate allows one writer per store: one copy per session
    shutil.copy2(STORE, own)
    s.kb = KnowledgeBase(own, read_only=False)
    s.aura = aura or ProcurementAura()
    s.employee_id = employee_id
    s.user = s.aura.whoami(employee_id)
    s.messages = []
    s._setup_tools()
    s.log_path = TMP / f"log-{employee_id}.jsonl"
    s.system = s._system_prompt()
    s._reset_question_state()
    s.interaction_id = s.kb.start_interaction("test", employee_id, "scripted")
    replies = iter(answers or [])
    s.confirm = lambda prompt: next(replies, "n") == "y"
    return s


def q(aura, cypher, params=None):
    return [dict(r) for r in aura.conn.execute(cypher, params or {})]


def quiet(fn, *a):
    with redirect_stdout(io.StringIO()) as out:
        result = fn(*a)
    return result, out.getvalue()


def main():
    checks = []

    def check(name, cond):
        checks.append(bool(cond))
        print(f"{'PASS' if cond else 'FAIL'}  {name}")

    build(STORE)
    kb = KnowledgeBase(STORE)
    gov = {r["t"][:40]: r["g"] for r in kb._rows("MATCH (q:QueryTemplate) WHERE q.title CONTAINS 'Purchase Order (governed)' "
                                                 "RETURN q.title AS t, q.governance AS g")}
    kb.close()
    check("the three procurement commands are governed templates in the knowledge store",
          len(gov) == 3 and set(gov.values()) == {"governed"})

    # 1. Tools by role
    albert, gloria = session("16"), session("12")
    check("a Procurement Assistant gets the procurement tools, not the approval-limit change",
          procurement.NAMES <= albert.offered and "change_approval_bands" not in albert.offered)
    check("an L1 approver gets no procurement tools", not (procurement.NAMES & gloria.offered))
    check("the procurement rules are in the Procurement Assistant's prompt only",
          "Never suggest splitting a PO" in albert.system[0]["text"] and "Never suggest splitting" not in gloria.system[0]["text"])
    check("calling a procurement tool without the role is refused", "refused" in gloria.tool("recommend_restock", {}))
    gloria.close()

    # 2. Recommendations
    rec = albert.tool("recommend_restock", {})
    by_sup = {r["SupplierID"]: r for r in rec["rows"]}
    chai = by_sup["1"]["Lines"]
    check("restock recommendation: Chai 55 for Supplier 1, Aniseed Syrup 45 for Supplier 2 (the loop's formula)",
          [(l["Product"], l["RecommendedQt"]) for l in chai] == [("Chai", 55)]
          and [(l["Product"], l["RecommendedQt"]) for l in by_sup["2"]["Lines"]] == [("Aniseed Syrup", 45)])
    check("unavailable and well-stocked products aren't recommended",
          all(l["Product"] not in ("Chang", "Discontinued Spice") for r in rec["rows"] for l in r["Lines"]))
    check("each PO shows the approval level it will need", by_sup["1"]["ApprovalLevelNeeded"] == "L1")
    check("the recommendation carries its counts and totals, and names its template",
          rec["summary"]["POs"] == 2 and rec["summary"]["byApprovalLevel"]["L1"]["POs"] == 2
          and rec["summary"]["estimatedCost"] == 700.0 and rec["template"].startswith("Restock recommendation"))

    # 3. Guard rails before anything is written
    fresh = session("17")
    check("create refused before a recommendation in this session",
          "refused" in fresh.tool("create_purchase_orders", {"purchaseOrders": [
              {"supplierId": "1", "items": [{"productId": "1", "qty": 55}], "justification": "x"}]}))
    fresh.close()
    split = albert.tool("create_purchase_orders", {"purchaseOrders": [
        {"supplierId": "2", "items": [{"productId": "3", "qty": 20}], "justification": "part 1"},
        {"supplierId": "2", "items": [{"productId": "3", "qty": 25}], "justification": "part 2"}]})
    check("two POs for one Supplier in a batch are refused (no splitting)", "refused" in split and "Splitting" in split["refused"])
    check("a PO without a justification is refused", "refused" in albert.tool("create_purchase_orders", {"purchaseOrders": [
        {"supplierId": "1", "items": [{"productId": "1", "qty": 55}], "justification": "  "}]}))
    check("a fractional or zero quantity is refused", "refused" in albert.tool("create_purchase_orders", {"purchaseOrders": [
        {"supplierId": "1", "items": [{"productId": "1", "qty": 0}], "justification": "ok"}]}))
    _, _, flags = albert.procurement._lines([{"productId": "3", "qty": 200}], {l["ProductID"]: l for l in by_sup["2"]["Lines"]})
    check("a quantity over 3x the recommendation is flagged", flags and "4.4x" in flags[0])
    declined, shown = quiet(albert.tool, "create_purchase_orders", {"purchaseOrders": [
        {"supplierId": "1", "items": [{"productId": "1", "qty": 50}], "justification": "Restock Chai."}]})
    check("declining at the prompt writes nothing", "refused" in declined
          and q(albert.aura, "MATCH (:NewPoS)-->(po) RETURN count(po) AS n")[0]["n"] == 0)
    check("the confirmation shows recommended vs ordered, cost and approval level",
          "Chai: 50 (recommended 55)" in shown and "needs L1" in shown)

    # 4. Creating: accept with a change, plus a line that isn't needed
    albert.confirm = lambda prompt: True
    out, shown = quiet(albert.tool, "create_purchase_orders", {"purchaseOrders": [
        {"supplierId": "1", "items": [{"productId": "1", "qty": 50}, {"productId": "2", "qty": 5}],
         "justification": "Restock Chai for the weekend; 50 is enough."}]})
    created = out["created"]
    check("one PO created; the unneeded Chang line left out and reported",
          len(created) == 1 and created[0]["ProductIDs"] == ["1"] and [l["product"] for l in out["left_out"]] == ["product 2"])
    row = q(albert.aura, """MATCH (:NewPoS)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {PONumber:$n})-[c:PO_CREATED_BY]->(e:Employee),
                               (po)-[it:HAS_PO_ITEM]->(p:Product), (po)-[:PO_FOR_SUPPLIER]->(s:Supplier)
                            RETURN e.EmployeeID AS by, c.Source AS src, c.Justification AS j, c.Date IS NOT NULL AS dated,
                                   it.POqt AS qt, it.RecommendedQt AS rec, s.SupplierID AS sup""", {"n": created[0]["PONumber"]})[0]
    check("the PO records who, when, why, Source 'agent', and ordered 50 vs recommended 55",
          row == {"by": "16", "src": "agent", "j": "Restock Chai for the weekend; 50 is enough.", "dated": True,
                  "qt": 50, "rec": 55, "sup": "1"})
    check("a new batch needs a fresh recommendation", "refused" in albert.tool("create_purchase_orders", {"purchaseOrders": [
        {"supplierId": "2", "items": [{"productId": "3", "qty": 45}], "justification": "x"}]}))
    rec2 = albert.tool("recommend_restock", {})
    check("Chai is no longer recommended once its PO exists", [r["SupplierID"] for r in rec2["rows"]] == ["2"])

    # 5. A race: the need is covered by someone else between recommendation and write
    q(albert.aura, """MATCH (n:NewPoS), (s:Supplier {SupplierID:"2"}), (p:Product {ProductID:"3"}), (e:Employee {EmployeeID:"17"})
                      CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {PONumber:"PO-OTHER", PODate:datetime()}),
                             (po)-[:PO_FOR_SUPPLIER]->(s), (po)-[:PO_CREATED_BY {Source:"agent"}]->(e),
                             (po)-[:HAS_PO_ITEM {POqt:45, POPriceDiscount:0.7}]->(p)""")
    raced, _ = quiet(albert.tool, "create_purchase_orders", {"purchaseOrders": [
        {"supplierId": "2", "items": [{"productId": "3", "qty": 45}], "justification": "Open order 90001 waiting."}]})
    check("a line covered since the recommendation is left out, not ordered twice",
          raced["created"] == [] and [l["product"] for l in raced["left_out"]] == ["Aniseed Syrup"])
    hist = q(albert.aura, albert.kb.template_by_title("Procurement Assistant decisions")["cypher"])
    mine = [h for h in hist if h["PONumber"] == created[0]["PONumber"]][0]
    check("the decisions history shows the PO, its justification and the changed line (Chai 50 vs 55)",
          mine["Action"] == "created" and mine["Justification"].startswith("Restock Chai")
          and mine["ChangedLines"] == [{"Product": "Chai", "Ordered": 50, "Recommended": 55}])
    albert.close()

    # 6. Resubmission and cancellation
    bernard = session("17", answers=["y", "y", "y"])
    rs = {r["RejectedPO"]: r for r in bernard.tool("recommend_resubmissions", {})["rows"]}
    check("resubmission recommendation: PO-R1 Chai 25, rejection by Gloria Gaynor at L1 with her comment",
          rs["PO-R1"]["Lines"][0]["RecommendedQt"] == 25 and rs["PO-R1"]["Rejection"]["RejectedBy"] == "Gloria Gaynor"
          and rs["PO-R1"]["Rejection"]["Level"] == "L1")
    summ = bernard.procurement.recommend_resubmissions({})["summary"]
    check("resubmission summary: resubmittable vs nothing still needed, computed by the tool",
          summ["resubmittable"] == ["PO-R1"] and summ["nothingStillNeeded"] == ["PO-R2"] and summ["overlaps"] == [])
    check("PO-R2 (discontinued product) is flagged as a candidate for cancelling",
          rs["PO-R2"]["EstimatedCost"] == 0 and "cancelling" in rs["PO-R2"]["ApprovalLevelNeeded"])
    nothing = bernard.tool("resubmit_purchase_orders", {"resubmissions": [
        {"rejectedPO": "PO-R2", "items": [{"productId": "4", "qty": 40}], "justification": "Try again."}]})
    check("resubmitting a PO with nothing still needed is refused up front, with the reason and the cancel option",
          "refused" in nothing and "nothing on it is still needed" in nothing["refused"] and "cancel" in nothing["refused"])
    res, _ = quiet(bernard.tool, "resubmit_purchase_orders", {"resubmissions": [
        {"rejectedPO": "PO-R1", "items": [{"productId": "1", "qty": 25}], "justification": "Lower quantity, as L1 asked."}]})
    check("PO-R1 resubmitted as a new PO", len(res["resubmitted"]) == 1 and res["resubmitted"][0]["ResubmittedFrom"] == "PO-R1")
    link = q(bernard.aura, """MATCH (:NewPoS)-->(po:PurchaseOrder)-[h:HAS_PREVIOUS_PO]->(:PurchaseOrder {PONumber:"PO-R1"}),
                                  (po)-[c:PO_CREATED_BY]->(e:Employee), (po)-[it:HAS_PO_ITEM]->()
                              RETURN h.Resubmission_Justification AS j, h.Source AS hs, h.Date IS NOT NULL AS dated,
                                     e.EmployeeID AS by, c.Source AS cs, it.RecommendedQt AS rec""")
    check("the resubmission records justification, Date, Source 'agent', the signed-in assistant and RecommendedQt",
          link == [{"j": "Lower quantity, as L1 asked.", "hs": "agent", "dated": True, "by": "17", "cs": "agent", "rec": 25}])
    can, _ = quiet(bernard.tool, "cancel_rejected_purchase_orders", {"cancellations": [
        {"rejectedPO": "PO-R2", "justification": "Supplier discontinued the product."},
        {"rejectedPO": "PO-R1", "justification": "Already resubmitted."}]})
    check("PO-R2 cancelled; PO-R1 (already resubmitted) isn't",
          can["cancelled"] == ["PO-R2"] and [n["rejectedPO"] for n in can["not_cancelled"]] == ["PO-R1"])
    state = q(bernard.aura, """MATCH (po:PurchaseOrder {PONumber:"PO-R2"})
                               OPTIONAL MATCH (:RejectedPoS)-[r]->(po)
                               OPTIONAL MATCH (:CancelledPoS)-[c:IS_CANCELLED_PO_STATE]->(po)
                               OPTIONAL MATCH (po)-[b:PO_CANCELLED_BY]->(e:Employee)
                               OPTIONAL MATCH (po)-[rej:HAS_L1_PO_REJECTION]->()
                               RETURN count(r) AS rejected, c.Comment AS reason, b.Source AS src, e.EmployeeID AS by,
                                      count(rej) AS rejectionKept""")[0]
    check("the cancelled PO moved from RejectedPoS to CancelledPoS, with reason and Source; the rejection stays as history",
          state == {"rejected": 0, "reason": "Supplier discontinued the product.", "src": "agent", "by": "17", "rejectionKept": 1})
    check("nothing is left to recommend for resubmission", bernard.tool("recommend_resubmissions", {})["rows"] == [])
    hist = q(bernard.aura, bernard.kb.template_by_title("Procurement Assistant decisions")["cypher"])
    check("the decisions history shows the resubmission and the cancellation with their justifications",
          sorted((h["Action"], h["Justification"]) for h in hist) == [
              ("cancelled", "Supplier discontinued the product."), ("resubmitted", "Lower quantity, as L1 asked.")])
    bernard.close()

    # 7. End to end through the agent loop
    seen = {}
    steps = [
        lambda r: ("recommend_restock", {}),
        lambda r: (seen.__setitem__("rec", r), ("text", "1. Exotic Liquids: Chai 55 (L1). 2. New Orleans Cajun Delights: Aniseed Syrup 45 (L1)."))[1],
        lambda r: ("create_purchase_orders", {"purchaseOrders": [
            {"supplierId": "2", "items": [{"productId": "3", "qty": 45}], "justification": "Open order 90001 is waiting."}]}),
        lambda r: (seen.__setitem__("made", r), ("text", "Created the PO; it goes to L1."))[1],
    ]
    s = session("16", steps=steps, answers=["y"])
    quiet(s.ask, "What needs restocking?")
    quiet(s.ask, "Accept number 2 only. Justification: open order 90001 is waiting.")
    check("end to end: recommend, then create only the accepted PO", len(seen["made"]["created"]) == 1
          and seen["made"]["created"][0]["supplierId"] == "2")
    used = s.kb._rows("""MATCH (i:Interaction {id:$i})-[:USED]->(q:QueryTemplate) RETURN q.title AS t""", {"i": s.interaction_id})
    check("the interaction records the governed template it used", any(u["t"].startswith("Create a Purchase Order") for u in used))
    s.close()

    # 8. The harness: --no-resubmit, contiguous bands and Source "simulation"
    import importlib.util
    spec = importlib.util.spec_from_file_location("harness_test", ROOT / "model" / "NorthwindPlus_Stress_Test.py")
    h = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = h
    spec.loader.exec_module(h)
    captured = {}
    h.iterate_weighted_actions = lambda d, st, db, actions, msg: captured.setdefault("names", [a.name for a in actions])
    h.NO_RESUBMIT = True
    h.iterate_po_vetting(None, None, None)
    check("harness --no-resubmit drops po_resubmit from the PO Vetting loop",
          "po_resubmit" not in captured["names"] and "l1_reject" in captured["names"])
    check("harness vetting uses contiguous bands (<= the limit)",
          all("POCost < ro.ApprovalLimit" not in a.execute_query for a in h.PO_VETTING_ACTIONS))
    store = TMP / "vet.rl"
    c = relate.connect(str(store)); c.execute(TOY_VETTING); c.close()
    import random
    whatif.replay(store, whatif.load_actions(), None, random.Random(3), 50)
    c = relate.connect(str(store), read_only=True)
    sources = {r["s"] for r in c.execute("MATCH (:PurchaseOrder)-[d:HAS_L1_PO_APPROVAL|HAS_L1_PO_REJECTION]->() RETURN d.Source AS s")}
    c.close()
    check("decisions written by the harness carry Source 'simulation'", sources == {"simulation"})

    # 9. The two run modes, and the guard against a loop still doing the job
    os.environ["SIMULATION_MODE"] = "full"
    full = session("16")
    check("SIMULATION_MODE=full: a Procurement Assistant gets no PO tools (the loops do that job)",
          not (procurement.NAMES & full.offered) and "SIMULATION_MODE is 'full'" in full.system[0]["text"])
    check("SIMULATION_MODE=full: a PO tool called anyway is refused", "refused" in full.tool("recommend_restock", {}))
    full.close()
    os.environ["SIMULATION_MODE"] = "agents"
    looped = session("16")
    q(looped.aura, """MATCH (s:Supplier {SupplierID:"1"}), (e:Employee {EmployeeID:"17"}), (rj:RejectedPoS)
                      CREATE (po:PurchaseOrder {PONumber:"PO-LOOP", PODate:datetime()})-[:PO_FOR_SUPPLIER]->(s),
                             (po)-[:PO_CREATED_BY {Date:datetime(), Source:"simulation"}]->(e)""")
    rec3 = looped.tool("recommend_restock", {})
    check("a PO created by the simulation in the last few minutes: recommendations come with a warning",
          "warning" in rec3 and "PO Creation loop" in rec3["warning"])
    blocked = looped.tool("create_purchase_orders", {"purchaseOrders": [
        {"supplierId": "2", "items": [{"productId": "3", "qty": 45}], "justification": "x"}]})
    check("...and creating POs is refused until the loop is stopped", "refused" in blocked and "still seems to be running" in blocked["refused"])
    q(looped.aura, "MATCH (:PurchaseOrder {PONumber:'PO-LOOP'})-[c:PO_CREATED_BY]->() SET c.Date = datetime() - duration({minutes: 10})")
    check("once the loop has been quiet for a few minutes, the warning goes away", "warning" not in looped.tool("recommend_restock", {}))
    looped.close()
    os.environ["SIMULATION_MODE"] = "bogus"
    try:
        session("16")
        bad_mode = False
    except SystemExit:
        bad_mode = True
    os.environ["SIMULATION_MODE"] = "agents"
    check("an unknown SIMULATION_MODE stops the session with a clear message", bad_mode)

    # 10. The web UI path: prepare/commit, Source "ui", no chat session, a read-only knowledge store
    class UISession:            # what the web API holds per signed-in person: no input(), no Interaction
        def __init__(self, employee_id, aura):
            self.aura, self.employee_id, self.mode = aura, employee_id, "agents"
            self.user = aura.whoami(employee_id)
            self.kb = ModelTemplates()             # straight from the model files: the API can't share the agent's store
    ui_aura = ProcurementAura()
    ui = procurement.Procurement(UISession("16", ui_aura), source="ui")
    try:
        procurement.Procurement(UISession("16", ui_aura), source="bogus")
        bad_source = False
    except ValueError:
        bad_source = True
    check("only 'agent' and 'ui' are accepted as a source", bad_source)
    ui.recommend_restock({})
    prep = ui.prepare_create({"purchaseOrders": [
        {"supplierId": "1", "items": [{"productId": "1", "qty": 50}], "justification": "Weekend demand (UI)."}]})
    check("prepare_create returns the review entries (cost, level, recommended vs ordered) and writes nothing",
          prep["entries"][0]["level"] == "L1" and prep["entries"][0]["lines"][0]["recommendedQt"] == 55
          and q(ui_aura, "MATCH (:NewPoS)-->(po) RETURN count(po) AS n")[0]["n"] == 0)
    made = ui.commit_create(prep["entries"])
    src = q(ui_aura, """MATCH (po:PurchaseOrder {PONumber:$n})-[c:PO_CREATED_BY]->(e:Employee) RETURN c.Source AS s, e.EmployeeID AS by""",
            {"n": made["created"][0]["PONumber"]})
    check("commit_create writes the PO with Source 'ui' and the signed-in assistant", src == [{"s": "ui", "by": "16"}])
    hist = q(ui_aura, ui.s.kb.template_by_title("Procurement Assistant decisions")["cypher"])
    check("the decisions history includes UI writes and says which front end", [(h["Action"], h["Source"]) for h in hist] == [("created", "ui")])
    bad = q(ui_aura, ui.t_create["cypher"].replace("CALL apoc.lock.nodes([p])", ""), {
        "requesterId": "16", "supplierId": "2", "items": [{"productId": "3", "qty": 45, "recommendedQt": 45}],
        "justification": "x", "source": "spreadsheet"})
    check("the governed Cypher itself writes nothing for an unknown source",
          bad == [] and q(ui_aura, "MATCH (:NewPoS)-->(po) RETURN count(po) AS n")[0]["n"] == 1)
    ui.recommend_restock({})
    prep2 = ui.prepare_create({"purchaseOrders": [
        {"supplierId": "2", "items": [{"productId": "3", "qty": 45}], "justification": "Open order waiting (UI)."}]})
    q(ui_aura, """MATCH (s:Supplier {SupplierID:"1"}), (e:Employee {EmployeeID:"17"})
                  CREATE (po:PurchaseOrder {PONumber:"PO-LOOP2", PODate:datetime()})-[:PO_FOR_SUPPLIER]->(s),
                         (po)-[:PO_CREATED_BY {Date:datetime(), Source:"simulation"}]->(e)""")
    late = ui.commit_create(prep2["entries"])
    check("commit re-checks the loop guard: a loop that started after the preview blocks the write",
          "refused" in late and q(ui_aura, "MATCH (:NewPoS)-->(po) RETURN count(po) AS n")[0]["n"] == 1)
    act = ui.audit(24)
    check("the activity-by-front-end summary separates the simulation's PO from the UI's",
          {(r["Source"], r["Action"]): r["POs"] for r in act["activity"]} == {("simulation", "created"): 1, ("ui", "created"): 1}
          and act["decisions"][0]["Source"] == "ui")
    dem = ui.demand([{"productId": "1", "qty": 55}], 7, 7)
    chai_d = dem["rows"][0]
    check("recent demand: Chai 900 units over 2 days = 450/day (the order 10 days ago is outside the window)",
          (chai_d["Orders"], chai_d["UnitsOrdered"], chai_d["UnitsPerDay"]) == (3, 900, 450.0))
    check("demand suggestion: the quantity that covers 7 days at that rate, from effective stock (the UI's Chai PO now counts as on order)",
          chai_d["DaysOfCoverAfterPO"] is not None and chai_d["SuggestedQt"] == int(-(-(450.0 * 7 - chai_d["EffectiveStock"]) // 1)))
    check("the suggestion says what it does to the PO: cost and the approval level it would need (L1 -> L3)",
          dem["po"]["approvalLevel"] == "L1" and dem["po"]["approvalLevelWithSuggestions"] == "L3" and dem["po"]["anySuggestion"])
    quiet_d = ui.demand([{"productId": "2", "qty": 5}], 7, 7)["rows"][0]
    check("no recent orders: no rate, no cover figure, no suggestion",
          (quiet_d["Orders"], quiet_d["UnitsPerDay"], quiet_d["DaysOfCoverAfterPO"], quiet_d["SuggestedQt"]) == (0, 0.0, None, None))
    ui_aura2 = ProcurementAura()
    ui2 = procurement.Procurement(UISession("17", ui_aura2), source="ui")
    ui2.recommend_resubmissions({})
    r_prep = ui2.prepare_resubmit({"resubmissions": [
        {"rejectedPO": "PO-R1", "items": [{"productId": "1", "qty": 25}], "justification": "As L1 asked (UI)."}]})
    ui2.commit_resubmit(r_prep["entries"])
    c_prep = ui2.prepare_cancel({"cancellations": [{"rejectedPO": "PO-R2", "justification": "Discontinued (UI)."}]})
    ui2.commit_cancel(c_prep["entries"])
    srcs = q(ui_aura2, """MATCH (po:PurchaseOrder)-[h:HAS_PREVIOUS_PO]->(:PurchaseOrder {PONumber:"PO-R1"}),
                                (:PurchaseOrder {PONumber:"PO-R2"})-[b:PO_CANCELLED_BY]->()
                          RETURN h.Source AS resub, b.Source AS cancel""")
    check("resubmit and cancel from the UI record Source 'ui'", srcs == [{"resub": "ui", "cancel": "ui"}])
    gl = procurement.Procurement(UISession("12", ProcurementAura()), source="ui")
    check("prepare and commit check the role themselves (an L1 approver is refused)",
          "refused" in gl.prepare_cancel({"cancellations": [{"rejectedPO": "PO-R1", "justification": "x"}]})
          and "refused" in gl.commit_cancel([{"p": {"rejectedPO": "PO-R1"}, "justification": "x"}]))
    kb = KnowledgeBase(STORE)
    same = all(ModelTemplates().template_by_title(t)["cypher"] == kb.template_by_title(t)["cypher"] for t in (
        procurement.RESTOCK_TITLE, procurement.RESUBMISSION_TITLE, procurement.CREATE_TITLE, procurement.RESUBMIT_TITLE,
        procurement.CANCEL_TITLE, "Procurement Assistant decisions"))
    kb.close()
    check("templates read from the model files are the same Cypher the knowledge store holds", same)

    # 11. The knowledge store is rebuilt when the model files change, even with the same model version
    from build_kb import needs_rebuild
    check("a freshly built store is current", needs_rebuild(STORE) is None)
    stale = TMP / "stale.rl"
    shutil.copy2(STORE, stale)
    c = relate.connect(str(stale)); c.execute("MATCH (k:KnowledgeBase) SET k.modelHash = 'built-from-older-files'"); c.close()
    check("a store built from older model files (same version) is flagged for a rebuild",
          (needs_rebuild(stale) or "").startswith("the model files changed"))
    check("a store with other embeddings is flagged for a rebuild", "embeddings" in (needs_rebuild(STORE, "voyage-4-nano") or ""))

    print(f"\n{sum(checks)}/{len(checks)} checks passed")
    return all(checks)


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
