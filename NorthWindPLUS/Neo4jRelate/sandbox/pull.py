"""
Copies the part of the live graph that PO vetting needs into a fresh, local relate store.

Two ways, same result:
  - `relate pull` (the relate CLI, over Aura's HTTP Query API): used whenever the `relate` binary is found
    (RELATE_BIN, or on PATH). On Colab the notebook installs it.
  - a fallback copier: the same statement through the Neo4j Python driver in one read transaction, written into
    relate through the Python API. For machines without the CLI (and for the offline tests).

The pull is ONE statement (four parts joined by UNION ALL), so Aura answers it from one transaction: the six loops
keep writing while we read, and separate statements could see the queue at different moments.

`relate pull` refuses a non-empty destination (a re-pull is never a merge), so the destination is deleted first.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import relate

PULL_TIMEOUT_S = 180

# Everything the harness's PO-vetting actions touch, except po_resubmit (left out of v1: it needs stock levels,
# every active PO and every open customer order).
PULL_QUERY = """
MATCH p = (:NewPoS)-[:IS_NEW_PO_STATE]->(:PurchaseOrder)-[:HAS_PO_ITEM]->(:Product)
RETURN p
UNION ALL
MATCH p = (:NewPoS)-[:IS_NEW_PO_STATE]->(:PurchaseOrder)
          -[:HAS_L1_PO_APPROVAL|HAS_L2_PO_APPROVAL|HAS_L1_PO_REJECTION|HAS_L2_PO_REJECTION|HAS_L3_PO_REJECTION]->(:Employee)
RETURN p
UNION ALL
MATCH p = (r:RolE)-[:IS_ACTIVE_ROLE]->(:Employee)
WHERE r.Title IN ["Level1Approver", "Level2Approver", "Level3Approver"]
RETURN p
UNION ALL
MATCH p = (c) WHERE c:NewPoS OR c:ApprovedPoS OR c:RejectedPoS
RETURN p
"""


def find_cli() -> str | None:
    return os.environ.get("RELATE_BIN") or shutil.which("relate")


def _fresh(dest: Path):
    for f in dest.parent.glob(dest.name + "*"):   # the store and any sidecar files
        shutil.rmtree(f) if f.is_dir() else f.unlink()
    dest.parent.mkdir(parents=True, exist_ok=True)


def pull(dest: Path, aura=None, method: str = "auto", env: dict | None = None) -> dict:
    """Pull the vetting subgraph into `dest`. method: auto | cli | driver. `aura` (agent.aura.Aura) is needed for
    the driver fallback. Returns where the data came from, when, and the pull's own summary."""
    dest = Path(dest)
    _fresh(dest)
    cli = find_cli()
    if method == "cli" or (method == "auto" and cli):
        if not cli:
            raise RuntimeError("The relate CLI isn't installed (set RELATE_BIN or put `relate` on PATH).")
        return _pull_cli(cli, dest, env)
    if aura is None:
        raise RuntimeError("No relate CLI found, and no Aura connection was given for the fallback copier.")
    return _pull_driver(dest, aura)


def _pull_cli(cli: str, dest: Path, env: dict | None) -> dict:
    run_env = dict(os.environ if env is None else env)
    if "NEO4J_USERNAME" not in run_env and run_env.get("NEO4J_USER"):
        run_env["NEO4J_USERNAME"] = run_env["NEO4J_USER"]
    pulled_at = datetime.now(timezone.utc)
    r = subprocess.run([cli, "pull", "--query", PULL_QUERY, "--database", str(dest)],
                       env=run_env, capture_output=True, text=True, timeout=PULL_TIMEOUT_S)
    if r.returncode != 0:
        raise RuntimeError(f"relate pull failed (exit {r.returncode}): {(r.stderr or r.stdout).strip()[-1500:]}")
    summary = next((l for l in (r.stdout + "\n" + r.stderr).splitlines() if l.startswith("pulled ")), r.stdout.strip())
    m = re.search(r"pulled (\d+) new / (\d+) reused nodes, (\d+) new / (\d+) reused rels", summary)
    return {"method": "relate pull", "pulled_at": pulled_at.isoformat(timespec="seconds"), "summary": summary,
            "nodes": int(m.group(1)) if m else None, "relationships": int(m.group(3)) if m else None}


# ---------------- fallback copier ----------------

def _plain(value):
    """Driver values -> values the relate Python API accepts. Neo4j and relate temporal types both have to_native()."""
    if hasattr(value, "to_native"):
        return value.to_native()
    if isinstance(value, list):
        return [_plain(v) for v in value]
    return value


def read_paths_neo4j(aura) -> tuple[dict, dict]:
    """Runs PULL_QUERY on Aura in one read transaction; returns (nodes, rels) keyed by element id."""
    nodes, rels = {}, {}

    def work(tx):
        for record in tx.run(PULL_QUERY):
            path = record["p"]
            for n in path.nodes:
                nodes[n.element_id] = (sorted(n.labels), {k: _plain(v) for k, v in n.items()})
            for r in path.relationships:
                rels[r.element_id] = (r.type, r.start_node.element_id, r.end_node.element_id,
                                      {k: _plain(v) for k, v in r.items()})

    with aura.driver.session(database=aura.database) as session:
        session.execute_read(work)
    return nodes, rels


def read_paths_relate(conn) -> tuple[dict, dict]:
    """The same, from a relate store standing in for Aura (offline tests)."""
    nodes, rels = {}, {}
    for row in conn.execute(PULL_QUERY):
        path = row["p"]
        for n in path.nodes:
            nodes[n.element_id] = (sorted(n.labels), {k: _plain(v) for k, v in n.properties.items()})
        for r in path.relationships:
            rels[r.element_id] = (r.type, r.start_node_element_id, r.end_node_element_id,
                                  {k: _plain(v) for k, v in r.properties.items()})
    return nodes, rels


def write_store(dest: Path, nodes: dict, rels: dict):
    """Writes nodes and relationships into a new relate store, keeping labels, types and properties."""
    conn = relate.connect(str(dest))
    try:
        conn.execute("CREATE INDEX pulled_eid IF NOT EXISTS FOR (n:_Pulled) ON (n._eid)")
        by_labels: dict[tuple, list] = {}
        for eid, (labels, props) in nodes.items():
            by_labels.setdefault(tuple(labels), []).append({"eid": eid, "props": props})
        for labels, rows in by_labels.items():
            conn.execute("UNWIND $rows AS row CREATE (n:_Pulled) SET n = row.props, n._eid = row.eid, n:$($labels)",
                         {"rows": rows, "labels": list(labels)})
        by_type: dict[str, list] = {}
        for _, (rtype, start, end, props) in rels.items():
            by_type.setdefault(rtype, []).append({"s": start, "e": end, "props": props})
        for rtype, rows in by_type.items():
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", rtype):
                raise ValueError(f"Unexpected relationship type {rtype!r}")
            conn.execute(f"""UNWIND $rows AS row
                             MATCH (a:_Pulled {{_eid: row.s}}), (b:_Pulled {{_eid: row.e}})
                             CREATE (a)-[r:`{rtype}`]->(b) SET r = row.props""", {"rows": rows})
        conn.execute("MATCH (n:_Pulled) REMOVE n._eid, n:_Pulled")
        conn.execute("DROP INDEX pulled_eid IF EXISTS")
    finally:
        conn.close()


def _pull_driver(dest: Path, aura) -> dict:
    pulled_at = datetime.now(timezone.utc)
    # A relate connection standing in for Aura (the offline tests) has `conn` and no `driver`.
    nodes, rels = read_paths_neo4j(aura) if hasattr(aura, "driver") else read_paths_relate(aura.conn)
    write_store(dest, nodes, rels)
    return {"method": "driver (fallback: no relate CLI found)", "pulled_at": pulled_at.isoformat(timespec="seconds"),
            "summary": f"copied {len(nodes)} nodes, {len(rels)} rels to {dest}",
            "nodes": len(nodes), "relationships": len(rels)}
