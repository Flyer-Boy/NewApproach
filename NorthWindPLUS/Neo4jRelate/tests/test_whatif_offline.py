"""
Offline tests of the what-if sandbox: no Anthropic API, no Neo4j Aura.
  - Aura is replaced by relate holding a small PO-vetting queue (tests/toy_vetting.py).
  - The pull uses the fallback copier; if the relate CLI is installed (RELATE_BIN or on PATH), the real
    `relate pull` is tested too, against `relate serve --http` standing in for Aura's Query API.
  - The agent test reuses the scripted client from test_agent_offline.py.

  python tests/test_whatif_offline.py
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
for sub in ("agent", "kb", "tests", "sandbox"):
    sys.path.insert(0, str(ROOT / sub))

import relate  # noqa: E402
import pull as pull_mod  # noqa: E402
import whatif  # noqa: E402
from build_kb import build  # noqa: E402
from toy_vetting import TOY_VETTING  # noqa: E402
import test_agent_offline as base  # noqa: E402

TMP = Path(tempfile.mkdtemp(prefix="whatif-test-"))
PROPOSED = {"l1": 8000.0, "l2": 20000.0, "l3": 500000.0}


class VettingAura(base.RelateAura):
    """The agent's Aura logic against relate holding the toy vetting queue."""
    def __init__(self):
        self.database = "toy"
        self.conn = relate.connect(":memory:")
        self.conn.execute(TOY_VETTING)


def shape(store: Path) -> tuple:
    c = relate.connect(str(store), read_only=True)
    labels = sorted((tuple(r["l"]), r["c"]) for r in c.execute("MATCH (n) RETURN labels(n) AS l, count(*) AS c"))
    types = sorted((r["t"], r["c"]) for r in c.execute("MATCH ()-[r]->() RETURN type(r) AS t, count(*) AS c"))
    c.close()
    return labels, types


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main():
    checks = []

    def check(name, cond):
        checks.append(bool(cond))
        print(f"{'PASS' if cond else 'FAIL'}  {name}")

    # 1. Fallback copier: the vetting subgraph, nothing else, types kept
    aura = VettingAura()
    pulled = TMP / "pulled.rl"
    info = pull_mod.pull(pulled, aura=aura, method="driver")
    labels, types = shape(pulled)
    names = {l[0] for l, _ in labels}
    check("copier pulls POs, products, approver roles, employees and state nodes",
          names == {"PurchaseOrder", "Product", "RolE", "Employee", "NewPoS", "ApprovedPoS", "RejectedPoS"})
    check("copier leaves out unrelated nodes (Buyer, suppliers, orders, the policy admin)",
          dict(labels).get(("RolE",)) == 3 and dict(labels).get(("Employee",)) == 3)
    check("copier keeps relationship types", dict(types) == {"IS_NEW_PO_STATE": 5, "HAS_PO_ITEM": 5, "IS_ACTIVE_ROLE": 3})
    c = relate.connect(str(pulled), read_only=True)
    d = c.execute("MATCH (p:PurchaseOrder) RETURN p.PODate AS d LIMIT 1").single()["d"]
    leftovers = c.execute("MATCH (n:_Pulled) RETURN count(n) AS n").single()["n"]
    c.close()
    check("copier keeps DATETIME values as datetimes", hasattr(d, "year"))
    check("copier removes its temporary label", leftovers == 0)
    check("copier reports its method", info["method"].startswith("driver") and info["nodes"] == 15)

    # 2. The rehearsal: current vs proposed
    r = whatif.what_if(PROPOSED["l1"], PROPOSED["l2"], PROPOSED["l3"], runs=3, pulled_store=pulled, seed=7)
    cur, prop = r["scenarios"]["current"], r["scenarios"]["proposed"]
    check("queue at pull: 5 POs worth 30,900", r["queue_at_pull"] == {"pos": 5, "value": 30900.0})
    check("current limits read from the copy", cur["limits"] == {"l1Limit": 5000.0, "l2Limit": 12500.0, "l3Limit": 500000.0})
    import random
    actions, ok = whatif.load_actions(), True
    for limits in (None, {"l1Limit": 8000.0, "l2Limit": 20000.0, "l3Limit": 500000.0}):
        for i in range(4):
            run_copy = TMP / f"run-{i}.rl"
            shutil.copy2(pulled, run_copy)
            one = whatif.replay(run_copy, actions, limits, random.Random(i), 50)
            ok &= one["approved_L1"] + one["approved_L2"] + one["approved_L3"] + one["rejected"] == 5 and not one["stuck"]
    check("in every run, every PO ends approved or rejected, none stuck",
          ok and cur["stuck_in_runs"] == 0 and prop["stuck_in_runs"] == 0)
    check("proposed limits: nothing needs L3 (PO-4 at 14,000 is in the L2 band)", prop["approved_L3"]["max"] == 0)
    check("current limits: PO-4 can only be approved at L3", cur["approved_L2"]["max"] <= 1 and cur["passed_on_L2"]["max"] <= 1)
    check("proposed limits: at most one PO passed up from L1, none from L2",
          prop["passed_on_L1"]["max"] <= 1 and prop["passed_on_L2"]["max"] == 0)
    check("never more cycles than hand-offs allow (5 POs, 8 at most today, 6 proposed)",
          cur["cycles"]["max"] <= 8 and prop["cycles"]["max"] <= 6)
    check("contiguous bands: PO-5 (exactly 5,000) has a path, nothing flagged",
          r["boundary_pos"]["current"] == [] and r["boundary_pos"]["proposed"] == [])
    check("scratch stores are deleted afterwards", not (whatif.SCRATCH / r["whatIfId"]).exists())
    check("refuses limits Aura would refuse", "refused" in whatif.what_if(9000, 8000, 500000, pulled_store=pulled))

    # 3. Boundaries that remain: above the L3 limit, and a cost of 0
    edge = whatif.boundary_pos({"PO-X": 600000.0, "PO-Y": 0.0, "PO-Z": 500000.0},
                               {"l1Limit": 5000.0, "l2Limit": 12500.0, "l3Limit": 500000.0})
    check("above L3 and zero cost flagged; exactly the L3 limit is fine", sorted(b["po"] for b in edge) == ["PO-X", "PO-Y"])

    # 4. Through the agent: what-if, then the governed change citing it
    store = TMP / "kb.rl"
    build(store)
    real_find_cli, pull_mod.find_cli = pull_mod.find_cli, lambda: None   # the stand-in Aura has no Query API
    seen = {}
    s = base.make_session("25", [
        lambda r: ("what_if_approval_bands", {"l1Limit": 8000, "l2Limit": 20000, "l3Limit": 500000}),
        lambda r: (seen.__setitem__("wi", r), ("text", "Rehearsed: the proposed limits clear the queue faster."))[1],
    ], store=store)
    s.aura = VettingAura()
    s.user = s.aura.whoami("25")
    s.ask("What would happen if we raised L1 to 8000 and L2 to 20000?")
    wid = seen["wi"].get("whatIfId")
    check("agent runs the what-if (fallback copier, no CLI needed)", wid and seen["wi"]["source"]["method"] != "")
    rows = s.kb._rows("MATCH (i:Interaction)-[:RAN]->(w:WhatIf {id:$w}) RETURN w.proposedLimits AS pl, w.queuePOs AS n",
                      {"w": wid})
    check("what-if recorded in relate, linked to the question", rows and rows[0]["pl"] == [8000.0, 20000.0, 500000.0])
    s.steps = None
    s.client = base.ScriptedClient([
        lambda r: ("change_approval_bands", {"l1Limit": 8000, "l2Limit": 20000, "l3Limit": 500000,
                                             "justification": "Speed up vetting"}),
        lambda r: (seen.__setitem__("pc", r), ("text", "Done."))[1],
    ])
    replies = iter(["y"])
    s.confirm = lambda prompt: next(replies) == "y"
    s.ask("Apply it.")
    pc = s.aura.read("MATCH (pc:PolicyChange) RETURN pc.PolicyChangeID AS id, pc.Justification AS j")["rows"]
    check("the PolicyChange justification cites the what-if", pc and wid in pc[0]["j"])
    applied = s.kb._rows("MATCH (w:WhatIf {id:$w}) RETURN w.appliedAs AS a", {"w": wid})
    check("the what-if records which PolicyChange applied it", applied and applied[0]["a"] == pc[0]["id"])
    s.close()
    stats = build(store)
    check("a rebuild keeps the what-if and its link", stats.get("whatifs") == 1)

    # 5. The real `relate pull`, if the CLI is installed: relate serve --http stands in for Aura's Query API
    pull_mod.find_cli = real_find_cli
    cli = pull_mod.find_cli()
    if not cli:
        print("SKIP  relate pull via the CLI (no relate binary; set RELATE_BIN to test it)")
    else:
        src = TMP / "aura-standin.rl"
        c = relate.connect(str(src)); c.execute(TOY_VETTING); c.close()
        port = free_port()
        server = subprocess.Popen([cli, "serve", "--database", str(src), "--http", str(port), "--read-only",
                                   "--auth", "neo4j:test-password"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            for _ in range(50):
                try:
                    socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
                    break
                except OSError:
                    time.sleep(0.2)
            env = {**os.environ, "NEO4J_URI": f"http://127.0.0.1:{port}", "NEO4J_USERNAME": "neo4j",
                   "NEO4J_PASSWORD": "test-password", "NEO4J_DATABASE": "neo4j"}
            via_cli = TMP / "pulled-cli.rl"
            try:
                info = pull_mod.pull(via_cli, method="cli", env=env)
                check("relate pull: the same subgraph as the fallback copier", shape(via_cli) == shape(pulled))
                check("relate pull: summary parsed", info["method"] == "relate pull" and info["nodes"] == 15)
                r2 = whatif.what_if(8000, 20000, 500000, runs=2, pulled_store=via_cli)
                check("relate pull: the rehearsal runs on the pulled store",
                      r2["queue_at_pull"]["pos"] == 5 and r2["scenarios"]["proposed"]["stuck_in_runs"] == 0)
            except Exception as exc:
                check(f"relate pull runs ({exc})", False)
        finally:
            server.terminate()
            server.wait(timeout=10)

    shutil.rmtree(TMP, ignore_errors=True)
    print(f"\n{sum(checks)}/{len(checks)} checks passed")
    return all(checks)


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
