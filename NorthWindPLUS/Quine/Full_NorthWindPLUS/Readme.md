# NorthWind PLUS on Quine — the full model

**The complete NorthWind PLUS graph, loaded into [Quine](https://hub.docker.com/r/thatdot/quine), thatDot's streaming graph,, with the company's own business rules running as Standing Queries.**

This folder holds the *full* NorthWind PLUS implementation for Quine: the same 360-degree procurement and order-fulfillment cycle as the [Neo4j, Memgraph and FalkorDB versions](../../README.md), and the same simulation loops. On top of that, Quine can run half of the business itself. In **Standing Query mode**, reordering on low stock, the three levels of PO vetting, buyer submission, RFQ vetting and finance closure all happen inside the graph, the moment the matching pattern appears, with no polling. Python only plays the *outside world*: customers, suppliers and deliveries.

> **Want it without Python?** The [`Recipe_Version`](Recipe_Version/Readme.md) subfolder runs this same model as a single Quine recipe. Ingest streams play the outside world, and standing queries run the company's rules, so nothing outside Quine drives the simulation.
>
> Looking for the self-contained five-minute "business day" demo? That's in the [parent `Quine/` folder](../README.md). This folder is the full model and its Python stress harness.

---

## Contents

- [What's different on Quine](#whats-different-on-quine)
- [Files](#files)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Step 1 — Load the graph](#step-1--load-the-graph)
- [Step 2 — Choose a mode](#step-2--choose-a-mode)
- [Step 3 — Run the simulation](#step-3--run-the-simulation)
- [Optional — the recommendation layer](#optional--the-recommendation-layer)
- [Quine-specific notes](#quine-specific-notes)

---

## What's different on Quine

**Model v2.4: no properties on edges.** Quine doesn't support properties on relationships, so every edge that carried data in v2.3.1 becomes a small node. The principle *state = position* is unchanged.

| In v2.3.1 (Neo4j) | In v2.4 (Quine) |
|---|---|
| `(Order)-[:HAS_ORDER_PRODUCT {Quantity, UnitPrice, Discount}]->(Product)` | `(Order)-[:HAS_ORDER_ITEM]->(:OrderItem {…})-[:ORDER_ITEM_PRODUCT]->(Product)`, and the same for `POItem` and `RFQItem` |
| an approval or rejection edge with `{Date, Comment}` | `(PO)-[:HAS_L1_PO_APPROVAL]->(:VettingDecision {Date, Comment})-[:VETTED_BY]->(Employee)` |
| a delivery, payment or fulfillment edge with `{Date, Comment}` | a `WarehouseDelivery`, `FinancePayment` or `WarehouseFulfillment` event node |
| role and employment start dates on edges | `RoleAssignment` and `EmploymentRecord` event nodes |

**Identity through `idFrom()`.** Every proper-noun node and every singleton Collection has a deterministic id, for example `idFrom("Product", "11")` or `idFrom("NewPoS")`. Queries start from those anchors instead of scanning labels.

**Atomic counters.** The *isotopes* `UnitsInStock` and `UnitsOnOrder` change only through Quine's atomic `int.add()`, so concurrent loops can't lose each other's updates.

**LowStock is a Collection.** Products at their reorder point are members of the `LowStocK` Collection. Membership is re-evaluated after every step that changes stock, POs in flight or open-order demand, and PO creation works from it. This is the hook the reorder Standing Query watches.

---

## Files

| File | Description |
|---|---|
| `northwind-plus-quine-batch.sh` | Builds the whole graph through Quine's REST API. It imports the data, creates every Collection, role and employee, runs one pass of every workflow step, and finishes with data-quality invariants. |
| `register-standing-queries.sh` | Registers, lists or removes the nine `nw-*` Standing Queries that run the company's own rules inside Quine. |
| `NorthwindPlus_Stress_Test_Quine.py` | The simulation harness: Standing Query mode, or the original six loops. |
| `northwind-plus-quine-recommendations.sh` | Optional collaborative-filtering layer (ratings and customer similarity). |
| `NorthWind_PLUS_Graph_Data_Model_Import_v2.4 (Quine).cypher` | The v2.4 model as a commented Cypher script. **It still targets Neo4j** (it uses `LOAD CSV`, APOC and `CALL` subqueries). It's the reference for the edge-property-free model, not the Quine loader — use the `.sh` scripts for Quine. |
| `Recipe_Version/` | The same model run as a Quine recipe (ingest streams + standing queries, no Python). Its batch loader adds `--import-only`, and its `register-standing-queries.sh` includes a fix for the PO-creation step. See its own [Readme](Recipe_Version/Readme.md). |

---

## Prerequisites

- **Quine**, running *without* a recipe and reachable over HTTP (default `http://localhost:8080`). The scripts were developed and tested against **Quine 2.1.1**.
- **bash**, **curl** and **python3**. On Windows, run everything from **WSL**.
- **Network access to GitHub.** The batch loader reads the cleaned CSV files straight from this repo's [`NorthWindPLUS/Import`](../../Import) folder.

The Python harness uses only the standard library, so there's no `pip install`.

---

## Quick start

```bash
# 1. Start Quine (here with Docker)
docker run -d --name quine -p 8080:8080 thatdot/quine

# 2. Load the graph
./northwind-plus-quine-batch.sh --reset

# 3. Let the graph run the company's own rules (optional, but the interesting part)
./register-standing-queries.sh

# 4. Simulate the outside world; run the invariants when you stop it (Ctrl+C)
python3 NorthwindPlus_Stress_Test_Quine.py --check
```

Then open http://localhost:8080 and explore the graph as it changes.

> `thatdot/quine` without a tag pulls the latest image. If you run into differences, pin the version the scripts were tested on (2.1.1).

---

## Step 1 — Load the graph

```bash
./northwind-plus-quine-batch.sh [--reset] [--from N] [--quine URL]
```

| Option | Meaning |
|---|---|
| `--reset` | Delete everything in the graph first. Without it, the script refuses to run on a non-empty graph. |
| `--from N` | Resume at step N; earlier steps are skipped. Useful after fixing a failed step. |
| `--quine URL` | Quine base URL (default `http://localhost:8080`). |

The loader runs about 60 numbered steps in sections, printing checkpoints along the way:

1. **Import:** the original Northwind data, normalized. This covers categories, suppliers, products and their isotopes, customers, roles, employees, territories, shippers, orders and order items. Every product is then restocked with 150 units before the simulation.
2. **PLUS:** the employee directory, procurement roles with approval limits, supplier states, and the procurement, warehouse and finance staff.
3. **One pass of every workflow:** customer orders, PO creation from `LowStocK`, L1/L2/L3 vetting (with demo rejections and one resubmission that keeps its lineage), buyer submission, supplier RFQs, RFQ vetting and resubmission, the stock-threshold update, warehouse receiving, finance closure and order fulfillment.
4. **Invariants.** The script **fails** if any of these is broken: no negative stock or units on order; every PO in exactly one procurement state; no order both open and fulfilled; no PO paid before delivery, or delivered or paid twice; `UnitsOnOrder` matching approved, undelivered RFQs; and `LowStocK` membership matching the reorder rule for every product.

---

## Step 2 — Choose a mode

The harness works in two modes:

| Mode | Python runs (the outside world) | Quine runs (the company) |
|---|---|---|
| **`sq`** — Standing Queries | `customer-order`, `order-fulfillment`, `rfq-submission` (suppliers), `rfq-fulfillment` (goods arrive), and a slow `threshold-recalibration` job | reordering, PO vetting, buyer submission, RFQ vetting, on-order updates and finance closure — as Standing Queries |
| **`loops`** — the original design | the original six loops: `customer-order`, `po-creation`, `po-vetting`, `rfq-vetting`, `warehouse-finance`, `order-fulfillment` | nothing extra |

The default is `--mode auto`, which picks `sq` if the `nw-*` Standing Queries are registered and `loops` otherwise.

### The Standing Queries

```bash
./register-standing-queries.sh            # (re)register all, then backfill them over existing data
./register-standing-queries.sh --status   # list the NorthWind standing queries
./register-standing-queries.sh --remove   # delete them all (back to the loops-only setup)
```

| Standing Query | Fires when | Does |
|---|---|---|
| `nw-reorder-low-stock` | a product is in `LowStocK` and its supplier is approved | creates one PO per supplier for its low products |
| `nw-po-vetting-l1` | a PO is in `NewPoS` | L1: reject by rule, approve within the limit, or pass to L2 |
| `nw-po-vetting-l2` | a PO in `NewPoS` has an L1 approval | L2: reject by rule, approve within the limit, or pass to L3 |
| `nw-po-vetting-l3` | a PO in `NewPoS` has an L2 approval | L3: reject by rule or over the limit, otherwise approve |
| `nw-low-stock-after-reject` | a PO enters `RejectedPoS` | re-evaluates `LowStocK` for its products |
| `nw-buyer-submission` | a PO enters `ApprovedPoS` | the buyer submits it to the supplier |
| `nw-rfq-vetting` | an RFQ arrives for a submitted PO | approves it if it's within the PO budget, otherwise rejects it |
| `nw-rfq-approved-on-order` | a PO gets an approved RFQ | adds the RFQ quantities to `UnitsOnOrder` (atomically) |
| `nw-finance-closure` | a submitted PO gets a `WarehouseDelivery` | finance pays and closes it |

**Rejections follow rules, never chance.** The rules live in the data:

- A PO is rejected at any level if its supplier isn't in `ApprovedSupplierS`, or a product on it is no longer available.
- At L3, a PO is rejected if its cost exceeds `Level3Approver.ApprovalLimit`, because no one can approve it.
- An RFQ is rejected if any line costs more than the PO budgeted for it, or the PO already has an approved RFQ.

To watch the graph act as it happens (with Docker, using your container's name):

```bash
docker logs -f quine 2>&1 | grep -o '"alert":"[^"]*"'
```

---

## Step 3 — Run the simulation

Run every loop of the mode in one process, with a labelled, combined log (Ctrl+C stops them all):

```bash
python3 NorthwindPlus_Stress_Test_Quine.py --check
python3 NorthwindPlus_Stress_Test_Quine.py --rates customer-order=12,rfq-submission=8 --check
```

Or run a single loop on its own, exactly like the Neo4j harness:

```bash
python3 NorthwindPlus_Stress_Test_Quine.py --loop customer-order --rate 6
```

| Option | Meaning |
|---|---|
| `--mode M` | `sq`, `loops` or `auto` (default) |
| `--loop NAME` | run only this loop (default: every loop of the mode) |
| `--rate N` | executions per minute for `--loop` (default 6) |
| `--rates a=N,b=N` | per-loop rates; `0` disables a loop |
| `--overprice F` | `sq` mode: share of RFQs quoted above budget, which the RFQ Standing Query then rejects by rule (default 0.15) |
| `--duration S` | stop after S seconds |
| `--check` | run the data-quality invariants when the loops stop |
| `--check-only` | just run the invariants and exit |
| `--quine URL` | Quine base URL (default `$QUINE_URL` or `http://localhost:8080`) |

**Default rates** (executions per minute):

| Loop | `loops` mode | `sq` mode |
|---|---|---|
| `customer-order` | 6 | 6 |
| `order-fulfillment` | 4 | 4 |
| `po-creation` | 2 | — (Standing Query) |
| `po-vetting` | 4 | — (Standing Queries) |
| `rfq-vetting` | 4 | — (Standing Query) |
| `warehouse-finance` | 4 | — |
| `rfq-submission` | — | 4 |
| `rfq-fulfillment` | — | 4 |
| `threshold-recalibration` | — | 0.2 (every 5 minutes) |

As in the other harnesses, there are no thresholds or approval limits in the Python code. They live on the `RolE` nodes, and the Collections *are* the state machine. Each action is a name, a weight and two Cypher strings: an eligibility pattern and an execute query. That is exactly the shape a Standing Query takes, which is what made moving them into Quine straightforward.

---

## Optional — the recommendation layer

```bash
./northwind-plus-quine-recommendations.sh [--quine URL]
```

Run it on demand, after the batch loader. It builds:

```
(Customer)-[:HAS_RATING]->(:Rating {Rating})-[:RATING_FOR_PRODUCT]->(Product)
(Customer)-[:HAS_SIMILARITY]->(:Similarity {Similarity})<-[:HAS_SIMILARITY]-(Customer)
```

It's safe to re-run: `Rating` and `Similarity` nodes have deterministic ids, so a second run updates the scores instead of duplicating them.

---

## Quine-specific notes

- **No transactions and no `apoc.lock`.** Every write re-checks its own "not yet done" guard right before writing. Each loop runs on a single thread, and the loops work on different stages of the pipeline. **Run only one copy of each loop.** Two copies of the same loop could both pick the same PO or order, which the Neo4j harness prevents with locks.
- **No `randomUUID()`.** Generated numbers (`CO-`, `PO-`, `RFQ-`, `SH-`) use the new node's own id, `strId(n)`.
- **Address nodes are identified by their value**, so a shipment to a customer's address links to the same `Address` node.
- **A Quine 2.1.1 quirk found while porting:** a pattern predicate such as `WHERE NOT (po)-[:X]->()` on a `WITH` that follows `ORDER BY`/`LIMIT` or an aggregation silently evaluates to false. The same predicate directly after a `MATCH` works. That's why the guards re-bind the node they already hold (`MATCH (po) WHERE NOT …`). Keep this in mind if you write your own Standing Queries.
- **How the Standing Queries are written to be safe:**
  - Writers move a node *into* its new Collection last and take it *out of* its old one first, so a half-written state never triggers the next level.
  - Outputs are never retried, so writes can't be duplicated.
  - Counters are stamped, so the backfill never counts an RFQ twice.

  The header of `register-standing-queries.sh` lists all the rules.

For the model itself, the design principles and the other databases, see the [NorthWindPLUS README](../../README.md) and the article [A Labeled Property Graph (LPG) Masterpiece](https://marcospinedo.substack.com/p/a-labeled-property-graph-lpg-masterpiece).
