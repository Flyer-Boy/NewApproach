"""
Exercises the real Aura.read / whoami / run_governed code (not a replacement class) against a stand-in session
that enforces the Neo4j driver's rules for managed transactions:
  - tx.run() rejects neo4j.Query objects (they're only allowed in session.run)
  - the timeout must come from the transaction function's @unit_of_work attribute
Rows come from relate, so the Cypher really runs.

  python tests/test_aura_driver_path.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "agent"))
sys.path.insert(0, str(ROOT / "tests"))

import relate  # noqa: E402
from neo4j import Query  # noqa: E402
from aura import Aura, QUERY_TIMEOUT_S  # noqa: E402
from toy_graph import TOY  # noqa: E402

seen_timeouts = []


class Record(dict):
    def data(self):
        return dict(self)


class Status:
    def __init__(self, code, desc, notification):
        self.gql_status, self.status_description, self.is_notification = code, desc, notification


class Result(list):
    """Iterable records + consume(), like neo4j.Result. Queries mentioning NoSuchProp get a 01N52 warning."""
    def __init__(self, rows, query):
        super().__init__(rows)
        self.query = query

    def consume(self):
        statuses = [Status("00000", "note: successful completion", False)]
        if "NoSuchProp" in self.query:
            statuses.insert(0, Status("01N52", "warn: property key does not exist. The property `NoSuchProp` does not exist.", True))
        return type("Summary", (), {"gql_status_objects": statuses})()


class StrictTx:
    def __init__(self, conn):
        self.conn = conn

    def run(self, query, parameters=None, **kw):
        if isinstance(query, Query):
            raise TypeError("Query object is only supported for session.run")   # the driver's own message
        query = "\n".join(l for l in query.split("\n") if "apoc.lock" not in l)  # relate has no APOC
        return Result([Record(r) for r in self.conn.execute(query, parameters or {})], query)


class StrictSession:
    def __init__(self, conn):
        self.conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def _managed(self, fn):
        seen_timeouts.append(getattr(fn, "timeout", None))   # what the real driver reads
        return fn(StrictTx(self.conn))

    execute_read = execute_write = _managed


class StrictDriver:
    def __init__(self, conn):
        self.conn = conn

    def session(self, database=None):
        return StrictSession(self.conn)

    def close(self):
        pass


aura = Aura.__new__(Aura)
aura.database = "test"
conn = relate.connect(":memory:")
conn.execute(TOY)
aura.driver = StrictDriver(conn)

checks = []
def check(name, cond):
    checks.append(cond)
    print(f"{'PASS' if cond else 'FAIL'}  {name}")

who = aura.whoami("25")
check("whoami works through a managed read transaction", who == {"employeeId": "25", "name": "Olivia Bennett", "roles": ["ProcurementPolicyAdmin"]})
r = aura.read("MATCH (p:PurchaseOrder) RETURN p.PONumber AS po ORDER BY po")
check("read returns rows", r.get("rows") == [{"po": "PO-A"}, {"po": "PO-B"}])
check("read rejects writes before the database", "error" in aura.read("MATCH (p:Product) SET p.UnitPrice = 0"))
w = aura.read("MATCH (p:PurchaseOrder) RETURN p.NoSuchProp AS x")
check("Neo4j warnings come back with the rows (success statuses filtered out)",
      w.get("warnings") == ["01N52: warn: property key does not exist. The property `NoSuchProp` does not exist."])
check("clean query has no warnings key", "warnings" not in r)
try:
    aura.whoami("999")
    check("unknown employee gives a clear message", False)
except SystemExit as e:
    check("unknown employee gives a clear message", "No Employee with EmployeeID '999'" in str(e) and "2 Employees" in str(e))

tmpl = (ROOT / "model" / "NorthWind_PLUS_Graph_Data_Model_Import_v2.3.2.cypher").read_text(encoding="utf-8")
i = tmpl.index('MATCH (:RolE {Title:"ProcurementPolicyAdmin"})-[ar:IS_ACTIVE_ROLE]')
governed = tmpl[i:tmpl.index(";", i)]
g = aura.run_governed(governed, {"requesterId": "25", "l1Limit": 8000.0, "l2Limit": 20000.0, "l3Limit": 500000.0, "justification": "test"})
check("governed write works through a managed write transaction", g.get("rows", [{}])[0].get("LimitsAfter") == [8000.0, 20000.0, 500000.0])
check(f"every transaction function carried the {QUERY_TIMEOUT_S}s timeout", seen_timeouts and all(t == QUERY_TIMEOUT_S for t in seen_timeouts))

print(f"\n{sum(checks)}/{len(checks)} checks passed")
sys.exit(0 if all(checks) else 1)
