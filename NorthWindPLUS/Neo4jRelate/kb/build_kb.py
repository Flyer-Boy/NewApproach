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
  (:NodeType)-[:SOURCE_OF]->(:RelType {name, pattern, description})-[:TARGETS]->(:NodeType)
  (:WorkflowStep {name, description})-[:INVOLVES]->(:RelType)
  (:QueryTemplate {name, title, description, cypher, kind, governance, params, labels, rels, source, status,
                   ontologyVersion, useCount, embedding?})-[:USES]->(:NodeType), -[:TRAVERSES]->(:RelType),
                                                         -[:PART_OF {via}]->(:WorkflowStep)
  (:Interaction {question, answer, employeeId, model, usage...})-[:USED]->(:QueryTemplate), -[:CREATED]->(:QueryTemplate)
  (:ModelPrinciple {text}), (:KnowledgeBase {ontologyVersion, builtAt, embeddingModel, embeddingDims})

Rebuilding keeps what the agent learned: templates it saved (source 'agent') and the Interaction history are
exported from the old store and put back, re-linked to the current ontology. A learned template whose Cypher names
something the ontology no longer declares is kept but marked status 'needs-review'.

Usage:
  python kb/build_kb.py                              # writes kb/northwind_kb.rl, no embeddings
  python kb/build_kb.py --embeddings voyage-4-nano   # + vectors (see kb/embeddings.py)
  python kb/build_kb.py --fresh                      # also drop learned templates and history
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import rdflib  # noqa: E402
import relate  # noqa: E402

from embeddings import get_embedder  # noqa: E402
from kb_write import (add_template, code_part, embed_templates, is_write, link_workflows,  # noqa: E402,F401
                      load_semantics, slug, unknown_names, concepts_in)

ONTOLOGY_VERSION = "2.3.2"
ROOT = Path(__file__).resolve().parent.parent
MODEL = ROOT / "model"
KB = ROOT / "kb"

GRAPH_TYPE_FILE = MODEL / "NorthwindPlusGraphType_v2.3.2.cypher"
TTL_FILE = MODEL / "NorthwindPlusGraph_RDF-turtle_v2.3.2.ttl"
IMPORT_FILE = MODEL / "NorthWind_PLUS_Graph_Data_Model_Import_v2.3.2.cypher"
HARNESS_FILE = MODEL / "NorthwindPlus_Stress_Test.py"
SEMANTICS_FILE = KB / "semantics.json"


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
# Seed templates: import script queries section + harness actions
# ---------------------------------------------------------------------------

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


def seed_templates() -> list[dict]:
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
                          "source": "import-script"})
    for t in extract_harness_templates(HARNESS_FILE):
        templates.append({**t, "kind": "action", "governance": "simulation", "source": "stress-harness"})
    seen = {}
    for t in templates:
        base = t["name"]
        seen[base] = seen.get(base, 0) + 1
        if seen[base] > 1:
            t["name"] = f"{base}_{seen[base]}"
        t.update(status="seed", ontologyVersion=ONTOLOGY_VERSION)
    return templates


# ---------------------------------------------------------------------------
# Learned knowledge: survives rebuilds
# ---------------------------------------------------------------------------

def export_learned(store: Path) -> dict:
    if not store.exists():
        return {"templates": [], "interactions": []}
    conn = relate.connect(str(store), read_only=True)
    try:
        templates = [dict(r["q"]) for r in conn.execute(
            "MATCH (q:QueryTemplate) WHERE q.source = 'agent' RETURN properties(q) AS q")]
        interactions = [dict(r) for r in conn.execute("""
            MATCH (i:Interaction)
            OPTIONAL MATCH (i)-[:USED]->(u:QueryTemplate)
            OPTIONAL MATCH (i)-[:CREATED]->(c:QueryTemplate)
            RETURN properties(i) AS props, collect(DISTINCT u.name) AS used, collect(DISTINCT c.name) AS created""")]
        uses = {r["n"]: r["c"] for r in conn.execute(
            "MATCH (q:QueryTemplate) WHERE q.useCount > 0 RETURN q.name AS n, q.useCount AS c")}
    except Exception:                      # an older store without these labels/properties
        templates, interactions, uses = [], [], {}
    finally:
        conn.close()
    for t in templates:
        t.pop("embedding", None)
        t.pop("createdAt", None)
    for i in interactions:
        i["props"] = {k: (str(v) if type(v).__name__ == "Temporal" else v) for k, v in i["props"].items()}
    return {"templates": templates, "interactions": interactions, "useCounts": uses}


def restore_learned(conn, learned: dict, labels: set, rel_types: set, sem: dict) -> dict:
    restored = review = 0
    for t in learned["templates"]:
        stale = unknown_names(t["cypher"], labels, rel_types)
        if stale:
            t["status"], t["reviewReason"] = "needs-review", f"Not in ontology {ONTOLOGY_VERSION}: {', '.join(stale)}"
            review += 1
        add_template(conn, t, labels, rel_types)
        if stale:
            conn.execute("MATCH (q:QueryTemplate {name:$n}) SET q.reviewReason = $r", {"n": t["name"], "r": t["reviewReason"]})
        link_workflows(conn, sem, t["name"])
        restored += 1
    for name, count in (learned.get("useCounts") or {}).items():
        conn.execute("MATCH (q:QueryTemplate {name:$n}) SET q.useCount = $c", {"n": name, "c": count})
    for i in learned["interactions"]:
        conn.execute("CREATE (i:Interaction) SET i = $p", {"p": i["props"]})
        for rel, names in (("USED", i["used"]), ("CREATED", i["created"])):
            conn.execute(f"""MATCH (i:Interaction {{id:$id}}) UNWIND $names AS n
                             MATCH (q:QueryTemplate {{name:n}}) CREATE (i)-[:{rel}]->(q)""",
                         {"id": i["props"].get("id"), "names": names})
    return {"learned_templates": restored, "needs_review": review, "interactions": len(learned["interactions"])}


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build(store: Path, embeddings: str | None = None, fresh: bool = False) -> dict:
    nodes, rels = parse_graph_type(GRAPH_TYPE_FILE)
    category, ttl_comments = load_ttl(TTL_FILE)
    sem = load_semantics()
    labels, rel_types = set(nodes), {r["name"] for r in rels}

    missing = (set(sem["node_types"]) - labels) | (set(sem["rel_types"]) - rel_types)
    for step in sem["workflow_steps"].values():
        missing |= set(step["rel_types"]) - rel_types
    if missing:
        raise SystemExit(f"semantics.json names things the GRAPH TYPE doesn't declare: {sorted(missing)}")

    embedder = embeddings if hasattr(embeddings, "embed_documents") else get_embedder(embeddings)   # name or loaded embedder
    learned = {"templates": [], "interactions": []} if fresh else export_learned(store)
    for suffix in ("", "-wal", "-shm", "-journal"):
        Path(str(store) + suffix).unlink(missing_ok=True)
    conn = relate.connect(str(store))
    conn.autocommit = False

    def run(q, p=None):
        conn.execute(q, p or {})

    run("""CREATE (:KnowledgeBase {ontologyVersion:$v, builtAt:datetime(), sources:$s,
                                   embeddingModel:$em, embeddingDims:$ed})""",
        {"v": ONTOLOGY_VERSION, "s": [p.name for p in (GRAPH_TYPE_FILE, TTL_FILE, IMPORT_FILE, HARNESS_FILE, SEMANTICS_FILE)],
         "em": embedder.name if embedder else "none", "ed": embedder.dims if embedder else 0})
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

    for t in seed_templates():
        add_template(conn, t, labels, rel_types)
    link_workflows(conn, sem)
    restored = restore_learned(conn, learned, labels, rel_types, sem)
    if embedder:
        embedded = embed_templates(conn, embedder)
    conn.commit()

    # Indexes (autocommit for DDL)
    conn.autocommit = True
    ddl = [
        "CREATE CONSTRAINT nodetype_name IF NOT EXISTS FOR (n:NodeType) REQUIRE n.name IS UNIQUE",
        "CREATE CONSTRAINT reltype_name IF NOT EXISTS FOR (r:RelType) REQUIRE r.name IS UNIQUE",
        "CREATE CONSTRAINT template_name IF NOT EXISTS FOR (q:QueryTemplate) REQUIRE q.name IS UNIQUE",
        "CREATE FULLTEXT INDEX template_text IF NOT EXISTS FOR (q:QueryTemplate) ON EACH [q.title, q.description, q.name]",
        "CREATE FULLTEXT INDEX nodetype_text IF NOT EXISTS FOR (n:NodeType) ON EACH [n.name, n.description]",
        "CREATE FULLTEXT INDEX reltype_text IF NOT EXISTS FOR (r:RelType) ON EACH [r.name, r.description]",
        "CREATE FULLTEXT INDEX interaction_text IF NOT EXISTS FOR (i:Interaction) ON EACH [i.question]",
    ]
    if embedder:
        ddl.append(f"""CREATE VECTOR INDEX template_vec IF NOT EXISTS FOR (q:QueryTemplate) ON (q.embedding)
                       OPTIONS {{indexConfig: {{`vector.dimensions`: {embedder.dims}, `vector.similarity_function`: 'cosine'}}}}""")
    for statement in ddl:
        conn.execute(statement)

    stats = {k: conn.execute(f"MATCH (n:{k}) RETURN count(n) AS c").single()["c"]
             for k in ("NodeType", "RelType", "Property", "WorkflowStep", "QueryTemplate", "ModelPrinciple", "Interaction")}
    stats["templates_by_governance"] = {r["g"]: r["c"] for r in conn.execute(
        "MATCH (q:QueryTemplate) RETURN q.governance AS g, count(q) AS c ORDER BY g")}
    stats.update(restored)
    stats["embeddings"] = f"{embedder.name} ({embedder.dims} dims, {embedded} templates)" if embedder else "none"
    conn.close()
    return stats


def main():
    ap = argparse.ArgumentParser(description="Build the NorthWind PLUS agent knowledge store in relate.")
    ap.add_argument("--store", default=str(KB / "northwind_kb.rl"))
    ap.add_argument("--embeddings", default=None, help="none | voyage-4-nano | voyage-api | hash (default: $EMBEDDINGS or none)")
    ap.add_argument("--fresh", action="store_true", help="also drop learned templates and interaction history")
    args = ap.parse_args()
    print(json.dumps(build(Path(args.store), args.embeddings, args.fresh), indent=2))


if __name__ == "__main__":
    main()
