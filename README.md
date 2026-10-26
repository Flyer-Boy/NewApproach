# A New Approach to Application Development using Graphs

**Don't put Graphs around your applications. Build the applications around the Graph.**

This repository contains the scripts, data and prototype code behind my articles on building **Line-of-Business applications natively on a Labeled Property Graph** — where the graph is not only the data layer, but also the place where business state, rules and workflow live.

It holds four proofs of concept, from a Ride-Hailing app to a full 360-degree procurement and order-fulfillment system that runs six business processes concurrently against the same live graph — now on **Neo4j, Memgraph, FalkorDB and Quine**. On Quine, that business even runs itself: a single recipe streams in customers, suppliers and deliveries, and standing queries apply the company's rules inside the graph, with no application code.

---

## Contents

- [Why Graph-Native?](#why-graph-native)
- [The key principles](#the-key-principles)
- [What's in this repository](#whats-in-this-repository)
- [Graph database support](#graph-database-support)
- [Getting started](#getting-started)
- [Folder guide](#folder-guide)
- [Articles and talks](#articles-and-talks)
- [Contact](#contact)

---

## Why Graph-Native?

After decades of working with RDBMS/SQL and enterprise software development, I have spent more than eight years exploring new ways to build Line-of-Business applications on Graph Databases, far beyond their conventional use cases.

The journey began in 2013, after 17 years at Microsoft, where I worked in its Consulting division and later led Developer and Platform Evangelism across Brazil and Asia Pacific. I invested in and joined a startup to build what I believed could become a revolutionary Graph-Native Platform, and it is there that many of the concepts, principles and methodologies in this repository were born. The startup did not survive — we were too ambitious and, arguably, ahead of our time in a very conservative market. But I believe those ideas are even more relevant today, as we enter the AI era.

Graphs are not merely specialized tools for Data Science, Knowledge Graphs or Graph RAG. I believe they can be the ideal foundation for almost any business application:

- **Data should be created in the Graph**, not created in tables and imported into a graph later. When the graph is the native substrate, relationships, semantics, ontology and context exist from the moment the first business object is created.
- **Most of today's business problems are networks and workflows**, not tables. Roughly speaking, most business apps are workflows — and a workflow is a graph.
- **Graph-Native systems are Agentic AI-ready.** The context, semantics, ontology and history an AI agent needs to reason are already in the same graph the application reads and writes every day — no ETL pipelines, no repeated ingestion from disconnected tables.

This has evolved far beyond a side project. It is a life mission — one I will pursue for as long as it takes.

---

## The key principles

Every model in this repository follows the same small set of rules. They are explained in depth in [the concept article](https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3), and every Cypher script repeats them in its header.

| Principle | What it means |
|---|---|
| **Proper Noun Nodes** | A node stores only the properties that define the uniqueness of the entity it represents. Any state, or an entity's contextual relevance to another entity, is a relationship — never a property. Nothing is hidden inside properties: you (and AI) can understand the whole model at any moment without reading them. |
| **Never Delete Nodes** | Nodes are never deleted, so every entity stays traceable over time. Time flows in one direction; entities are archived and timestamped, not erased. |
| **Read-Only Nodes** | Once created, node properties don't change. `SET` is reserved for corrections and a few exceptions — the *isotopes*, such as inventory counts, which are isolated in their own small nodes. This greatly simplifies concurrency and consistency. |
| **Relationships Drive the System** | The system works by creating nodes and creating/deleting their relationships as the workflow moves on. A business event is a node moving from one Collection to another. *State = position.* There are 118 stable chemical elements that build everything we know just by changing their relationships — this is biomimicry applied to software architecture. |
| **Lean Nodes** | Outgoing relationships are minimized. One-to-many connections go through **Collection** (hub) nodes that represent domain states and contexts, using explicit set semantics (Superset, Subset, Element of) instead of relational algebra's implicit joins — which matches how domain experts naturally think. |

> If you find yourself filtering on a node property that represents state or context, that's a sign the model needs a relationship instead — it was most likely built with a table mentality.

I'm aware that current graph databases are not fully optimized for this approach yet. I witnessed and worked with the first RDBMS and saw how they evolved over the decades; graph databases will too.

---

## What's in this repository

| Proof of concept | What it demonstrates | Highlights |
|---|---|---|
| [**RideHailing**](RideHailing) | The core concepts in a familiar domain: passengers, drivers, cars and bookings moving between states | Full **React + TypeScript** prototype app running directly on the graph |
| [**TenderWorkflow**](TenderWorkflow) | A tendering system with intertwined workflows — vendor, tender and bid vetting with multi-level approvals — where the graph is both the data and the logic layer | Full ontology, Neo4j **GRAPH TYPE** schema, RDF/Turtle ontology, Python random test generator |
| [**NorthWind**](NorthWind) | The classic Northwind database, remodeled with a Graph mentality | Cleaned CSV import files |
| [**NorthWindPLUS**](NorthWindPLUS) | Northwind extended into a full 360-degree business cycle: customer orders, low-stock detection, POs with 3-level vetting, supplier RFQs, warehouse, finance and order fulfillment | Six concurrent Python simulation loops stress-testing the graph; ported to 4 graph databases; on Quine, the business rules run as Standing Queries — and a **recipe version** runs the whole simulation inside the graph — see the [NorthWindPLUS README](NorthWindPLUS/README.md) |

The Cypher scripts are heavily commented and explain what each block does and why, so they work well as a learning resource for applying the principles above.

---

## Graph database support

I started with Neo4j and keep testing the models on other graph databases. When a model works on another engine, I publish the adapted scripts here.

| | Neo4j | Memgraph | FalkorDB | Quine |
|---|:---:|:---:|:---:|:---:|
| RideHailing | ✅ | ✅ | | |
| TenderWorkflow | ✅ (v7.1, GRAPH TYPE) | ✅ (v7.1) | 🧪 beta (v7.1) | |
| NorthWind | ✅ | | | |
| NorthWindPLUS | ✅ (v2.3.1, GRAPH TYPE) | ✅ | ✅ | ✅ (v2.4, Standing Queries + recipe) |

Quine doesn't support properties on relationships, so the Quine version uses **model v2.4**, in which every edge that carried data becomes a small node. The principles are unchanged.

With the standardization of **GQL** (ISO/IEC 39075:2024) and the wide adoption of **openCypher**, Cypher-based scripts are increasingly portable across graph databases — but each engine has its own nuances. The ported scripts document the changes each engine required in their headers.

---

## Getting started

The easiest way in is **Neo4j**:

1. Get a free database at [Neo4j Aura](https://neo4j.com/cloud/aura-free/), or use Neo4j Desktop.
2. New to Cypher? Start at [Neo4j GraphAcademy](https://graphacademy.neo4j.com/).
3. Pick a proof of concept, open its main `.cypher` script, and follow the instructions in its header.

> ⚠️ Most scripts begin with `MATCH (n) DETACH DELETE n` to clear the database. Run them on an empty or disposable database.

The GRAPH TYPE schema scripts (`TenderGraphType v1.cypher`, `NorthwindPlusGraphType_v1.cypher`) use Neo4j's GRAPH TYPE schema enforcement, introduced as a preview in Neo4j 2026.02 / Cypher 25. Check that your Neo4j version supports it before running them.

The Python simulators need Python 3 and the driver for your database (for example `pip install neo4j`). Connection settings are passed as environment variables, described at the top of each script.

---

## Folder guide

### `/RideHailing`

| File | Description |
|---|---|
| `RideHailing.cypher` | Creates the initial nodes (Passengers, Drivers, Cars, Bookings) in different states so you can explore the model. Can be run in full. |
| `RideHaining-MemGraph.cypher` | The same script adapted for Memgraph. |
| `neo4j-RideHailingDB.backup` | A Neo4j backup with the initial nodes and some bookings already made — an alternative to running the script. |
| `RideHailing_Queries.cypher` | Example queries to run against the model. |
| `RideHailing_Templates.cypher` | Cypher commands used to build the mockup application shown in the article. Replace the variables with real values before running. |
| `The RideHailingGraphModel.png` | The Ride-Hailing graph model. |
| `RideHailingGraphApp/` | The React + TypeScript (Vite) prototype application that runs on the model. |

### `/TenderWorkflow`

| File | Description |
|---|---|
| `TenderWorkflow v7.1.cypher` | **Current version.** The Tendering System simulation with full ontology implementation (Neo4j). |
| `TenderGraphType v1.cypher` | Companion GRAPH TYPE schema for v7.1, enforcing the ontology at the database level. |
| `TenderGraph RDF-turtle v1.ttl` | The same ontology expressed in RDF/OWL (Turtle). |
| `TenderWorkflow v7.1 MemGraph.cypher` | v7.1 adapted for Memgraph. |
| `TenderWorkflow v7.1 FalkorDB (beta).cypher` | v7.1 adapted for FalkorDB — beta. |
| `Tender_Workflow_Random_Test_Generator.py` | Parameterized Python generator that randomly creates Tenders, vets them, invites vendors, accepts and vets Bids, and awards (or not) the Tenders, strictly following the workflow rules. Approval thresholds are read from the graph, not hardcoded. |
| `Tender_Workflow_Random_Test_Generator_MemGraph.py` | The generator adapted for Memgraph. |
| `* ScriptOutputFile.txt` | Sample generator runs on Neo4j Aura (with GRAPH TYPE), Neo4j Desktop and Memgraph in Docker. |
| `Tender Model v7.1 visualisation.png` / `.svg` | The v7.1 graph model. |
| `TenderWorkflow v5.cypher`, `v6.cypher`, `v6 - MemGraph.cypher`, `v6 Graph Model.png` | Earlier versions, kept for reference (v6 uses the generic `[:HAS]` relationship with a `RelType` property). |

### `/NorthWind`

| File | Description |
|---|---|
| `NorthWind v2.1.cypher` | The Northwind model adapted to the key principles, with ontology-specific relationship types (v2 dropped the generic `[:HAS]`). |
| `NorthWind.cypher`, `NorthWind v2.cypher` | Earlier versions. |
| `NorthWind Schema Only.cypher` | The schema only, no data (created with the Arrows app). |
| `NorthWindPlus  v1.cypher`, `NorthWind_PLUS_Graph_Data_Model_Import_v2.1.cypher` | Early iterations of NorthWind PLUS, kept for history. The current version lives in `/NorthWindPLUS`. |
| `Northwind.png` | The Northwind graph model. |
| `Import/` | **Cleaned CSV files.** The original files in [neo4j-graph-examples/northwind](https://github.com/neo4j-graph-examples/northwind) contain unescaped commas in some fields (mainly addresses in Brazil, France and Belgium, and some notes), which shifts columns on import. I reported this in issue #53 of that repository. |

### `/NorthWindPLUS`

The most complete proof of concept: Northwind turned into a full business cycle, plus Python harnesses that run six independent business processes concurrently against the same graph to test whether it holds the load. It includes ports to Memgraph, FalkorDB and Quine, a GRAPH TYPE schema, an RDF ontology, and notes on an Agentic AI layer.

➡️ **See the [NorthWindPLUS README](NorthWindPLUS/README.md)** for the full guide and quick starts for each database.

The Quine work comes in three flavours, each with its own README:

| Folder | What it is | Who drives the business |
|---|---|---|
| [`NorthWindPLUS/Quine/Full_NorthWindPLUS/Recipe_Version`](NorthWindPLUS/Quine/Full_NorthWindPLUS/Recipe_Version/Readme.md) | **The full model as a single Quine recipe.** Ingest streams play the outside world (customers, suppliers, the warehouse dock). Standing queries run the company's rules (PO vetting, buyer submission, RFQ vetting, finance closure). It ships with 47 sample queries and 26 right-click quick queries. | Quine alone — no Python |
| [`NorthWindPLUS/Quine/Full_NorthWindPLUS`](NorthWindPLUS/Quine/Full_NorthWindPLUS/Readme.md) | The full model loaded over Quine's REST API, driven by the Python harness: either the original six loops, or the outside world in Python with the rules as Standing Queries | Python, with or without Standing Queries |
| [`NorthWindPLUS/Quine`](NorthWindPLUS/Quine/README.md) | A self-contained, five-minute "business day" streaming demo built by thatDot from the model | Quine alone |

---

## Articles and talks

1. **The Concept** — [A new approach to application development using Cypher/GQL (Graphs)](https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3)
2. **The Ride-Hailing POC** — [Ride-Hailing Graph App Prototype Explainer](https://medium.com/@marcospinedo/ride-hailing-graph-app-prototype-explainer-071a89543a90)
3. **Workflows on Graphs** — [How Graphs simplify Business Processes and Workflows](https://medium.com/@marcospinedo/how-graphs-simplify-business-processes-and-workflows-like-moving-balls-between-baskets-c9606c9e973f)
4. **The "why"** — [Biomimicry in Software: Designing Business Systems using Graphs Like Nature Does](https://medium.com/@marcospinedo/biomimicry-in-software-designing-business-systems-using-graphs-like-nature-does-4c107dd2596e)
5. **The Tender Workflow** — [A Graph-Native Workflow Application using Neo4j/Cypher](https://medium.com/@marcospinedo/a-graph-native-workflow-application-using-neo4j-graph-a4406e51b4e5)
6. **NODES 2025 talk** — [video presentation of the concepts + POC demo](https://youtu.be/ExupBmmH1Rs), and the companion article with slides and extended transcript: [Rethinking Line of Business Applications: Graphs & Cypher as an Alternative to RDBMS & SQL](https://medium.com/@marcospinedo/rethinking-line-of-business-applications-graphs-cypher-as-an-alternative-to-rdbms-sql-fd1d204f99b7)
7. **Ontology and schema enforcement** — [Graph-Native Business Applications with a Full Ontology — a practical use case of Neo4j's new GRAPH TYPE Schema enforcement](https://medium.com/@marcospinedo/graph-native-business-applications-with-a-full-ontology-a-practical-use-case-of-neo4js-new-graph-216c9bf20d22)
8. **NorthWind PLUS** — [A Labeled Property Graph (LPG) Masterpiece](https://marcospinedo.substack.com/p/a-labeled-property-graph-lpg-masterpiece) — the ultimate test: six independent business processes running concurrently against the same live graph, putting all the concepts into practice.

I will keep adding content and prototypes as this New Approach evolves.

---

## Contact

If you want to discuss, learn more, or try this approach on your next project, you can reach out to me at marcos.pinedo@outlook.com or [LinkedIn](https://www.linkedin.com/in/marcospinedo/)

If you liked what you just saw, I suggest you read some of my previous articles (on [Medium](https://medium.com/@marcospinedo), [Substack](https://substack.com/@marcospinedo), or [LinkedIn](https://www.linkedin.com/in/marcospinedo/)) on related subjects if you haven’t already.


**"Alea iacta est" — crossing the Rubicon of Graph adoption!** 🚀

Enjoy!

---

<sub>*If you're curious about the name "Flyer-Boy": that is a long, long story. It now happens to be my Xbox gamertag "Flyerboy", Instagram name, Discord tag and so on — it now follows me everywhere, so bear with it. Sorry!*</sub>
