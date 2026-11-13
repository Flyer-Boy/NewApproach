"""
Neo4j Aura side of the agent: read queries in read transactions, and the governed approval-band change.

Safety layers for reads:
  1. A write-keyword check rejects CREATE/MERGE/SET/DELETE/REMOVE before anything is sent.
  2. Reads run in a READ transaction (session.execute_read); Neo4j itself refuses writes there.
  3. A server-side timeout and a row cap keep a bad query from hogging the live simulation.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from neo4j import GraphDatabase, NotificationDisabledClassification, unit_of_work
import logging

# The sign-in query checks IS_ACTIVE_ROLE.EndDate, which no role has yet; Neo4j warns about unknown property
# keys. Keep that noise out of the console (stage 4: pass such warnings to the agent instead).
logging.getLogger("neo4j.notifications").setLevel(logging.ERROR)

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "kb"))
from build_kb import is_write  # noqa: E402  (same write detection the knowledge store uses)

QUERY_TIMEOUT_S = 20
MAX_ROWS_FETCHED = 500


def _plain(value):
    """Neo4j values -> JSON-friendly values (temporal types, nodes, lists, maps)."""
    if isinstance(value, dict):
        return {k: _plain(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_plain(v) for v in value]
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)   # DateTime, Duration, etc. -> ISO-ish text


class Aura:
    def __init__(self):
        uri = os.environ.get("NEO4J_URI")
        user = os.environ.get("NEO4J_USER") or os.environ.get("NEO4J_USERNAME", "neo4j")
        password = os.environ.get("NEO4J_PASSWORD")
        self.database = os.environ.get("NEO4J_DATABASE", "neo4j")
        if not uri or not password:
            raise SystemExit("Set NEO4J_URI and NEO4J_PASSWORD (e.g. in the project's .env file).")
        self.driver = GraphDatabase.driver(
            uri, auth=(user, password),
            notifications_disabled_classifications=[NotificationDisabledClassification.PERFORMANCE])
        self.driver.verify_connectivity()

    def close(self):
        self.driver.close()

    # ---------------- reads ----------------

    def read(self, cypher: str, params: dict | None = None) -> dict:
        if is_write(cypher):
            return {"error": "Rejected: this query contains a write clause. Only read queries can be run with this tool."}

        # The timeout goes on the transaction function: managed transactions don't accept Query objects.
        @unit_of_work(timeout=QUERY_TIMEOUT_S)
        def work(tx):
            result = tx.run(cypher, params or {})
            rows = []
            for record in result:
                rows.append(_plain(record.data()))
                if len(rows) >= MAX_ROWS_FETCHED:
                    break
            return rows

        try:
            with self.driver.session(database=self.database) as session:
                rows = session.execute_read(work)
            return {"rows": rows, "row_count": len(rows), "capped": len(rows) >= MAX_ROWS_FETCHED}
        except Exception as exc:   # syntax errors, timeouts, unknown labels... the model can fix and retry
            return {"error": f"{type(exc).__name__}: {exc}"}

    # ---------------- identity ----------------

    def whoami(self, employee_id: str) -> dict | None:
        result = self.read("""
            MATCH (e:Employee {EmployeeID:$id})
            OPTIONAL MATCH (e)-[:HAS_PERSON]->(p:Person)
            OPTIONAL MATCH (r:RolE)-[ar:IS_ACTIVE_ROLE]->(e) WHERE ar.EndDate IS NULL
            RETURN e.EmployeeID AS employeeId, coalesce(p.FirstName + ' ' + p.LastName, e.Email) AS name,
                   collect(r.Title) AS roles""", {"id": employee_id})
        if "error" in result:
            raise SystemExit(f"Could not look up Employee {employee_id!r} on {self.database!r}: {result['error']}")
        rows = result["rows"]
        if not rows:
            count = self.read("MATCH (e:Employee) RETURN count(e) AS n").get("rows", [{}])[0].get("n")
            raise SystemExit(f"No Employee with EmployeeID {employee_id!r} in database {self.database!r} "
                             f"({count} Employees there). Is this the v2.3.2 database, and is NEO4J_DATABASE right?")
        return rows[0]

    # ---------------- governed write ----------------

    def run_governed(self, cypher: str, params: dict) -> dict:
        """Runs the governed template (role check, validation and audit are inside the Cypher itself)."""
        @unit_of_work(timeout=QUERY_TIMEOUT_S)
        def work(tx):
            return [_plain(r.data()) for r in tx.run(cypher, params)]
        try:
            with self.driver.session(database=self.database) as session:
                rows = session.execute_write(work)
            return {"rows": rows}
        except Exception as exc:
            return {"error": f"{type(exc).__name__}: {exc}"}
