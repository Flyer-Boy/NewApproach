"""
Shared write helpers for the knowledge store: used by build_kb.py (seed templates) and by the agent (templates it
learns), so both create exactly the same shape:

  (:QueryTemplate {..., labels, rels, embedding?})-[:USES]->(:NodeType), -[:TRAVERSES]->(:RelType),
                                                  -[:PART_OF {via}]->(:WorkflowStep)
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from embeddings import template_text

KB_DIR = Path(__file__).resolve().parent
SEMANTICS_FILE = KB_DIR / "semantics.json"
WRITE_RE = re.compile(r"\b(CREATE|MERGE|SET|DELETE|REMOVE)\b")


def load_semantics() -> dict:
    return json.loads(SEMANTICS_FILE.read_text(encoding="utf-8"))


def code_part(line: str) -> str:
    """The line without a trailing // comment (the queries have no '//' inside strings)."""
    return line.split("//", 1)[0]


def is_write(cypher: str) -> bool:
    code = "\n".join(code_part(l) for l in cypher.split("\n"))
    code = re.sub(r'"[^"]*"', '""', code)
    code = re.sub(r"'[^']*'", "''", code)
    return bool(WRITE_RE.search(code))


def concepts_in(cypher: str, labels: set, rel_types: set) -> tuple[list, list]:
    code = "\n".join(code_part(l) for l in cypher.split("\n"))
    used_labels = sorted({m for m in re.findall(r":`?([A-Za-z_]\w*)", code)} & labels)
    used_rels = sorted({m for m in re.findall(r"\b[A-Z][A-Z0-9_]*\b", code)} & rel_types)
    return used_labels, used_rels


def unknown_names(cypher: str, labels: set, rel_types: set) -> list[str]:
    """Label-like / rel-type-like names in the Cypher that the ontology doesn't declare (stale or misspelled)."""
    code = "\n".join(code_part(l) for l in cypher.split("\n"))
    code = re.sub(r'"[^"]*"|\'[^\']*\'', "", code)
    found = set(re.findall(r"\(\s*\w*\s*:`?([A-Z]\w*)", code))                 # (x:Label
    found |= set(re.findall(r"\[\s*\w*\s*:`?([A-Z][A-Z0-9_]*)", code))         # [r:REL_TYPE
    found |= set(re.findall(r"\|\s*([A-Z][A-Z0-9_]{3,})", code))               # |OTHER_REL
    return sorted(found - labels - rel_types)


def slug(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    return s[:60].rstrip("_")


def schema_names(conn) -> tuple[set, set]:
    labels = {r["n"] for r in conn.execute("MATCH (n:NodeType) RETURN n.name AS n")}
    rels = {r["n"] for r in conn.execute("MATCH (r:RelType) RETURN r.name AS n")}
    return labels, rels


def unique_name(conn, base: str) -> str:
    name, i = base, 1
    while conn.execute("MATCH (q:QueryTemplate {name:$n}) RETURN count(q) AS c", {"n": name}).single()["c"]:
        i += 1
        name = f"{base}_{i}"
    return name


def add_template(conn, t: dict, labels: set, rel_types: set) -> dict:
    """Create one QueryTemplate and its concept links. t needs name, title, description, cypher and the
    governance fields; returns t with params/labels/rels filled in."""
    t = dict(t)
    t.setdefault("params", sorted(set(re.findall(r"\$(\w+)", t["cypher"]))))
    t["labels"], t["rels"] = concepts_in(t["cypher"], labels, rel_types)
    props = {k: t.get(k) for k in (
        "name", "title", "description", "cypher", "kind", "governance", "params", "source", "loop", "weight",
        "eligibility", "status", "ontologyVersion", "createdBy", "question", "labels", "rels")}
    props["useCount"] = t.get("useCount", 0)
    conn.execute("CREATE (q:QueryTemplate) SET q = $props, q.createdAt = datetime()", {"props": props})
    conn.execute("""MATCH (q:QueryTemplate {name:$name})
                    UNWIND $labels AS l MATCH (n:NodeType {name:l}) CREATE (q)-[:USES]->(n)""", t)
    conn.execute("""MATCH (q:QueryTemplate {name:$name})
                    UNWIND $rels AS r MATCH (rt:RelType {name:r}) CREATE (q)-[:TRAVERSES]->(rt)""", t)
    return t


def link_workflows(conn, sem: dict, name: str | None = None):
    """PART_OF links by keyword (title/description) AND by shared relationship types. name=None: all templates."""
    where = "q.name = $tname" if name else "true"
    for wname, step in sem["workflow_steps"].items():
        for kw in step.get("keywords", []):
            conn.execute(f"""MATCH (q:QueryTemplate), (w:WorkflowStep {{name:$n}})
                    WHERE {where} AND (toLower(q.title) CONTAINS $kw OR toLower(q.description) CONTAINS $kw)
                      AND NOT (q)-[:PART_OF]->(w)
                    CREATE (q)-[:PART_OF {{via:'keyword'}}]->(w)""", {"n": wname, "kw": kw.lower(), "tname": name})
    conn.execute(f"""MATCH (q:QueryTemplate) WHERE {where}
            MATCH (q)-[:TRAVERSES]->(:RelType)<-[:INVOLVES]-(w:WorkflowStep)
            WHERE NOT (q)-[:PART_OF]->(w)
            WITH DISTINCT q, w CREATE (q)-[:PART_OF {{via:'relationship'}}]->(w)""", {"tname": name})


def embed_templates(conn, embedder, name: str | None = None) -> int:
    """Set q.embedding for one template (name) or all templates without one."""
    where = "q.name = $tname" if name else "q.embedding IS NULL"
    rows = [dict(r) for r in conn.execute(f"""
        MATCH (q:QueryTemplate) WHERE {where}
        OPTIONAL MATCH (q)-[:PART_OF]->(w:WorkflowStep)
        WITH q, collect(DISTINCT w.name) AS workflows
        RETURN q.name AS name, q.title AS title, q.description AS description, workflows,
               coalesce(q.labels, []) + coalesce(q.rels, []) AS concepts""", {"tname": name})]
    if not rows:
        return 0
    vectors = embedder.embed_documents([template_text(r["title"], r["description"], r["workflows"], r["concepts"])
                                        for r in rows])
    for r, v in zip(rows, vectors):
        conn.execute("MATCH (q:QueryTemplate {name:$n}) SET q.embedding = vector($v, $d, FLOAT32)",
                     {"n": r["name"], "v": v, "d": embedder.dims})
    return len(rows)
