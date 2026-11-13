"""
Offline end-to-end test of the agent loop: no Anthropic API, no Neo4j Aura.
  - Aura is replaced by relate holding a tiny NorthWind PLUS graph (apoc.lock lines are stripped: relate has no APOC).
  - Claude is replaced by a scripted client that issues real tool calls and reads the real tool results.
Checks the plumbing: template search, read queries, write rejection, preview, role check, confirmation, governed change.

  python tests/test_agent_offline.py
"""
import builtins
import json
import sys
from pathlib import Path
from types import SimpleNamespace as NS

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "agent"))
sys.path.insert(0, str(ROOT / "kb"))

import relate  # noqa: E402
import agent as agent_mod  # noqa: E402
from aura import Aura, _plain, is_write  # noqa: E402

TOY = """
CREATE (rs:RoleS {Name:"RoleS"}), (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}),
  (l1:RolE {Title:"Level1Approver", ApprovalBase:0.00, ApprovalLimit:5000.00, Rules:"old"}),
  (l2:RolE {Title:"Level2Approver", ApprovalBase:5000.01, ApprovalLimit:12500.00, Rules:"old"}),
  (l3:RolE {Title:"Level3Approver", ApprovalBase:12500.01, ApprovalLimit:500000.00, Rules:"old"}),
  (pp:RolE {Title:"ProcurementPolicyAdmin"}),
  (pp)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(olivia:Employee {EmployeeID:"25", Email:"Olivia.Bennett@northwind.com"})-[:HAS_PERSON]->(:Person {FirstName:"Olivia", LastName:"Bennett"}),
  (l1)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(gloria:Employee {EmployeeID:"12", Email:"Gloria.Gaynor@northwind.com"})-[:HAS_PERSON]->(:Person {FirstName:"Gloria", LastName:"Gaynor"}),
  (n:NewPoS {Name:"NewPoS"}), (p:Product {ProductID:"1", ProductName:"Chai", UnitPrice:10.0}),
  (n)-[:IS_NEW_PO_STATE]->(:PurchaseOrder {PONumber:"PO-A"})-[:HAS_PO_ITEM {POqt:1000, POPriceDiscount:0.7}]->(p),
  (n)-[:IS_NEW_PO_STATE]->(:PurchaseOrder {PONumber:"PO-B"})-[:HAS_PO_ITEM {POqt:2000, POPriceDiscount:0.7}]->(p),
  (s1:Supplier {SupplierID:"1", CompanyName:"Exotic Liquids"}), (s2:Supplier {SupplierID:"2", CompanyName:"Tokyo Traders"}),
  (rej:PoRejectedRFQ {Name:"PoRejectedRFQ"}),
  (:RFQ {RFQNumber:"R1"})-[:RFQ_FROM_SUPPLIER]->(s1), (r2:RFQ {RFQNumber:"R2"})-[:RFQ_FROM_SUPPLIER]->(s1),
  (:RFQ {RFQNumber:"R3"})-[:RFQ_FROM_SUPPLIER]->(s2), (rej)-[:IS_SUPPLIER_REJECTED_RFQ_STATE {Date:datetime()}]->(r2)
"""


class RelateAura(Aura):
    """Aura's read/whoami/run_governed logic, executed against relate instead of Neo4j."""
    def __init__(self):
        self.conn = relate.connect(":memory:")
        self.conn.execute(TOY)

    def close(self):
        self.conn.close()

    def read(self, cypher, params=None):
        if is_write(cypher):
            return {"error": "Rejected: this query contains a write clause. Only read queries can be run with this tool."}
        try:
            rows = [_plain(dict(r)) for r in self.conn.execute(cypher, params or {})]
            return {"rows": rows, "row_count": len(rows), "capped": False}
        except Exception as exc:
            return {"error": f"{type(exc).__name__}: {exc}"}

    def run_governed(self, cypher, params):
        cypher = "\n".join(l for l in cypher.split("\n") if "apoc.lock" not in l)
        try:
            return {"rows": [_plain(dict(r)) for r in self.conn.execute(cypher, params)]}
        except Exception as exc:
            return {"error": f"{type(exc).__name__}: {exc}"}


class ScriptedClient:
    """Stands in for anthropic.Anthropic(): each step looks at the last tool result and decides the next call."""
    def __init__(self, steps):
        self.steps = steps
        self.messages = self

    def create(self, **kw):
        last = kw["messages"][-1]["content"]
        last_result = json.loads(last[0]["content"]) if isinstance(last, list) else None
        action = self.steps.pop(0)(last_result)
        usage = NS(model_dump=lambda: {"input_tokens": 0, "output_tokens": 0})
        if action[0] == "text":
            return NS(content=[NS(type="text", text=action[1])], stop_reason="end_turn", usage=usage)
        return NS(content=[NS(type="tool_use", id=f"t{len(self.steps)}", name=action[0], input=action[1])],
                  stop_reason="tool_use", usage=usage)


def make_session(employee_id, steps):
    s = agent_mod.Session.__new__(agent_mod.Session)
    s.client, s.model = ScriptedClient(steps), "scripted"
    s.kb = agent_mod.KnowledgeBase()
    s.aura = RelateAura()
    s.employee_id = employee_id
    s.user = s.aura.whoami(employee_id)
    s.messages = []
    s.policy_template = s.kb.template_by_title(agent_mod.POLICY_TEMPLATE_TITLE)
    s.preview_template = s.kb.template_by_title(agent_mod.PREVIEW_TEMPLATE_TITLE)
    s.log_path = ROOT / "tests" / "offline-test.jsonl"
    s.log_path.unlink(missing_ok=True)
    s.system = []
    return s


checks = []
def check(name, cond):
    checks.append(cond)
    print(f"{'PASS' if cond else 'FAIL'}  {name}")


# 1. Question answered from a template found by search
seen = {}
s = make_session("12", [
    lambda r: ("search_templates", {"query": "Supplier RFQ rejection rate"}),
    lambda r: (seen.setdefault("search", r), ("run_read_query", {"cypher": r["templates"][0]["cypher"], "template": r["templates"][0]["name"]}))[1],
    lambda r: (seen.setdefault("rows", r), ("text", "Exotic Liquids: 50% of RFQs rejected (live snapshot)."))[1],
])
print("signed in:", s.user)
s.ask("Which suppliers get their quotes rejected most often?")
check("whoami resolves name and roles", s.user["name"] == "Gloria Gaynor" and s.user["roles"] == ["Level1Approver"])
check("search finds 'Supplier Reliability' first", seen["search"]["templates"][0]["title"].startswith("Supplier Reliability"))
rows = {r["s.CompanyName"]: r["RejectionRatePct"] for r in seen["rows"]["rows"]}
check("template runs and computes rejection rates", rows == {"Exotic Liquids": 50.0, "Tokyo Traders": 0.0})

# 2. Writes are rejected by run_read_query
s = make_session("12", [
    lambda r: ("run_read_query", {"cypher": "MATCH (p:Product) SET p.UnitPrice = 0 RETURN p"}),
    lambda r: (seen.__setitem__("write", r), ("text", "I can't change data."))[1],
])
s.ask("Set all prices to zero")
check("write query rejected before reaching the database", "error" in seen["write"])

# 3. Non-admin cannot change the bands
s = make_session("12", [
    lambda r: ("change_approval_bands", {"l1Limit": 8000, "l2Limit": 20000, "l3Limit": 500000, "justification": "faster"}),
    lambda r: (seen.__setitem__("refused", r), ("text", "You don't have that role."))[1],
])
s.ask("Raise the limits")
check("change refused for an Employee without ProcurementPolicyAdmin", "refused" in seen["refused"])

# 4. Admin: preview, then change -- first declined at the prompt, then confirmed
answers = iter(["n", "y"])
builtins.input = lambda prompt="": (print(prompt + "<auto>"), next(answers))[1]
s = make_session("25", [
    lambda r: ("preview_approval_bands", {"l1Limit": 8000, "l2Limit": 20000, "l3Limit": 500000}),
    lambda r: (seen.__setitem__("preview", r), ("change_approval_bands", {"l1Limit": 8000, "l2Limit": 20000, "l3Limit": 500000, "justification": "Quarter-end restock"}))[1],
    lambda r: (seen.__setitem__("declined", r), seen.__setitem__("changes_after_decline", len(s.aura.read("MATCH (pc:PolicyChange) RETURN pc")["rows"])), ("change_approval_bands", {"l1Limit": 8000, "l2Limit": 20000, "l3Limit": 500000, "justification": "Quarter-end restock"}))[2],
    lambda r: (seen.__setitem__("applied", r), ("text", "Done: L1 8,000 / L2 20,000 / L3 500,000."))[1],
])
s.ask("Raise L1 to 8000 and L2 to 20000 to speed up vetting")
check("preview shows current vs proposed routing", {(r["CurrentFinalLevel"], r["ProposedFinalLevel"]) for r in seen["preview"]["rows"]} == {("L2", "L1"), ("L3", "L2")})
check("declining at the prompt writes nothing", "refused" in seen["declined"] and seen["changes_after_decline"] == 0)
check("confirmed change applied with before/after", seen["applied"]["rows"][0]["LimitsAfter"] == [8000.0, 20000.0, 500000.0])
bands = {r["t"]: (r["b"], r["l"]) for r in s.aura.read("MATCH (r:RolE) WHERE r.Title STARTS WITH 'Level' RETURN r.Title AS t, r.ApprovalBase AS b, r.ApprovalLimit AS l")["rows"]}
check("bands contiguous after change", bands == {"Level1Approver": (0.0, 8000.0), "Level2Approver": (8000.01, 20000.0), "Level3Approver": (20000.01, 500000.0)})
check("PolicyChange linked to requester", s.aura.read("MATCH (:PolicyChange)-[:REQUESTED_BY]->(e:Employee) RETURN e.EmployeeID AS id")["rows"] == [{"id": "25"}])
log = [json.loads(l) for l in s.log_path.read_text().splitlines()]
check("session log records question, tools and answer", [e["event"] for e in log] == ["question", "tool", "tool", "tool", "answer"])

print(f"\n{sum(checks)}/{len(checks)} checks passed")
sys.exit(0 if all(checks) else 1)
