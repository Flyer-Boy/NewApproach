# NorthWind PLUS on Ultipa GQLDB — an ISO GQL port

**The full NorthWind PLUS model (v2.3.1) and its six concurrent simulation loops, rewritten in ISO GQL for [Ultipa GQLDB](https://www.ultipa.com/docs/gql) ("Ultipa Graph v6").**

This is the same model, the same nodes, relationships and properties, and the same 360-degree business cycle as the [Neo4j version](../README.md): customer orders, low-stock detection, POs with three levels of vetting, supplier RFQs, warehouse receiving, finance closure and order fulfillment. What changes is the language. Every Cypher statement is translated to **GQL** (ISO/IEC 39075), and the Neo4j driver and APOC locks are replaced by Ultipa's Python driver and its write-conflict detection.

It is a useful test of the portability claim behind the [New Approach](../../README.md). Because the business logic lives in the graph, not in application code, moving the whole application to another engine means translating queries, not redesigning the system.

---

## Contents

- [Files](#files)
- [Prerequisites](#prerequisites)
- [Connection settings](#connection-settings)
- [Step 1 — Build the graph](#step-1--build-the-graph)
- [Step 2 — Run the simulation loops](#step-2--run-the-simulation-loops)
- [Step 3 — Watch and check](#step-3--watch-and-check)
- [How the port differs from Neo4j](#how-the-port-differs-from-neo4j)
- [GQLDB behaviours found while porting](#gqldb-behaviours-found-while-porting)

---

## Files

| File | Description |
|---|---|
| `NorthWind_PLUS_Graph_Data_Model_Import_v2.3.1_Ultipa_GQL.gql` | The full model in GQL: import, one pass of every workflow step, live views, the recommendation engine, and query examples with data-quality checks. Its header has a Cypher → GQL conversion table. |
| `run_gql_script.py` | Runs a section of the `.gql` file against GQLDB, one statement at a time, with progress, timing and resume. |
| `NorthwindPlus_Stress_Test_Ultipa.py` | The concurrency harness: the same six loops as the Neo4j version. |
| `PySetup_Ultipa.bat` | Windows launcher: opens eight loop windows (two loops run twice, for contention). |

---

## Prerequisites

- An **Ultipa GQLDB** instance and a user with permission to create a graph.
- **Python 3** and Ultipa's Python driver:

  ```bash
  pip install --upgrade ultipa      # 6.x; it is imported as "gqldb"
  ```

- Network access to GitHub. The script loads the cleaned CSV files straight from this repo's [`NorthWindPLUS/Import`](../Import) folder.

Keep `run_gql_script.py` in the same folder as `NorthwindPlus_Stress_Test_Ultipa.py`, because it imports its connection code from there.

---

## Connection settings

Both Python scripts read the same environment variables:

```bash
export ULTIPA_HOSTS="localhost:9000"      # comma-separated host:port list
export ULTIPA_USER="root"
export ULTIPA_PASSWORD="<password>"
export ULTIPA_GRAPH="NorthWindPLUS"
export ULTIPA_TIMEOUT="60"                 # optional: per-query deadline, in seconds
export ULTIPA_TLS="1"                      # optional: only if your instance requires TLS
```

| Variable | Default | Notes |
|---|---|---|
| `ULTIPA_HOSTS` | `localhost:9000` | |
| `ULTIPA_USER` | `root` | |
| `ULTIPA_PASSWORD` | — | Required. |
| `ULTIPA_GRAPH` | `NorthWindPLUS` | The loops must use the graph the script loaded. |
| `ULTIPA_TIMEOUT` | `60` for the harness; `600` for `run_gql_script.py` | The driver's own default is 30 seconds. |
| `ULTIPA_TLS` | off | `1` opens an encrypted connection. A plain-text instance on port 443 rejects TLS, so leave it off unless yours requires it. |

> A cloud gateway in front of the instance may cut any request off at about 60 seconds (HTTP 504), whatever `ULTIPA_TIMEOUT` says. The script was written to stay under that limit; see [the order-details batches](#gqldb-behaviours-found-while-porting).

---

## Step 1 — Build the graph

```bash
python run_gql_script.py NorthWind_PLUS_Graph_Data_Model_Import_v2.3.1_Ultipa_GQL.gql --section setup
```

This first runs `CREATE GRAPH IF NOT EXISTS <ULTIPA_GRAPH>`, creating an open (schema-free) graph, which behaves like Neo4j. It then runs the setup section. ⚠️ Setup starts with `MATCH (n) DETACH DELETE n`, so use an empty or disposable graph.

The `.gql` file is divided into sections, marked with `//@@ BEGIN …` / `//@@ END …`:

| `--section` | What it runs |
|---|---|
| `setup` (default) | Import, normalization, every Collection, role and employee, and one pass of every workflow step |
| `live_views` | "What happened today" views of orders and POs, to run while the loops are going |
| `recommendation` | Optional recommendation engine: customer ratings and cosine similarity |
| `examples` | Query examples, the Inventory Level Report, and data-quality checks after the simulation |
| `all` | The whole file |

| Option | Meaning |
|---|---|
| `--dry-run` | Print the statements without connecting |
| `--keep-going` | Continue after a failed statement |
| `--from N` / `--to N` | Run only statements N through M (1-based). On a failure, the runner tells you which `--from` to resume with. |
| `--timeout S` | Per-statement deadline in seconds |
| `--show-rows N` | Rows to print for statements that return data (default 5) |

You can also paste the statements into Ultipa Manager or the CLI one at a time. Run `CREATE GRAPH IF NOT EXISTS NorthWindPLUS` and `USE NorthWindPLUS` first.

After the import, check that no staging rows are left:

```gql
MATCH (r:StgOrderDetail) RETURN count(r);
```

It must return 0. If it doesn't, run the order-details batch statement again.

---

## Step 2 — Run the simulation loops

```bash
python NorthwindPlus_Stress_Test_Ultipa.py --loop customer-order    --rate 6
python NorthwindPlus_Stress_Test_Ultipa.py --loop po-creation       --rate 2
python NorthwindPlus_Stress_Test_Ultipa.py --loop po-vetting        --rate 4
python NorthwindPlus_Stress_Test_Ultipa.py --loop rfq-vetting       --rate 4
python NorthwindPlus_Stress_Test_Ultipa.py --loop warehouse-finance --rate 4
python NorthwindPlus_Stress_Test_Ultipa.py --loop order-fulfillment --rate 4
```

Run each loop in its own terminal, so they behave like independent actors working on the same graph. The loops are the same as in the [Neo4j harness](../README.md#the-simulation-loops).

| Option | Meaning |
|---|---|
| `--loop NAME` | Which loop to run (required) |
| `--rate N` | Executions per minute (default 6) |
| `--duration S` | Stop after S seconds (default: run until Ctrl+C) |
| `--print-queries` | Print every GQL statement the loop can send, then exit without connecting. Paste them into Ultipa Manager to debug one statement at a time. |

Ctrl+C stops a loop cleanly and prints a summary: executions, retries, errors, no-ops and the achieved rate.

**On Windows:** fill in `ULTIPA_HOSTS`, `ULTIPA_USER` and `ULTIPA_PASSWORD` at the top of `PySetup_Ultipa.bat` (and `ULTIPA_GRAPH`, `ULTIPA_TIMEOUT` and `ULTIPA_TLS` if needed), then run it from this folder. It checks that the driver is installed, then opens eight windows, each waiting for Enter. PO vetting and order fulfillment run twice each, so their **retries** count shows the conflict handling at work. Don't commit the file with your password filled in.

---

## Step 3 — Watch and check

While the loops run, use the `live_views` section to see the orders and POs created, approved, submitted and closed today. When you stop the loops, run the data-quality checks at the end of the `examples` section to confirm that nothing slipped through: no negative stock, no PO in two states, no order both open and fulfilled, and so on.

```bash
python run_gql_script.py NorthWind_PLUS_Graph_Data_Model_Import_v2.3.1_Ultipa_GQL.gql --section examples --keep-going
```

---

## How the port differs from Neo4j

**The language.** The main translations, all listed in the `.gql` header:

| Cypher | GQL in this port |
|---|---|
| `CREATE` | `INSERT` |
| `WITH …` | `RETURN … NEXT` (aggregation), `LET` (new variable), `FILTER` (condition on a computed value) |
| `UNWIND list AS x` | `FOR x IN list` |
| `NOT (a)-[:R]->()` | `NOT EXISTS { MATCH (a)-[:R]->() }` |
| `count{ pattern }` | `VALUE { MATCH pattern RETURN count(*) }` |
| `datetime()` | `local_datetime()`, used everywhere, so every stored date has one type |
| `randomUUID()` | No UUID function: IDs are built from the node's auto-generated `_id` right after `INSERT` |
| `-[:R*1..]->` | `-[:R]->{1,}` |
| `"a" + "b"` | `"a" \|\| "b"` |
| `LOAD CSV … MERGE` | `LOAD CSV … INTO <StagingLabel> MAPPING (…)`, then a normal `MATCH`/`INSERT` transforms the staging nodes |

**Concurrency — the big one.** In Neo4j, each guarded action picks a candidate, locks it with `apoc.lock.nodes`, and re-checks its guard under the lock. GQLDB has no APOC and no explicit lock statement. Instead, it uses snapshot isolation with conflict detection at commit: when two transactions modify the same node, the second to commit is refused with **error 3011** (write conflict). The harness therefore runs each unit of work in an explicit transaction. On a conflict it rolls back and retries on a fresh snapshot, with exponential backoff and up to 5 retries. On the retry, the guard (e.g. "not yet vetted") fails, and the action becomes a harmless "lost the race" no-op.

Ultipa's documentation describes the conflict rule for a node that both transactions *modify*. Many of these actions only add or delete edges around the chosen PO, RFQ or order, and it isn't documented whether edge changes count as modifying their endpoints. So every action that used `apoc.lock.nodes` also increments an `OCCVersion` counter on the node it used to lock, which guarantees the conflict. This is the one deliberate departure from the *Read-Only Nodes* principle in this port. If Ultipa confirms that edge inserts and deletes conflict on their endpoints, set `OCC_TOUCH = False` at the top of the harness, and no extra property is written.

**No schema enforcement.** The graph is open (schema-free). The Neo4j GRAPH TYPE schema has no equivalent in this port.

---

## GQLDB behaviours found while porting

These came up while testing against a live GQLDB instance. Each is worked around in the scripts, and they're worth knowing if you write your own GQL for Ultipa.

- **Anonymous elements in `INSERT` can store null.** An `INSERT` that copies a value from another variable into an *anonymous* node or edge, such as `(:InventoryLevel {UnitsInStock: r.UnitsInStock})`, stored null. The same `INSERT` with named elements stored the value. The `.gql` file names every such element (`ins_n1`, `ins_e1`, …), and the harness renames them automatically before sending a query.
- **`LOAD CSV` writes into one label and allows no expressions.** Anything computed during the load is loaded into a staging label (`Stg…`) first, then transformed. The staging nodes are deleted at the end.
- **Convert numbers in `LOAD CSV`, not afterwards.** `to_integer()`/`to_float()` on a `LOAD CSV` value returned null, so numeric columns are converted with `MAPPING … AS INT` / `AS FLOAT`. The one exception is `Discontinued`, which stays text and is converted in the filters, because that was the combination that correctly linked the 69 available products.
- **The ~60-second gateway limit.** In one statement, linking the 2,155 order-detail rows took about 58 seconds, right at the limit. It's done in batches of 250 instead. Each batch deletes the staging rows it used, so re-running it can never create a line twice.
- **`/` always returns a float.** Integer division is written `to_integer(floor(a / b))`.
- **Edges are always directed.** Cypher's undirected `MERGE (c1)-[:SIMILARITY]-(c2)` becomes one edge per pair of customers, written from the lower `CustomerID` to the higher one, and the recommendation queries read it in either direction.

Both files document these in their headers and comments, next to the statements they affect.

For the model itself and the design principles, see the [NorthWindPLUS README](../README.md) and the article [A Labeled Property Graph (LPG) Masterpiece](https://marcospinedo.substack.com/p/a-labeled-property-graph-lpg-masterpiece).
