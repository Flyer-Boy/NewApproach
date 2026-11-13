#!/usr/bin/env python3
"""
Build the agent's knowledge store (a relate .rl file) for NorthWind PLUS.

Sources, all from the model/ folder:
  - NorthwindPlusGraphType_v2.3.2.cypher        exact Neo4j names, property types, keys, relationship endpoints
  - NorthwindPlusGraph_RDF-turtle_v2.3.2.ttl    Entity vs Collection, rdfs:comment meanings
  - kb/semantics.json                           curated business meanings (from the import script's comments)
  - NorthWind_PLUS_Graph_Data_Model_Import_v2.3.2.cypher
                                                read templates (queries section) + the governed Approval Policy Change
  - NorthwindPlus_Stress_Test.py                simulation actions (the six loops' Cypher)

Knowledge graph written to relate:
  (:NodeType {name, category, description})-[:HAS_PROPERTY]->(:Property {key, name, type, notNull, isKey})
  (:NodeType)-[:SOURCE_OF]->(:RelType {name, description})-[:TARGETS]->(:NodeType)
  (:RelType)-[:HAS_PROPERTY]->(:Property)
  (:WorkflowStep {name, description})-[:INVOLVES]->(:RelType)
  (:QueryTemplate {name, title, description, cypher, kind, governance, params, source, status, ontologyVersion,
                   useCount})-[:USES]->(:NodeType), -[:TRAVERSES]->(:RelType), -[:PART_OF]->(:WorkflowStep)
  (:ModelPrinciple {text}), (:KnowledgeBase {ontologyVersion, builtAt})

The store is rebuilt from scratch on every run. Templates the agent learns later (status 'candidate' /
'approved') will need to be preserved across rebuilds -- that comes with the feedback stage.

Usage:
  python kb/build_kb.py                       # writes kb/northwind_kb.rl
  python kb/build_kb.py --store other.rl
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
from pathlib import Path

import rdflib
import relate

ONTOLOGY_VERSION = "2.3.2"
ROOT = Path(__file__).resolve().parent.parent
MODEL = ROOT / "model"
KB = ROOT / "kb"

GRAPH_TYPE_FILE = MODEL / "NorthwindPlusGraphType_v2.3.2.cypher"
TTL_FILE = MODEL / "NorthwindPlusGraph_RDF-turtle_v2.3.2.ttl"
IMPORT_FILE = MODEL / "NorthWind_PLUS_Graph_Data_Model_Import_v2.3.2.cypher"
HARNESS_FILE = MODEL / "NorthwindPlus_Stress_Test.py"
SEMANTICS_FILE = KB / "semantics.json"

WRITE_RE = re.compile(r"\b(CREATE|MERGE|SET|DELETE|REMOVE)\b")


# ---------------------------------------------------------------------------
# Ontology: GRAPH TYPE + TTL + curated semantics
# ---------------------------------------------------------------------------

def parse_props(block: str) -> list[dict]:
    props = []
    for part in block.split(","):
        part = " ".join(part.split())
        if not part:
            continue
        m = re.match(r"(\w+)\s*::\s*(.+?)(\s+NOT NULL)?$", part)
        if not m:
            raise ValueError(f"Unparsed property declaration: {part!r}")
        props.append({"name": m.group(1), "type": m.group(2), "notNull": bool(m.group(3))})
    return props


def parse_graph_type(path: Path) -> tuple[dict, list]:
    text = re.sub(r"//.*", "", path.read_text(encoding="utf-8"))
    nodes = {}
    for m in re.finditer(r"\((\w*):(\w+)\s*=>\s*\{(.*?)\}\s*\)(\s*REQUIRE\s*\(\w+\.(\w+)\)\s*IS KEY)?", text, re.S):
        label, block, key = m.group(2), m.group(3), m.group(5)
        props = parse_props(block)
        for p in props:
            p["isKey"] = (p["name"] == key)
        nodes[label] = {"props": props, "key": key}
    rels = []
    for m in re.finditer(r"\(:(\w+)\)-\[:(\w+)\s*=>\s*\{(.*?)\}\]->\(:(\w+)\)", text, re.S):
        props = parse_props(m.group(3))
        for p in props:
            p["isKey"] = False
        rels.append({"from": m.group(1), "name": m.group(2), "props": props, "to": m.group(4)})
    return nodes, rels


def camel(rel_type: str) -> str:
    parts = rel_type.lower().split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def load_ttl(path: Path) -> tuple[dict, dict]:
    g = rdflib.Graph()
    g.parse(path)
    ns = "http://example.org/northwindplus#"
    category, comments = {}, {}
    for cls, parent in g.subject_objects(rdflib.RDFS.subClassOf):
        if isinstance(parent, rdflib.URIRef) and str(parent) in (ns + "Entity", ns + "Collection"):
            category[str(cls).replace(ns, "")] = str(parent).replace(ns, "")
    for subj, comment in g.subject_objects(rdflib.RDFS.comment):
        if isinstance(subj, rdflib.URIRef) and str(subj).startswith(ns):
            comments[str(subj).replace(ns, "")] = str(comment)
    return category, comments


# ---------------------------------------------------------------------------
# Templates: import script queries section + harness actions
# ---------------------------------------------------------------------------

def code_part(line: str) -> str:
    """The line without a trailing // comment (the queries section has no '//' inside strings)."""
    return line.split("//", 1)[0]


def extract_script_templates(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    start = text.index("// **Approval Policy Change**  (v2.3.2)")
    end = text.index("//  End of Query Examples  //")
    lines = text[start:end].split("\n")

    templates, comments, body = [], [], []
    for line in lines:
        stripped = line.strip()
        if not body:
            if stripped.startswith("//-----"):
                comments = []
                continue
            if stripped.startswith("//"):
                c = stripped.lstrip("/").strip()
                if c.startswith(":param"):
                    comments = []          # parameter instructions, not a description
                    continue
                comments.append(c)
                continue
            if not stripped:
                comments = []
                continue
        body.append(line)
        if code_part(line).rstrip().endswith(";"):
            cypher = "\n".join(body).rstrip().rstrip(";").rstrip()
            desc = [c for c in comments if c and not set(c) <= set("#*- ")]
            templates.append({"comments": desc, "cypher": cypher})
            comments, body = [], []
    return templates


HARNESS_DESCRIPTIONS = {
    "customer_order": ("Create a random Customer Order", "Create one Open Customer Order for a random Customer, sold by a random Sales Representative, with 1-11 random available products."),
    "po_creation": ("Create Purchase Orders for low-stock Products", "Create one PO per Supplier whose available Products have effective stock (in stock + already on active POs - open order demand) near the reorder threshold."),
    "order_fulfillment": ("Fulfill the oldest Open Customer Order", "Ship the oldest Open Customer Order whose every line has enough stock; decrement inventory; mark it Fulfilled."),
    "l1_reject": ("L1 rejects a PO", "Level 1 rejects a random PO awaiting vetting."),
    "l1_approve_final": ("L1 approves a PO (final)", "Level 1 approves a PO whose cost is within its band; the PO moves to ApprovedPoS."),
    "l1_approve_passthrough": ("L1 approves a PO and passes it to L2", "Level 1 approves a PO whose cost exceeds its limit; it stays in NewPoS for L2."),
    "l2_reject": ("L2 rejects a PO", "Level 2 rejects a PO already approved by L1."),
    "l2_approve_final": ("L2 approves a PO (final)", "Level 2 approves a PO within its band; the PO moves to ApprovedPoS."),
    "l2_approve_passthrough": ("L2 approves a PO and passes it to L3", "Level 2 approves a PO above its limit; it stays in NewPoS for L3."),
    "l3_reject": ("L3 rejects a PO", "Level 3 rejects a PO already approved by L2."),
    "l3_approve_final": ("L3 approves a PO (final)", "Level 3 approves a PO within its band; the PO moves to ApprovedPoS."),
    "po_resubmit": ("Resubmit a rejected PO", "Create a new PO for a rejected PO's still-needed items, same Supplier, pointing back with HAS_PREVIOUS_PO."),
    "buyer_submit_po": ("Buyer submits an approved PO to its Supplier", "Move an approved PO to SubmittedPoS and into the Supplier's new-PO collection; create its RFQ collections."),
    "supplier_submit_rfq": ("Supplier submits an RFQ for a PO", "The Supplier quotes a new PO with an RFQ (full quantity at 70% of unit price)."),
    "rfq_reject": ("Buyer rejects an RFQ", "The Buyer rejects an RFQ awaiting vetting."),
    "rfq_approve": ("Buyer approves an RFQ", "The Buyer approves an RFQ that fits the PO budget; units are added to UnitsOnOrder."),
    "rfq_resubmit": ("Supplier resubmits a rejected RFQ", "The Supplier sends a new RFQ (65% of unit price) pointing back with HAS_PREVIOUS_RFQ."),
    "warehouse_delivery": ("Warehouse receives a PO's products", "A Warehouse Clerk receives an approved-RFQ PO: stock up, units on order down."),
    "finance_closure": ("Finance pays and closes a PO", "Finance pays a delivered PO and moves it to ClosedPoS (and the Supplier's closed POs)."),
}


def load_harness(path: Path):
    spec = importlib.util.spec_from_file_location("northwind_harness", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod   # dataclasses look their module up in sys.modules
    spec.loader.exec_module(mod)   # main() is guarded by __name__, so nothing runs
    return mod


def extract_harness_templates(path: Path) -> list[dict]:
    h = load_harness(path)
    out = []

    def add(name, loop, cypher, eligibility=None, weight=None):
        title, desc = HARNESS_DESCRIPTIONS[name]
        out.append({"name": f"sim_{name}", "title": title, "description": desc, "cypher": cypher.strip(),
                    "eligibility": (eligibility or "").strip(), "loop": loop, "weight": weight})

    add("customer_order", "customer-order", h.CUSTOMER_ORDER_QUERY)
    add("po_creation", "po-creation", h.PO_CREATION_QUERY)
    add("order_fulfillment", "order-fulfillment", h.ORDER_FULFILLMENT_QUERY)
    for loop, actions in (("po-vetting", h.PO_VETTING_ACTIONS), ("rfq-vetting", h.RFQ_VETTING_ACTIONS),
                          ("warehouse-finance", h.WAREHOUSE_FINANCE_ACTIONS)):
        for a in actions:
            add(a.name, loop, a.execute_query, a.eligibility_query, a.weight)
    return out


def slug(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    return s[:60].rstrip("_")


def concepts_in(cypher: str, labels: set, rel_types: set) -> tuple[list, list]:
    code = "\n".join(code_part(l) for l in cypher.split("\n"))
    used_labels = sorted({m for m in re.findall(r":`?([A-Za-z_]\w*)", code)} & labels)
    used_rels = sorted({m for m in re.findall(r"\b[A-Z][A-Z0-9_]*\b", code)} & rel_types)
    return used_labels, used_rels


def is_write(cypher: str) -> bool:
    code = "\n".join(code_part(l) for l in cypher.split("\n"))
    code = re.sub(r'"[^"]*"', '""', code)
    return bool(WRITE_RE.search(code))


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build(store: Path) -> dict:
    nodes, rels = parse_graph_type(GRAPH_TYPE_FILE)
    category, ttl_comments = load_ttl(TTL_FILE)
    sem = json.loads(SEMANTICS_FILE.read_text(encoding="utf-8"))
    labels, rel_types = set(nodes), {r["name"] for r in rels}

    missing = (set(sem["node_types"]) - labels) | (set(sem["rel_types"]) - rel_types)
    for step in sem["workflow_steps"].values():
        missing |= set(step["rel_types"]) - rel_types
    if missing:
        raise SystemExit(f"semantics.json names things the GRAPH TYPE doesn't declare: {sorted(missing)}")

    if store.exists():
        store.unlink()
    conn = relate.connect(str(store))
    conn.autocommit = False

    def run(q, p=None):
        conn.execute(q, p or {})

    # Ontology
    run("CREATE (:KnowledgeBase {ontologyVersion:$v, builtAt:datetime(), sources:$s})",
        {"v": ONTOLOGY_VERSION, "s": [p.name for p in (GRAPH_TYPE_FILE, TTL_FILE, IMPORT_FILE, HARNESS_FILE, SEMANTICS_FILE)]})
    for i, text in enumerate(sem["model_principles"]):
        run("CREATE (:ModelPrinciple {rank:$i, text:$t})", {"i": i, "t": text})

    for label, info in nodes.items():
        desc = sem["node_types"].get(label) or ttl_comments.get(label) or ""
        if ttl_comments.get(label) and sem["node_types"].get(label) and ttl_comments[label] not in desc:
            desc = f"{desc} {ttl_comments[label]}"
        run("CREATE (:NodeType {name:$n, category:$c, description:$d, keyProperty:$k})",
            {"n": label, "c": category.get(label, "Entity"), "d": desc, "k": info["key"]})
        for p in info["props"]:
            run("""MATCH (n:NodeType {name:$owner})
                   CREATE (n)-[:HAS_PROPERTY]->(:Property {key:$key, name:$name, type:$type, notNull:$nn, isKey:$ik})""",
                {"owner": label, "key": f"{label}.{p['name']}", "name": p["name"], "type": p["type"], "nn": p["notNull"], "ik": p["isKey"]})

    for r in rels:
        desc = sem["rel_types"].get(r["name"]) or ttl_comments.get(camel(r["name"])) or ""
        run("""MATCH (a:NodeType {name:$from}), (b:NodeType {name:$to})
               CREATE (a)-[:SOURCE_OF]->(t:RelType {name:$name, description:$d, pattern:$pattern})-[:TARGETS]->(b)""",
            {"from": r["from"], "to": r["to"], "name": r["name"], "d": desc,
             "pattern": f"(:{r['from']})-[:{r['name']}]->(:{r['to']})"})
        for p in r["props"]:
            run("""MATCH (t:RelType {name:$owner})
                   CREATE (t)-[:HAS_PROPERTY]->(:Property {key:$key, name:$name, type:$type, notNull:$nn, isKey:false})""",
                {"owner": r["name"], "key": f"{r['name']}.{p['name']}", "name": p["name"], "type": p["type"], "nn": p["notNull"]})

    for name, step in sem["workflow_steps"].items():
        run("CREATE (:WorkflowStep {name:$n, description:$d})", {"n": name, "d": step["description"]})
        run("""MATCH (w:WorkflowStep {name:$n}) UNWIND $rels AS r
               MATCH (t:RelType {name:r}) CREATE (w)-[:INVOLVES]->(t)""", {"n": name, "rels": step["rel_types"]})

    # Templates
    templates = []
    for t in extract_script_templates(IMPORT_FILE):
        if not t["comments"]:
            continue
        title = t["comments"][0]
        write = is_write(t["cypher"])
        if "PolicyChange" in t["cypher"] and write:
            governance = "governed"          # exposed to the agent, with role check + confirmation
        elif write:
            governance = "admin"             # demo/maintenance writes (e.g. the restock cheat): not exposed
        else:
            governance = "read"
        templates.append({"name": slug(title), "title": title, "description": " ".join(t["comments"]),
                          "cypher": t["cypher"], "kind": "action" if write else "read", "governance": governance,
                          "source": "import-script", "loop": None, "weight": None, "eligibility": ""})
    for t in extract_harness_templates(HARNESS_FILE):
        templates.append({**t, "kind": "action", "governance": "simulation", "source": "stress-harness"})

    seen = {}
    for t in templates:
        base = t["name"]
        seen[base] = seen.get(base, 0) + 1
        if seen[base] > 1:
            t["name"] = f"{base}_{seen[base]}"
        t["params"] = sorted(set(re.findall(r"\$(\w+)", t["cypher"])))
        t["labels"], t["rels"] = concepts_in(t["cypher"], labels, rel_types)
        run("""CREATE (q:QueryTemplate {name:$name, title:$title, description:$description, cypher:$cypher,
                       kind:$kind, governance:$governance, params:$params, source:$source, loop:$loop,
                       weight:$weight, eligibility:$eligibility, status:'seed', ontologyVersion:$v, useCount:0})""",
            {**{k: t[k] for k in ("name", "title", "description", "cypher", "kind", "governance", "params",
                                  "source", "loop", "weight", "eligibility")}, "v": ONTOLOGY_VERSION})
        run("""MATCH (q:QueryTemplate {name:$name})
               UNWIND $labels AS l MATCH (n:NodeType {name:l}) CREATE (q)-[:USES]->(n)""", t)
        run("""MATCH (q:QueryTemplate {name:$name})
               UNWIND $rels AS r MATCH (rt:RelType {name:r}) CREATE (q)-[:TRAVERSES]->(rt)""", t)

    # Workflow links: keyword rules first (title/description), then shared relationship types for the rest
    for name, step in sem["workflow_steps"].items():
        for kw in step.get("keywords", []):
            run("""MATCH (q:QueryTemplate), (w:WorkflowStep {name:$n})
                   WHERE (toLower(q.title) CONTAINS $kw OR toLower(q.description) CONTAINS $kw)
                     AND NOT (q)-[:PART_OF]->(w)
                   CREATE (q)-[:PART_OF {via:'keyword'}]->(w)""", {"n": name, "kw": kw.lower()})
    run("""MATCH (q:QueryTemplate) WHERE NOT (q)-[:PART_OF]->()
           MATCH (q)-[:TRAVERSES]->(:RelType)<-[:INVOLVES]-(w:WorkflowStep)
           WITH DISTINCT q, w CREATE (q)-[:PART_OF {via:'relationship'}]->(w)""")
    conn.commit()

    # Indexes (autocommit for DDL)
    conn.autocommit = True
    for ddl in (
        "CREATE CONSTRAINT nodetype_name IF NOT EXISTS FOR (n:NodeType) REQUIRE n.name IS UNIQUE",
        "CREATE CONSTRAINT reltype_name IF NOT EXISTS FOR (r:RelType) REQUIRE r.name IS UNIQUE",
        "CREATE CONSTRAINT template_name IF NOT EXISTS FOR (q:QueryTemplate) REQUIRE q.name IS UNIQUE",
        "CREATE FULLTEXT INDEX template_text IF NOT EXISTS FOR (q:QueryTemplate) ON EACH [q.title, q.description, q.name]",
        "CREATE FULLTEXT INDEX nodetype_text IF NOT EXISTS FOR (n:NodeType) ON EACH [n.name, n.description]",
        "CREATE FULLTEXT INDEX reltype_text IF NOT EXISTS FOR (r:RelType) ON EACH [r.name, r.description]",
    ):
        conn.execute(ddl)

    stats = {k: conn.execute(f"MATCH (n:{k}) RETURN count(n) AS c").single()["c"]
             for k in ("NodeType", "RelType", "Property", "WorkflowStep", "QueryTemplate", "ModelPrinciple")}
    stats["templates_by_governance"] = {r["g"]: r["c"] for r in conn.execute(
        "MATCH (q:QueryTemplate) RETURN q.governance AS g, count(q) AS c ORDER BY g")}
    conn.close()
    return stats


def main():
    ap = argparse.ArgumentParser(description="Build the NorthWind PLUS agent knowledge store in relate.")
    ap.add_argument("--store", default=str(KB / "northwind_kb.rl"))
    args = ap.parse_args()
    stats = build(Path(args.store))
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
