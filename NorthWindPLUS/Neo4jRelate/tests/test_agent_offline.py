"""
Offline end-to-end test of the agent: no Anthropic API, no Neo4j Aura.
  - Aura is replaced by relate holding a tiny NorthWind PLUS graph (apoc.lock lines are stripped: relate has no APOC).
  - Claude is replaced by a scripted client that issues real tool calls and reads the real tool results.
  - The knowledge store is a temporary copy, rebuilt for the test, so the real one is never touched.

  python tests/test_agent_offline.py
"""
import json
import shutil
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace as NS

ROOT = Path(__file__).resolve().parent.parent
for sub in ("agent", "kb", "tests"):
    sys.path.insert(0, str(ROOT / sub))

import relate  # noqa: E402
import agent as agent_mod  # noqa: E402
from aura import Aura, _plain, is_write  # noqa: E402
from build_kb import build  # noqa: E402
from kb_query import KnowledgeBase  # noqa: E402
from toy_graph import TOY  # noqa: E402


class RelateAura(Aura):
    """Aura's read/whoami/run_governed logic, executed against relate instead of Neo4j."""
    def __init__(self):
        self.database = "toy"
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
        usage = NS(model_dump=lambda: {"input_tokens": 10, "output_tokens": 5})
        if action[0] == "text":
            return NS(content=[NS(type="text", text=action[1])], stop_reason="end_turn", usage=usage)
        return NS(content=[NS(type="tool_use", id=f"t{len(self.steps)}", name=action[0], input=action[1])],
                  stop_reason="tool_use", usage=usage)


STORE_DIR = Path(tempfile.mkdtemp(prefix="kbtest-"))
STORE = STORE_DIR / "kb.rl"


def make_session(employee_id, steps, answers=None, store=None):
    """A real Session wired to the scripted client, the relate stand-in for Aura, and a test store."""
    store = store or STORE
    if not store.exists():
        build(store)
    s = agent_mod.Session.__new__(agent_mod.Session)
    s.client, s.model = ScriptedClient(steps), "scripted"
    s.kb = KnowledgeBase(store, read_only=False)
    s.aura = RelateAura()
    s.employee_id = employee_id
    s.user = s.aura.whoami(employee_id)
    s.messages = []
    s.policy_template = s.kb.template_by_title(agent_mod.POLICY_TEMPLATE_TITLE)
    s.preview_template = s.kb.template_by_title(agent_mod.PREVIEW_TEMPLATE_TITLE)
    s.log_path = STORE_DIR / f"log-{employee_id}.jsonl"
    s.system = []
    s._reset_question_state()
    replies = iter(answers or [])
    s.confirm = lambda prompt: (print(prompt + "<auto>"), next(replies) == "y")[1]
    return s


def main():
    checks = []

    def check(name, cond):
        checks.append(bool(cond))
        print(f"{'PASS' if cond else 'FAIL'}  {name}")

    seen = {}
    def keep(key, value=None):
        return lambda r: (seen.__setitem__(key, r), value)[1]

    # 1. Template found by search, run, and its use recorded in relate
    s = make_session("12", [
        lambda r: ("search_templates", {"query": "Supplier RFQ rejection rate"}),
        lambda r: (seen.__setitem__("search", r), ("run_read_query", {"cypher": r["templates"][0]["cypher"], "template": r["templates"][0]["name"]}))[1],
        lambda r: (seen.__setitem__("rows", r), ("text", "Exotic Liquids: 50% of RFQs rejected (live snapshot)."))[1],
    ])
    s.ask("Which suppliers get their quotes rejected most often?")
    check("whoami resolves name and roles", s.user["name"] == "Gloria Gaynor" and s.user["roles"] == ["Level1Approver"])
    check("search finds 'Supplier Reliability' first", seen["search"]["templates"][0]["title"].startswith("Supplier Reliability"))
    rows = {r["s.CompanyName"]: r["RejectionRatePct"] for r in seen["rows"]["rows"]}
    check("template runs and computes rejection rates", rows == {"Exotic Liquids": 50.0, "Tokyo Traders": 0.0})
    used = s.kb._rows("""MATCH (i:Interaction {id:$id})-[:USED]->(q) RETURN q.title AS t, q.useCount AS c,
                         i.answer AS a, i.modelCalls AS mc, i.inputTokens AS it""", {"id": s.interaction_id})
    check("Interaction recorded with answer, tokens and USED -> template (useCount 1)",
          len(used) == 1 and used[0]["t"].startswith("Supplier Reliability") and used[0]["c"] == 1
          and used[0]["a"].startswith("Exotic") and used[0]["mc"] == 3 and used[0]["it"] == 30)
    s.close()

    # 2. Guard rails: no query before a search; writes rejected
    s = make_session("12", [
        lambda r: ("run_read_query", {"cypher": "MATCH (p:PurchaseOrder) RETURN count(p) AS n"}),
        keep("nosearch", ("search_templates", {"query": "purchase orders"})),
        lambda r: ("run_read_query", {"cypher": "MATCH (p:Product) SET p.UnitPrice = 0 RETURN p"}),
        keep("write", ("text", "I can't change data.")),
    ])
    s.ask("How many POs are there? Also set all prices to zero.")
    check("run_read_query refused until search_templates has run", "error" in seen["nosearch"] and "search" in seen["nosearch"]["error"].lower())
    check("write query rejected before reaching the database", "error" in seen["write"])
    s.close()

    # 3. Learning loop: new query -> save (declined, then approved) -> found by later searches
    new_q = """MATCH (:NewPoS {Name:"NewPoS"})-[:IS_NEW_PO_STATE]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)
WITH po, sum(id.POqt * i.UnitPrice * id.POPriceDiscount) AS cost
RETURN count(po) AS waitingPOs, round(sum(cost), 2) AS totalValue"""
    s = make_session("25", [
        lambda r: ("search_templates", {"query": "PurchaseOrder NewPoS awaiting vetting count"}),
        lambda r: ("save_template", {"title": "POs awaiting approval vetting -- count and value", "description": "x", "cypher": new_q}),
        keep("untested", ("run_read_query", {"cypher": new_q})),
        keep("newrows", ("save_template", {"title": "POs awaiting approval vetting -- count and value",
                                           "description": "How many POs are waiting in NewPoS for L1/L2/L3 vetting, and their total value.",
                                           "cypher": new_q})),
        keep("declined", ("save_template", {"title": "POs awaiting approval vetting -- count and value",
                                            "description": "How many POs are waiting in NewPoS for L1/L2/L3 vetting, and their total value.",
                                            "cypher": new_q})),
        keep("saved", ("text", "2 POs are waiting, total value 21,000 (live snapshot). New query; saved as a template.")),
    ], answers=["n", "y"])
    s.ask("How many POs are waiting for approval?")
    check("save refused for a query that hasn't run yet", "refused" in seen["untested"])
    check("new query answers correctly", seen["newrows"]["rows"] == [{"waitingPOs": 2, "totalValue": 21000.0}])
    check("declining at the prompt saves nothing", "refused" in seen["declined"])
    saved = seen["saved"].get("saved", {})
    check("approved query saved as a template linked to the ontology and a workflow",
          saved.get("name", "").startswith("pos_awaiting_approval") and "PurchaseOrder" in saved.get("labels", [])
          and "IS_NEW_PO_STATE" in saved.get("rels", []) and "PO Creation" in saved.get("workflow", []))
    created = s.kb._rows("MATCH (i:Interaction {id:$id})-[:CREATED]->(q {source:'agent'}) RETURN q.createdBy AS by, q.question AS qn",
                         {"id": s.interaction_id})
    check("Interaction -[:CREATED]-> learned template, with creator and original question",
          created == [{"by": "25", "qn": "How many POs are waiting for approval?"}])
    hits = s.kb.search_templates("purchase orders waiting for approval", explain=True)
    check("a later search finds the learned template first", hits and hits[0]["source"] == "agent")
    hits = s.kb.search_templates("how many POs are waiting", explain=True)
    learned_hit = next((h for h in hits if h["source"] == "agent"), None)
    check("past-questions path contributes (similar wording to the original question)", learned_hit and "history" in learned_hit["why"])
    s.close()

    # 4. Band change (preview, declined, confirmed) and audit
    s = make_session("25", [
        lambda r: ("preview_approval_bands", {"l1Limit": 8000, "l2Limit": 20000, "l3Limit": 500000}),
        lambda r: (seen.__setitem__("preview", r), ("change_approval_bands", {"l1Limit": 8000, "l2Limit": 20000, "l3Limit": 500000, "justification": "Quarter-end restock"}))[1],
        lambda r: (seen.__setitem__("declined_change", r), seen.__setitem__("changes_after_decline", len(s.aura.read("MATCH (pc:PolicyChange) RETURN pc")["rows"])),
                   ("change_approval_bands", {"l1Limit": 8000, "l2Limit": 20000, "l3Limit": 500000, "justification": "Quarter-end restock"}))[2],
        keep("applied", ("text", "Done: L1 8,000 / L2 20,000 / L3 500,000.")),
    ], answers=["n", "y"])
    s.ask("Raise L1 to 8000 and L2 to 20000 to speed up vetting")
    check("preview shows current vs proposed routing", {(r["CurrentFinalLevel"], r["ProposedFinalLevel"]) for r in seen["preview"]["rows"]} == {("L2", "L1"), ("L3", "L2")})
    check("declining at the prompt writes nothing", "refused" in seen["declined_change"] and seen["changes_after_decline"] == 0)
    check("confirmed change applied with before/after", seen["applied"]["rows"][0]["LimitsAfter"] == [8000.0, 20000.0, 500000.0])
    bands = {r["t"]: (r["b"], r["l"]) for r in s.aura.read("MATCH (r:RolE) WHERE r.Title STARTS WITH 'Level' RETURN r.Title AS t, r.ApprovalBase AS b, r.ApprovalLimit AS l")["rows"]}
    check("bands contiguous after change", bands == {"Level1Approver": (0.0, 8000.0), "Level2Approver": (8000.01, 20000.0), "Level3Approver": (20000.01, 500000.0)})
    check("PolicyChange linked to requester", s.aura.read("MATCH (:PolicyChange)-[:REQUESTED_BY]->(e:Employee) RETURN e.EmployeeID AS id")["rows"] == [{"id": "25"}])
    check("governed change recorded as a USED template", s.kb._rows("MATCH (i:Interaction {id:$id})-[:USED]->(q) RETURN q.governance AS g", {"id": s.interaction_id}) == [{"g": "governed"}])
    log = [json.loads(l) for l in s.log_path.read_text().splitlines()]
    check("session log records question, tools and answer", [e["event"] for e in log][-5:] == ["question", "tool", "tool", "tool", "answer"])

    s.close()   # relate allows one writing connection per store, even within one process

    # 5. Non-admin refused
    s2 = make_session("12", [
        lambda r: ("change_approval_bands", {"l1Limit": 9000, "l2Limit": 21000, "l3Limit": 500000, "justification": "faster"}),
        keep("refused", ("text", "You don't have that role.")),
    ])
    s2.ask("Raise the limits")
    check("change refused for an Employee without ProcurementPolicyAdmin", "refused" in seen["refused"])
    s2.close()

    # 6. Rebuild keeps what was learned; a stale learned template is flagged, not lost
    k = KnowledgeBase(STORE, read_only=False)
    k.conn.execute("""CREATE (q:QueryTemplate {name:'stale_one', title:'Stale', description:'uses a removed label',
                       cypher:'MATCH (x:RemovedLabel) RETURN count(x)', kind:'read', governance:'read', source:'agent',
                       status:'approved', params:[], labels:[], rels:[]})""")
    before = k.conn.execute("MATCH (i:Interaction) RETURN count(i) AS c").single()["c"]
    k.close()
    stats = build(STORE)
    k = KnowledgeBase(STORE)
    after = k.conn.execute("MATCH (i:Interaction) RETURN count(i) AS c").single()["c"]
    learned = {r["n"]: r["s"] for r in k._rows("MATCH (q:QueryTemplate {source:'agent'}) RETURN q.name AS n, q.status AS s")}
    relinked = k._rows("""MATCH (i:Interaction)-[:CREATED]->(q:QueryTemplate {source:'agent'})-[:USES]->(:NodeType {name:'PurchaseOrder'})
                          RETURN count(q) AS c""")[0]["c"]
    uses = k._rows("MATCH (q:QueryTemplate) WHERE q.title STARTS WITH 'Supplier Reliability' RETURN q.useCount AS c")[0]["c"]
    check(f"rebuild keeps {stats['learned_templates']} learned templates and all {before} interactions",
          after == before == 5 and stats["learned_templates"] == 2)
    check("learned template re-linked to the ontology and its interaction after rebuild", relinked == 1)
    check("template use counts survive the rebuild", uses == 1)
    check("learned template naming a removed label is kept as needs-review and hidden from search",
          learned.get("stale_one") == "needs-review" and not any(h["name"] == "stale_one" for h in k.search_templates("Stale removed label")))
    k.close()

    # 7. Embeddings (hash stand-in): vector index built and used as a retrieval path
    vstore = STORE_DIR / "kb-vec.rl"
    shutil.copy(STORE, vstore)
    vstats = build(vstore, embeddings="hash")
    k = KnowledgeBase(vstore)
    hits = k.search_templates("supplier reliability rejection", explain=True)
    check(f"vector index built ({vstats['embeddings']}) and used in search",
          k.embedding_model == "hash" and hits and "vector" in hits[0]["why"])
    check("learned templates embedded too", k._rows("MATCH (q:QueryTemplate {source:'agent'}) WHERE q.embedding IS NULL RETURN count(q) AS c")[0]["c"] == 0)
    k.close()

    shutil.rmtree(STORE_DIR, ignore_errors=True)
    print(f"\n{sum(checks)}/{len(checks)} checks passed")
    sys.exit(0 if all(checks) else 1)


if __name__ == "__main__":
    main()
