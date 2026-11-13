# NorthWind PLUS × Relate by Neo4j — agent knowledge store (POC)

An AI agent answers business questions about a **live** NorthWind PLUS simulation running on Neo4j Aura,
and can make a few governed changes to it (such as changing the L1/L2/L3 PO approval bands while the loops run).

- **Neo4j Aura** is the system of record: the six Python loops write to it continuously.
- **Relate by Neo4j** (embedded, in-process) is the agent's own knowledge store: the ontology, a library of
  proven Cypher templates linked to the ontology concepts they touch, and (later) what the agent learns.
- **Claude** (Anthropic SDK) turns questions into template lookups or new Cypher, and runs them on Aura.

## Status

| Stage | What | State |
|---|---|---|
| 1 | Model v2.3.2: ProcurementPolicyAdmin role, PolicyChange audit node, governed approval-band change, 2 query fixes | Done, applied to Aura |
| 2 | Knowledge loader + template search | Done, tested locally |
| 3 | Agent: search templates → read queries on Aura → governed band change with role check + confirmation | Written; tested offline (relate stand-in for Aura, scripted model). Not yet run against Aura + the API |
| 4 | Learning loop (approved new queries become templates) + embeddings + hybrid search | Later |

## Layout

```
model/   NorthWind PLUS v2.3.2: import script, GRAPH TYPE, RDF/Turtle ontology, upgrade script, Python harness
kb/
  semantics.json   curated business meanings (from the import script's comments) -- edit to teach the agent
  build_kb.py      builds kb/northwind_kb.rl from model/ + semantics.json
  kb_query.py      what the agent calls: template search, schema context
  eval_search.py   retrieval check: is the expected template in the top 3?
agent/
  agent.py         interactive agent (Anthropic SDK tool use)
  aura.py          Neo4j side: read-transaction queries, identity lookup, governed write
  logs/            one JSON-lines file per session (questions, tool calls, answers)
tests/
  test_agent_offline.py   end-to-end test with relate standing in for Aura and a scripted model
```

## Run

```
pip install -r requirements.txt
python kb/build_kb.py                 # rebuild the knowledge store (seconds)
cd kb
python kb_query.py search "which customer orders are blocked by missing stock?"
python kb_query.py schema PurchaseOrder RFQ
python eval_search.py
```

Run the agent (needs `.env`, see `.env.example`):

```
python agent/agent.py --as-employee 25    # Olivia Bennett, ProcurementPolicyAdmin: can change the bands
python agent/agent.py --as-employee 12    # Gloria Gaynor, Level1Approver: can ask, can't change the bands
python agent/agent.py --as-employee 25 --model claude-opus-5-5
python tests/test_agent_offline.py        # no API, no Aura
```

`--as-employee` stands in for a real login: the session, not the model, decides who the user is.

`build_kb.py` imports `model/NorthwindPlus_Stress_Test.py` to read the loops' Cypher (nothing runs; the neo4j
driver just has to be installed).

## What's in the knowledge store

```
(:NodeType {name, category: Entity|Collection, description})-[:HAS_PROPERTY]->(:Property {name, type, notNull, isKey})
(:NodeType)-[:SOURCE_OF]->(:RelType {name, pattern, description})-[:TARGETS]->(:NodeType)
(:WorkflowStep)-[:INVOLVES]->(:RelType)
(:QueryTemplate {title, description, cypher, kind, governance, params, status, ontologyVersion})
     -[:USES]->(:NodeType)  -[:TRAVERSES]->(:RelType)  -[:PART_OF]->(:WorkflowStep)
(:ModelPrinciple {text})
```

Built from model v2.3.2: 47 node types, 86 relationship types, 151 properties, 12 workflow steps,
72 templates (51 read, 1 governed action, 1 admin-only write, 19 simulation actions from the loops).

Template governance:
- `read` — the agent may run these (in a read transaction).
- `governed` — the approval-band change: requester's ProcurementPolicyAdmin role is checked in the graph,
  the user confirms after a preview, every change is a PolicyChange node.
- `admin` — maintenance writes (the restock "cheat"); never exposed to the agent.
- `simulation` — the loops' random actions; stored for context, not exposed as agent tools.

## Retrieval (no embeddings yet)

Full-text (BM25) over template titles/descriptions, blended with a graph path: full-text over the ontology,
then traversal from the matching concepts to the templates that use them (scored by specificity).
Baseline on 12 business questions: expected template in the top 3 for 8. All 4 misses are vocabulary gaps
("negative" vs "below zero", "quotes" vs "RFQ"); the same questions rewritten into ontology terms hit #1 —
which is what the agent will do before searching, and what embeddings will add.

## Agent tools

| Tool | What it does | Guard rails |
|---|---|---|
| `search_templates` | Template search in relate (the model rewrites the question into ontology terms first) | read-only store |
| `get_schema` | Exact properties and relationship patterns for given node types | — |
| `run_read_query` | Runs Cypher on Aura | write-keyword check, READ transaction, 20 s timeout, 500-row cap (50 sent to the model) |
| `preview_approval_bands` | How proposed limits would route the POs awaiting vetting | read-only template |
| `change_approval_bands` | The governed band change | role checked from the session; terminal confirmation; the Cypher re-checks role and limits; PolicyChange audit node |

The full ontology (~17k characters) sits in the system prompt with prompt caching, so it's paid for once per
session rather than every turn.
