# NorthWind PLUS on Quine — the simulation as a recipe

**The NorthWind PLUS business running on its own inside [Quine](https://hub.docker.com/r/thatdot/quine), thatDot's streaming graph, with no Python script. The outside world arrives as *ingest streams*. The company reacts with *standing queries*.**

This folder is the recipe version of the [full NorthWind PLUS model on Quine](../Readme.md). The batch script still builds the graph, but the simulation runs from one Quine recipe, `northwind-plus-simulation.yaml`. It holds:

- **Ingest streams** that act like the end-user applications issuing Cypher against the graph: a Sales Rep entering a customer order, the warehouse shipping it, the Procurement Assistant raising POs, suppliers sending RFQs, goods arriving at the dock.
- **Standing queries** that fire on state changes and run the company's own rules: PO vetting at three levels, Buyer submission, RFQ vetting, on-order bookkeeping, LowStock re-evaluation, Finance payment and closure.
- **The UI:** node styles, 47 sample queries (your reports, profit queries and data-quality checks) and 26 right-click quick queries, so you can inspect the model while it runs.

> Looking for the five-minute "business day" demo thatDot built? That's in the [`Quine/` folder](../../README.md). For the Python-driven version of this model (loops mode or Standing Query mode), see [`Full_NorthWindPLUS`](../Readme.md).

---

## Contents

- [How it works](#how-it-works)
- [Files](#files)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [The ingest streams — the outside world](#the-ingest-streams--the-outside-world)
- [The standing queries — the company's rules](#the-standing-queries--the-companys-rules)
- [Exploring while it runs](#exploring-while-it-runs)
- [Changing the pace](#changing-the-pace)
- [The batch in `--import-only` mode](#the-batch-in---import-only-mode)
- [Things you should know](#things-you-should-know)
- [Porting notes: the report queries](#porting-notes-the-report-queries)
- [How it was tested](#how-it-was-tested)
- [Troubleshooting](#troubleshooting)

---

## How it works

```
 ingest streams (one beat per second)          standing queries (fire on a pattern)
 ─────────────────────────────────────         ───────────────────────────────────────────
 customer-order ── new Order in OpeN ────────▶ nw-low-stock-on-new-order ─▶ LowStocK
 po-creation   ◀── products in LowStocK
       └────────── new PO in NewPoS ─────────▶ nw-po-vetting-l1 ─▶ l2 ─▶ l3
                                                  ├─ approved ─▶ nw-buyer-submission ─▶ SubmittedPoS
                                                  └─ rejected ─▶ nw-low-stock-after-reject ─▶ LowStocK
 rfq-submission / rfq-resubmission ── RFQ ───▶ nw-rfq-vetting ─▶ approved ─▶ nw-rfq-approved-on-order
 rfq-fulfillment ── WarehouseDelivery ───────▶ nw-finance-closure ─▶ ClosedPoS
 order-fulfillment ── Order shipped
 threshold-recalibration ── new thresholds, LowStocK re-evaluated
```

The model's principles carry over unchanged:

- **State = position.** Every state change is an edge moving between Collection nodes, so "a business event happened" and "a node moved into a Collection" are the same thing. That's exactly what a standing query watches.
- **Isotopes.** Mutable counts (`UnitsInStock`, `UnitsOnOrder`, `StockThreshold`) live on their own small nodes and change through Quine's atomic `int.add()`.
- **Never delete nodes.** Only membership edges move.
- **v2.4: no properties on edges.** Items, decisions, deliveries and payments are nodes.

---

## Files

| File | Description |
|---|---|
| `northwind-plus-simulation.yaml` | The Quine recipe: 7 ingest streams, 11 standing queries, node styles, 47 sample queries, 26 quick queries and a status query. |
| `northwind-plus-quine-batch.sh` | Builds the graph through Quine's REST API. Use it here with `--import-only`: import and setup only, then it switches the simulation on. |
| `Readme.md` | This file. |

---

## Prerequisites

- **Docker Desktop**, running ("Engine running"), with the `thatdot/quine` image. Developed and tested against **Quine 2.1.1**. Pin `thatdot/quine:2.1.1` if a newer image behaves differently.
- **WSL** (or any bash) with **curl** and **python3**, for the batch script.
- **Network access to GitHub** from the Quine container: the batch loads the CSV files straight from this repo's [`NorthWindPLUS/Import`](../../../Import) folder.

---

## Quick start

The order matters. **Start Quine with the recipe first, then load the data.** Quine runs a recipe on a throwaway store: the graph disappears when Quine stops, so every run starts from empty.

**1. Start Quine with the recipe** (window 1, from this folder). The streams start ticking but wait until the data is in.

From WSL:

```bash
docker run --rm --name northwind-quine -p 8080:8080 -v "$PWD":/demo thatdot/quine -r /demo/northwind-plus-simulation.yaml
```

From a Windows Command Prompt, use `%cd%` instead of `$PWD`. From PowerShell, use `${PWD}`:

```bat
docker run --rm --name northwind-quine -p 8080:8080 -v "%cd%":/demo thatdot/quine -r /demo/northwind-plus-simulation.yaml
```

Wait for `Quine web server available at http://127.0.0.1:8080`.

**2. Load the graph and switch the simulation on** (window 2, WSL, from this folder):

```bash
bash ./northwind-plus-quine-batch.sh --import-only
```

This takes about a minute. Its last step sets `Simulation.Ready = true`. Every stream checks that flag on every beat, so the simulation starts by itself.

**3. Watch the company act** (window 3):

```bash
docker logs -f northwind-quine 2>&1 | grep --line-buffered -o '"alert":"[^"]*"'
```

```
"alert":"[ORDER] CO-c3b9af12f4 (6 product(s)) -> LowStock + Grandma's Boysenberry Spread  "
"alert":"[PO CREATED] PO-ec1f06b548 to Exotic Liquids: Chang x240  "
"alert":"[L1 APPROVED] PO-ec1f06b548 $3192.0"
"alert":"[SUBMITTED] PO-ec1f06b548 sent to Exotic Liquids, awaiting its RFQ"
"alert":"[RFQ REJECTED] RFQ-08744e45c2 for PO-198800098a quoted $547.5 / budget $511.0 (over budget on Aniseed Syrup )"
"alert":"[RFQ APPROVED] ..."
"alert":"[ON ORDER] ..."
"alert":"[PO CLOSED] ..."
"alert":"[SHIPPED] 11008 to Ernst Handel (3 line(s))"
```

**4. Explore** at http://localhost:8080. Sample queries are in the drop-down of the query bar; quick queries are on right-click of a node.

Stop with Ctrl+C in window 1. To start over, repeat steps 1 and 2.

---

## The ingest streams — the outside world

Each stream is a Quine `NumberIterator`: one number per second (`maxPerSecond: 1`). The first line of each query, `WITH toInteger($that) AS n WHERE n % <seconds> = 0`, sets its beat. The second line is the gate: `MATCH (sim) WHERE id(sim) = idFrom("Simulation") AND sim.Ready = true`. Every stream runs one beat at a time (`parallelism: 1`) and has no limit: it runs until Quine stops.

| Stream | Every | What happens |
|---|---|---|
| `customer-order` | 10 s | A random customer orders 1–11 available products from a random Sales Representative. The `IS_OPEN_ORDER_STATE` edge is written **last**, so the LowStock rule sees the order with all its items. |
| `order-fulfillment` | 15 s | The oldest open order with stock for every line ships: `ShipInfo` and `WarehouseFulfillment` event nodes, stock down with `int.add()`, Open → Fulfilled. |
| `po-creation` | 30 s | The Procurement Assistant raises **one PO per supplier** for all its products in `LowStocK` that still meet the reorder rule. See [why this is a stream](#why-po-creation-is-a-stream-not-a-standing-query). |
| `rfq-submission` | 15 s | A supplier answers one PO the Buyer submitted with an RFQ for every line: usually at the negotiated 30% discount (×0.70), 15% of the time at ×0.75, which is **above the PO budget**, so RFQ vetting rejects it by rule. |
| `rfq-resubmission` | 20 s | A rejected RFQ is answered with a new one at ×0.65, linked by `HAS_PREVIOUS_RFQ`, with a `ResubmissionNote`. |
| `rfq-fulfillment` | 15 s | The goods of a submitted PO with an approved RFQ arrive: `WarehouseDelivery` event, stock up and units on order down (`int.add()`). |
| `threshold-recalibration` | 300 s | `StockThreshold` = 150% of the average monthly quantity ordered, then `LowStocK` is re-evaluated for every available product. This is the slow job. |

**The reorder rule** (used by `po-creation`, the LowStock re-evaluations and the checks):

```
UnitsInStock + qty on active, undelivered POs − qty on open customer orders − 0.5 × StockThreshold  ≤  StockThreshold
order qty = StockThreshold − effective available + 2 × StockThreshold      (at the 30% discount)
```

`po-creation` also:

- links a rejected, not yet re-ordered PO of the same supplier for the product as `HAS_PREVIOUS_PO` lineage, with a `ResubmissionNote`;
- leaves a product in `LowStocK` for a person to decide when its previous PO was rejected at **L3** (over every approval limit);
- drops `LowStocK` memberships that no longer meet the rule;
- writes the `IS_NEW_PO_STATE` edge **last**, after the items.

### Why PO creation is a stream, not a standing query

The rule is *one PO per supplier for all its low products*. It must run one at a time: when several products of the same supplier enter LowStock together (at startup and after every threshold recalibration), two parallel runs could order the same products twice. The API lets you set a standing query's output parallelism to 1 (`register-standing-queries.sh` does), but **a recipe can't**. Quine 2.1.1 rejects `parallelism` and `shouldRetry` in a recipe's standing-query outputs. So PO creation is a stream with `parallelism: 1`, ticking every 30 seconds, and the business rule stays as designed.

---

## The standing queries — the company's rules

| Standing query | Fires when | Does |
|---|---|---|
| `nw-po-vetting-l1` | a PO is in `NewPoS` | L1: reject by rule, approve within the L1 limit, or pass to L2 |
| `nw-po-vetting-l2` | a PO in `NewPoS` has an L1 approval | L2: reject by rule, approve within the L2 limit, or pass to L3 |
| `nw-po-vetting-l3` | a PO in `NewPoS` has an L2 approval | L3: reject by rule or over every limit, otherwise approve |
| `nw-low-stock-after-reject` | a PO enters `RejectedPoS` | its products go back to `LowStocK` if they still meet the reorder rule |
| `nw-buyer-submission` | a PO enters `ApprovedPoS` | the Buyer submits it to the supplier (the supplier's `SupplierNewPoS` edge is written last) |
| `nw-rfq-vetting` | an RFQ arrives for a submitted PO | approve if every line is within the PO budget, otherwise reject |
| `nw-rfq-approved-on-order` | a PO gets an approved RFQ | `UnitsOnOrder += RFQ quantities`, once (stamped with `rfq.OnOrderPosted`) |
| `nw-finance-closure` | a submitted PO gets a `WarehouseDelivery` | Finance pays (`FinancePayment`) and closes it, on the procurement and the supplier side |
| `nw-low-stock-on-new-order` | an order enters `OrderStatusOpeN` | re-evaluates `LowStocK` for the order's products (gated on `Simulation.Ready`, so the imported open orders are skipped) |
| `nw-log-po-created` | a PO enters `NewPoS` | read-only `[PO CREATED]` alert |
| `nw-log-shipped` | an order is fulfilled with a `WarehouseFulfillment` | read-only `[SHIPPED]` alert |

**Rejections follow rules, never chance.** The rules live in the data:

- A PO is rejected at any level if its supplier isn't in `ApprovedSupplierS`, or a product on it is no longer available.
- At L3, a PO is rejected if its cost exceeds `Level3Approver.ApprovalLimit`, because no one can approve it.
- An RFQ is rejected if any line costs more than the PO budgeted for it (qty × UnitPrice × POPriceDiscount), or the PO already has an approved RFQ.

**How the rules are kept safe without transactions:**

- A writer moves a node **into** its new Collection **last**, after its parts exist, and takes it **out** of its old Collection **first**. Otherwise, for an instant, the node would match the next level's pattern (e.g. "in NewPoS with an L1 approval") and that standing query would fire too.
- Every rule re-checks its condition right before it writes ("not already vetted", "no approved RFQ yet").
- Counters are stamped: `rfq.OnOrderPosted` marks an RFQ already put on order, so it's never counted twice.

---

## Exploring while it runs

### Sample queries (the query-bar drop-down)

47 queries, grouped by prefix:

| Prefix | What |
|---|---|
| `00a`–`00c` · **Gross profit** | last hour (shipped orders vs paid POs); all time, every PO raised vs every order placed; all time, paid POs vs fulfilled orders |
| `LIVE` | change while the simulation runs: members per state Collection, the Product Supply/Demand Dashboard (the Inventory Level Report), LowStock now, the reorder rule per product, POs per state, the PO vetting trail, supplier RFQ rejection rate, rejection value by level, approval workload, PO and RFQ resubmission lineage, blocked orders, waiting times, orders that can ship now, low inventory |
| `GRAPH` | draw on the canvas: the PO state machine, the full context of the newest PO (3 hops), nodes-to-edges ratio, supernodes |
| `SALES` | the NorthWind reports: order totals, top customers and employees, discounts, sales by region, territory, category and employee, product orders vs stock, products never ordered, top buyers per product, recommendations for ANTON (slow, about 20 s) |
| `CHECK` | the data-quality invariants; each shows `Violations: 0` when all is well |

The three **gross-profit** queries:

- **`00a` (last hour)** counts only orders shipped by the simulation: imported orders have no `WarehouseFulfillment` node, whatever the time window. On the supplier side it counts POs Finance paid in the window; a PO is paid in the same query that closes it. Change `"PT1H"` to set the window, e.g. `"PT10M"`.
- **`00b` and `00c` (all time)** include the imported Northwind order history on the sales side (about 830 orders). There are no imported POs, so their profit looks much higher than the last-hour version.
- Early in a run, gross profit is negative: POs restock to twice the threshold, so supplier spend runs ahead of sales.

### Quick queries (right-click a node)

| Node | Quick queries |
|---|---|
| any node | Adjacent nodes; its state (the Collections it's a member of) |
| a Collection (any node with a `Name`) | members; how many members |
| `Simulation` | the three gross-profit queries |
| `Product` | isotopes; the reorder rule right now (would it reorder? how much?); open orders waiting on it; its POs and their state |
| `PurchaseOrder` | the whole PO story (3 hops, orders left out); vetting trail; items and cost; lineage; its RFQs, quoted vs budget, and their fate |
| `RFQ` | lines: quoted vs PO budget |
| `Order` | lines, products, customer, sales rep, shipment; can it ship? |
| `Customer` | orders and their state; product recommendations |
| `Supplier` | its POs by state; RFQ reliability; products with their isotopes |
| `Employee` | everything this person decided, received, paid or shipped; role, approval limit and workload |

### Status query

The recipe's status query prints a one-row summary in Quine's log at startup, and the log shows it as a link you can open: simulation live or not, open orders, products in LowStock, and POs per state.

---

## Changing the pace

Edit the `n % <seconds>` on the first line of a stream's query: `n % 10` means every 10 seconds. Restart Quine and run the batch again for the change to take effect.

Quine's `-x key=value` recipe parameters can't do this: they don't fill numeric fields, and they don't substitute inside query text. So the paces live in the YAML.

The streams have no `limit`: they run until Quine stops. To run for a fixed time, stop the container when you're done (`docker stop northwind-quine`).

---

## The batch in `--import-only` mode

```bash
bash ./northwind-plus-quine-batch.sh --import-only [--quine URL]
```

It runs the import and setup sections of the batch: the CSV data, every Collection, the PLUS roles and staff, the supplier PO Collections. It skips the 50 demo orders and the workflow test pass. Then it:

1. evaluates `LowStocK` once for every product (about 2 products start in LowStock);
2. runs the data-quality invariants on the loaded graph;
3. **goes live:** creates the `Simulation` node with `Ready = true` and `LiveSince`. If an invariant fails, the simulation is **not** switched on.

**Safety guard:** the batch checks for `nw-*` standing queries. If they're running and you start it *without* `--import-only`, it refuses, because its workflow test pass would race them.

---

## Things you should know

- **Retries.** Quine warns that ingest queries may be retried after a timeout. The re-checks make a retried beat do nothing everywhere except `customer-order`, where a retry would add one extra order.
- **No PO rejections by rule appeared in the test runs.** The data never breaks the PO rules: `po-creation` only orders from approved suppliers and available products, and vetting happens within milliseconds, so nothing changes in between. All rejections seen came from overpriced RFQs, about 1 in 5 RFQs. Reorder quantities are small, so most POs are approved at L1; L2 and L3 approvals are rare.
- **Recipe limits (Quine 2.1.1).** A recipe's standing-query outputs accept only `name`, `filter`, `preEnrichmentTransformation`, `resultEnrichment {query, parameter}` and `destinations`. There's no `parallelism` and no `shouldRetry`, so each rule is written to be safe if it runs concurrently or is retried. PO creation, which can't be, is a stream.
- **Run one copy.** Quine has no transactions or locks. Each stream runs one beat at a time, and each rule re-checks before writing. Don't run the Python harness's loops against the same Quine at the same time. Its `--check-only` is fine: `python3 NorthwindPlus_Stress_Test_Quine.py --check-only` runs all the invariants in one go.
- **Quine 2.1.1 quirks found while porting:**
  - A pattern predicate such as `WHERE NOT (po)-[:X]->()` on a `WITH` that follows `ORDER BY`/`LIMIT` or an aggregation silently evaluates to false. Right after a `MATCH` it works, which is why the re-checks are written `MATCH (po) WHERE NOT …`.
  - `WHERE NOT n:Label` silently matches nothing; write `NOT "Label" IN labels(n)`. (`WHERE n:Label` works.) None of the rules use it.
  - `idFrom()` with any `null` argument returns `null`, so the import uses `coalesce()`.
  - `datetime()` from a string without a time zone fails; dates carry a `Z`.
  - Edges are a set: creating the same edge twice is a no-op.
- **Icons.** `ion-play` (Simulation), `ion-checkmark-circled` (VettingDecision) and `ion-refresh` (ResubmissionNote) are not confirmed to exist in the icon set Quine's UI uses. If they don't, those nodes show without an icon. The other icons are ones thatDot's own recipe uses.

---

## Porting notes: the report queries

The sample queries are the reports from the end of `NorthWind_PLUS_Graph_Data_Model_Import_v2.4 (Quine).cypher`, adapted to Quine. Each was run against a live simulation.

- `count{ pattern }` doesn't work in Quine → `size([pattern | x])`.
- `CALL (x) { … }` doesn't work → `CALL { WITH x … }`.
- Named variable-length paths (`chain = …*1..`) don't work → unnamed variable-length patterns.
- `duration_between(a, b)` → `duration.between(a, b)`.
- Date literals carry a time zone: `datetime("9999-12-31T00:00:00.000Z")`.
- Where it's easy, queries start from an `idFrom()` anchor (a Collection, `Order 10461`, `Customer ANTON`) instead of scanning a label. Plain label scans such as `MATCH (po:PurchaseOrder)` also work in Quine; they're full scans, fine at this graph size.
- Dates that lived on edges in v2.3 now come from event nodes: a PO's closing date is `FinancePayment.Date`, an order's fulfillment date is `WarehouseFulfillment.Date` (or `ShipInfo.ShippedDate`).
- **Blocked-orders reports** use `>=` (a line is blocked when quantity ≥ stock), to match the fulfillment rule, which ships only when stock is strictly greater than the quantity.
- **Left out:**
  - `CALL db.schema.visualization()` doesn't exist in Quine.
  - The duplicate-relationship check can never find anything, because Quine never keeps two copies of the same edge.

---

## How it was tested

On Quine 2.1.1 (the official jar, started with `-r northwind-plus-simulation.yaml`), in the same order as the Quick start. Not yet in Docker on Windows.

- Three runs of about 8, 5 and 25 minutes. In the 25-minute run: 148 customer orders, 98 shipments, 69 POs created and submitted, 65 RFQs approved, 17 rejected by rule over budget, 65 POs paid and closed, threshold recalibration every 5 minutes.
- All 9 `CHECK` queries returned 0 at the end of each run, and the Python harness's `--check-only` passed all 10 invariants.
- Every sample query and quick query runs without errors on Quine 2.1.1 (each quick query was tried on a real node of its label).

**A bug found and fixed during testing.** In the second run, 4 POs were created but never entered `NewPoS`, so they sat outside every state. `po-creation` removed each product from `LowStocK` with a plain `MATCH`. If a concurrent LowStock re-evaluation had removed that membership a moment earlier, the `MATCH` found no rows and the PO's `IS_NEW_PO_STATE` edge was never written. The step is now an `OPTIONAL MATCH` with a conditional delete, in the recipe and in `register-standing-queries.sh` (whose `nw-reorder-low-stock` had the same step). The 25-minute run after the fix, checked every 2 minutes, had no PO outside a state.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine` | Docker Desktop isn't running. Start it and wait for "Engine running". |
| `invalid mount path: './' mount path must be absolute` | The folder inside the container must be absolute: `-v "<this folder>":/demo` and `-r /demo/northwind-plus-simulation.yaml`. |
| The volume path shows a literal `$PWD` | `$PWD` only works in WSL/bash. Use `%cd%` in the Command Prompt and `${PWD}` in PowerShell. |
| `permission denied while trying to connect to the docker API` (WSL) | Your WSL user isn't in the `docker` group: `sudo usermod -aG docker $USER`, then `wsl --shutdown` and reopen WSL. |
| Batch: `NorthWind standing queries are running in this Quine` | You ran it without `--import-only` against the recipe. Add `--import-only`. |
| Batch: `the graph already has N nodes` | The recipe's store isn't empty (e.g. you ran the batch twice). Restart the container and run the batch once. |
| Nothing happens after the batch | Check that its last step printed `GO LIVE … ready=True`. If an invariant failed, the simulation was not switched on. |

---

For the model itself, the design principles and the other databases, see the [NorthWindPLUS README](../../../README.md) and the article [A Labeled Property Graph (LPG) Masterpiece](https://marcospinedo.substack.com/p/a-labeled-property-graph-lpg-masterpiece).
