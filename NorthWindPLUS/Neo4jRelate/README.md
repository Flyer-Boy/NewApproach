# NorthWind PLUS × Relate by Neo4j — an agent that learns its way around a live graph (POC)

An AI agent answers business questions about a **live** NorthWind PLUS simulation running on Neo4j Aura, makes one
governed change (the L1/L2/L3 PO approval bands, while the loops run), and **learns**: every question is kept as an
`Interaction`, and new queries the user approves become templates that later questions find.

- **Neo4j Aura** is the system of record: six Python loops write to it continuously.
- **Relate by Neo4j** (embedded, in-process) is the agent's own knowledge graph: the ontology, a library of Cypher
  templates linked to the concepts they touch, the question history, and what the agent has learned.
- **Claude** (Anthropic SDK) turns questions into template lookups or new Cypher and runs them on Aura.

## Status

| Stage | What | State |
|---|---|---|
| 1 | Model v2.3.2: ProcurementPolicyAdmin role, PolicyChange audit node, governed approval-band change, 2 query fixes | Applied to Aura |
| 2 | Knowledge loader + template search | Run live |
| 3 | Agent: search → read queries on Aura → governed band change with role check + confirmation | Run live (terminal, Colab) |
| 4 | Learning loop, provenance, Neo4j warnings to the model, search-first enforcement, embeddings + hybrid search | Tested offline; not yet run live |

## Layout

```
model/   NorthWind PLUS v2.3.2: import script, GRAPH TYPE, RDF/Turtle ontology, upgrade script, Python harness
kb/
  semantics.json   curated business meanings (from the import script's comments) -- edit to teach the agent
  build_kb.py      builds kb/northwind_kb.rl from model/ + semantics.json; keeps learned knowledge on rebuild
  kb_query.py      what the agent calls: hybrid template search, schema context, learning-loop writes
  kb_write.py      shared template-writing helpers (seed templates and learned ones get the same shape)
  embeddings.py    embedding providers: none | voyage-4-nano (local) | voyage-api | hash (tests)
  eval_search.py   retrieval check; --compare <provider> scores with vs. without embeddings
agent/
  agent.py         the agent (Anthropic SDK tool use)
  aura.py          Neo4j side: read transactions with warnings, identity lookup, governed write
  logs/            one JSON-lines file per session
tests/
  test_agent_offline.py     end-to-end: relate stands in for Aura, a scripted model stands in for Claude (27 checks)
  test_aura_driver_path.py  real aura.py against a stand-in enforcing the Neo4j driver's transaction rules (8 checks)
  toy_graph.py              tiny NorthWind PLUS graph used by both
tools/make_notebooks.py     generates both notebooks
NorthWind_PLUS_Agent.ipynb        local Jupyter front end
NorthWind_PLUS_Agent_Colab.ipynb  Google Colab front end (knowledge store kept on Google Drive)
```

## Run

**0. Load the model into Neo4j Aura** (Aura Query console):
1. `model/NorthWind_PLUS_Graph_Data_Model_Import_v2.3.2.cypher`, lines 95-1171. This wipes the database and builds
   NorthWind PLUS v2.3.2. Optional: the Recommendation Engine, lines 1271-1334.
   To keep an existing v2.3.1 database instead, run `model/NorthWind_PLUS_v2.3.2_Upgrade_from_v2.3.1.cypher`.
2. `model/NorthwindPlusGraphType_v2.3.2.cypher` (GRAPH TYPE schema).
3. Start the six loops: `model/NorthwindPlus_Stress_Test.py`, one process per `--loop`.

**Then, in Colab:** open `NorthWind_PLUS_Agent_Colab.ipynb`, add the Colab Secrets it lists, *Run all*, upload
`relate-agent.zip` when asked (or set `REPO_URL`).

**Or locally** (`.env` from `.env.example`, `pip install -r requirements.txt`):

```
python kb/build_kb.py                       # knowledge store; add --embeddings voyage-4-nano for semantic search
python agent/agent.py --as-employee 25      # Olivia Bennett, ProcurementPolicyAdmin: can change the bands
python agent/agent.py --as-employee 12      # Gloria Gaynor, Level1Approver: can ask, can't change the bands
python tests/test_agent_offline.py          # no API, no Aura
python tests/test_aura_driver_path.py
```

`--as-employee` stands in for a real login: the session, not the model, decides who the user is.
relate allows **one writing process per store**: don't run the terminal agent and a notebook on the same store at once.

## The knowledge graph in relate

```
(:NodeType {name, category: Entity|Collection, description})-[:HAS_PROPERTY]->(:Property {name, type, notNull, isKey})
(:NodeType)-[:SOURCE_OF]->(:RelType {name, pattern, description})-[:TARGETS]->(:NodeType)
(:WorkflowStep)-[:INVOLVES]->(:RelType)
(:QueryTemplate {title, description, cypher, governance, params, source, status, useCount, embedding?})
     -[:USES]->(:NodeType)  -[:TRAVERSES]->(:RelType)  -[:PART_OF {via: keyword|relationship}]->(:WorkflowStep)
(:Interaction {question, answer, employeeId, model, modelCalls, inputTokens, outputTokens, newQueries})
     -[:USED]->(:QueryTemplate)   -[:CREATED]->(:QueryTemplate)
(:ModelPrinciple {text}), (:KnowledgeBase {ontologyVersion, embeddingModel})
```

Seeded from model v2.3.2: 47 node types, 86 relationship types, 151 properties, 12 workflow steps, 72 templates
(51 read, 1 governed action, 1 admin-only write, 19 simulation actions from the loops).

Template governance: `read` (the agent may run it, in a read transaction) · `governed` (the band change: role checked
in the graph, user confirms, PolicyChange audit node) · `admin` (maintenance writes; never exposed) · `simulation`
(the loops' random actions; context only).

## The learning loop

1. Every question becomes an `Interaction`, linked to the templates it USED (and their `useCount` goes up).
2. When no template fits, the agent writes Cypher from the ontology. If it worked and is reusable, the agent calls
   `save_template`; **the user approves** (terminal / notebook prompt). Only a read query that already ran
   successfully for that question can be saved.
3. The new template is linked to the ontology concepts and workflow steps it touches, embedded (if embeddings are
   on), and tied to the Interaction that CREATED it. The next search finds it, directly and through the past question.
4. Rebuilding the store keeps learned templates and the history, re-linked to the current ontology. A learned
   template that names something the ontology no longer declares is kept as `needs-review` and hidden from search.

## Retrieval

Four ranked lists blended on normalized scores: full-text over templates (weight 1.0), vector search over template
embeddings (0.8, if built with embeddings), past questions → the templates that answered them (0.6), and the concept
graph (full-text over the ontology, then traversal to templates, scored by specificity; 0.35).

Baseline without embeddings on 12 business questions: expected template in the top 3 for **9/12**. The misses are
vocabulary gaps ("quotes" vs. "RFQ", "negative" vs. "below zero", "approve" vs. "approval"). To measure embeddings:
`python kb/eval_search.py --compare voyage-4-nano` (or the optional last section of either notebook).

Embeddings: `voyage-4-nano` is Voyage AI's open-weight model (Apache-2.0, ~346M parameters, ~700 MB download),
run locally through sentence-transformers with `trust_remote_code=True` (`pip install -r requirements-embeddings.txt`).
`voyage-api` uses the hosted API (`VOYAGE_API_KEY`). Anthropic doesn't offer an embedding model.

## Agent tools

| Tool | What it does | Guard rails |
|---|---|---|
| `search_templates` | Hybrid template search in relate (the model rewrites the question into ontology terms first) | — |
| `get_schema` | Exact properties and relationship patterns for given node types | — |
| `run_read_query` | Runs Cypher on Aura; returns rows and any Neo4j warnings | refused until a search ran for the question; write-keyword check; READ transaction; 20 s timeout; 500-row cap (50 to the model) |
| `save_template` | Saves a new query as a template | only a read query that ran successfully this question; user approval; one per question |
| `preview_approval_bands` | How proposed limits would route the POs awaiting vetting | read-only template |
| `change_approval_bands` | The governed band change | role from the session; user confirmation; the Cypher re-checks role and limits; PolicyChange audit node |

The full ontology (~17k characters) sits in the system prompt with prompt caching.

## Changelog

- **Stage 4 (2026-11-13):** learning loop (`save_template` with user approval; `Interaction` provenance; `useCount`;
  learned knowledge survives rebuilds, stale templates flagged `needs-review`); past questions as a retrieval path;
  optional embeddings (voyage-4-nano local / Voyage API) with a vector index in relate; Neo4j warnings returned to
  the model; `run_read_query` refused until `search_templates` ran (the model had skipped it); counts and totals must
  come from Cypher (after a 28-vs-29 summing slip); workflow tags from keywords *and* relationships; notebooks close
  a previous session before signing in (relate: one writing connection per store); Colab keeps the store on Drive.
- **Harness fix:** `po_resubmit` could create a PO line with 0 units when effective stock sat exactly on its
  eligibility boundary (`StockThreshold / 2` is integer division). A 0-cost PO matches no vetting action, not even
  `l1_reject`, so it stayed in NewPoS forever. Found by the agent on its first live run. `po_resubmit` and
  `po_creation` now drop non-positive lines and skip empty POs; `po_resubmit`'s eligibility applies the same rule.
- **Agent:** query timeout via `@unit_of_work` (managed transactions reject `Query` objects); sign-in errors reported
  instead of hidden; token usage summed over every model call per question.
- **requirements.txt:** `brotli>=1.2.0` (older releases, e.g. Anaconda's 1.1.0, break the Anthropic SDK's HTTP client).
