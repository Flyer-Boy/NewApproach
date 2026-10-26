# NorthWindPLUS on Quine — the LPG masterpiece, running

A streaming take on Marcos Pinedo's *"A Labeled Property Graph (LPG) Masterpiece"*.
The article builds Northwind as a graph where **identity is the node, state is
position, mutable numbers are isotopes, and nothing is ever deleted**, then drives
a full business cycle through it with Python loops against Neo4j Aura and queries
the result.

This recipe keeps all four rules and changes one thing: the business cycle is a
**live stream** (one tick per second, 300 ticks = one business day) and the
queries are **standing queries** — they don't wait to be asked, they fire the
instant a pattern appears, and four of them **perform the next business step**
themselves, in the graph. The article's question was *"can a graph model a whole
business?"* This demo's question is *"can the graph run one?"*

Audience: Marcos. Runtime: Quine 2.1.0.

## Run it

With Docker (written for Windows + WSL + Docker Desktop):

```bash
./run-demo-docker.sh            # one business day (~5 min), then the graph sits still to explore
./run-demo-docker.sh --loop     # a fresh day every ~5½ minutes, forever (Ctrl-C to stop)
```

With Java and the Quine jar (set `QUINE_JAR`, or put a `quine*.jar` in this folder):

```bash
./run-demo.sh            # one business day (~5 min), then the graph sits still to explore
./run-demo.sh --loop     # a fresh day every ~5½ minutes, forever (Ctrl-C to stop)
./run-demo.sh --port 8081
```

Then open **http://localhost:8080**. The terminal shows every standing-query
fire as it happens; the end-of-day tally prints when the streams finish.

The graph lives in memory for the life of the JVM, so a day is reset by
restarting Quine — nothing is ever deleted from a running graph (rule 4 holds
inside every day). Run artefacts (`quine.log`, `shipped-orders.jsonl`) land in
`.run/` and are wiped at the start of each day.

## The five-minute day — what to watch for

| Tick (≈ s) | What the business does | What the twin does, unasked |
|---|---|---|
| 0 | Seed: 12 products (20 in stock, threshold 12), 8 customers, 9 employees with roles, 5 suppliers, **3 offers per product**, 14 state Collections | six standing queries are already armed |
| 3 → 239 | Sales: one customer order every 2 s, two lines each | |
| 9 → | Fulfillment: ships what is in stock, 6 s after the order | `[SHIPPED]` · accrues the customer's spend isotope |
| ~20 | First product drops below threshold → enters **LowStock** | `[LOW STOCK]` · reads the 3 supplier offers + scorecards, writes a **PurchaseRecommendation** → `[RECOMMEND]` |
| +2 | Procurement executes the recommendation: PO from *that* supplier at *that* qty → **NewPoS**; product also enters **Reordering** | |
| +10 | L1 vetting against the **ApprovalLimit on the role node**: ≤100 → ApprovedPoS; >100 → **RejectedPoS** | `[AUTO-RESUBMIT]` · creates `PO-nn-R` with `HAS_PREVIOUS_PO` lineage, routes it to L2, lands it in ApprovedPoS |
| +20 | Buyer submits; supplier answers with an RFQ at its *current* offer price → **SubmittedPoS** | |
| +30 | Goods received; stock up, on-order down → **ClosedPoS**; product leaves Reordering **and LowStock** | `[PO CLOSED]` · books an **Invoice** into PayablesDue, bumps the supplier scorecard · `[RESTOCKED]` (the low-stock query's *cancellation*) |
| any | An order that can't ship enters **BackOrders**; it leaves when it ships | `[BACKORDER]` … `[RELEASED]` (a condition and its end) |
| mid-day | A customer's shipped spend crosses $3,000 | the shipped-order automation moves them into **PreferredCustomers** → which fires `[TIER]` — a standing query triggered by another standing query's write |
| 240–299 | Sales stop; open orders drain, last POs close | |
| 300 | Every stream completes. Standalone: graph sits still. `--loop`: tally, 20 s, fresh day | |

Products 4, 8 and 12 are "bulk-pack" SKUs — every supplier sells them in lots
of 150, which is what puts a PO over the L1 limit and triggers the rejection
path. That is a rule in the data (a `MinOrderQty` on the offer, an
`ApprovalLimit` on the role), not a coin flip in the simulator.

## Follow along in the UI

**Sample queries** (drop-down on the search bar) are numbered in story order:

1. **START HERE** — the 14 state Collections. This is the business's state machine, drawn.
2. Where is everything right now — members per Collection. Run it twice a minute apart.
3. **Inventory dashboard, live** — the article's report, except the numbers change while you watch.
4. The supplier market — 3 offers per product, re-pricing every tick.
5. What the twin recommended, and whether procurement acted on it.
6. A recommendation on the canvas — product, the three offers, the chosen supplier, the PO it became.
7. Purchase orders by state.
8. **Rejected → resubmitted → closed** — the lineage the graph kept (rule 4), with the L1 rejecter and L2 approver.
9. Back orders right now, and what they are waiting on.
10. Payables the twin booked.
11. Supplier scorecard — what automation 1 reads when it chooses.
12. Customer 360 — spend today, orders shipped, tier.
13. The whole life of one order (graph).
14. Who did what on a closed PO.
15. Live graph around NewPoS.

**Graph feeds** (Exploration UI → the feed chips): six are armed by the
launcher, one per standing query. Toggle one on and the canvas draws each match
as it fires — the shape that *matched*, anchored on the id the standing query
returned. `LOW STOCK` and `BACK ORDER` redraw on the cancellation too.
`ORDER SHIPPED` is busy (~120/day); toggle it for a minute, then off.

**Quick queries** (right-click any node): every label has the pivots a person
following the story would ask — *Which Collection is this in?* on anything;
*The 3 supplier offers, right now* and *What the twin recommended* on a Product;
*PO lineage* and *Who touched this PO* on a PurchaseOrder; *Can it ship?* on an
Order; *Customer 360* on a Customer; *What we owe this supplier* on a Supplier.

## The four automations, in graph terms

Each is a standing query whose enrichment **writes to the graph**, and that
write is what the next business process consumes. No code outside the recipe.

| Fires on | Reads | Writes | Then |
|---|---|---|---|
| Product enters `LowStock` | the product's 3 `SupplierOffer` isotopes (cost, availability, min lot, updated every tick by the catalog feed) + each supplier's `SupplierScore` | a `PurchaseRecommendation` in `RecommendedPurchases`, linked to product, chosen supplier and the offer it was based on | the procurement stream raises the PO from it |
| PO enters `RejectedPoS` (pattern includes `REJECTED_L1_BY`) | the PO's line, product, supplier, buyer; the L1 and L2 role limits | `PO-nn-R` with `HAS_PREVIOUS_PO` → original, `VETTED_L2_BY`, placed in `ApprovedPoS` | submit/receive streams pick up "the latest PO in the lineage" |
| PO enters `ClosedPoS` (pattern includes `HAS_WAREHOUSE_DELIVERY`) | the approved RFQ line (qty × unit cost), the supplier | an `Invoice` in `PayablesDue`; atomic increments on the supplier scorecard | automation 1 uses the scorecard as a tiebreaker: what the twin learns changes what it buys |
| Order enters `ShippedOrders` (pattern includes `SHIPPED_VIA`) | order lines | atomic add to `CustomerSpend`; if the yielded total ≥ $3,000, `PreferredCustomers CONTAINS customer` | which fires standing query 5, `[TIER]` |

Two more watch a **condition and its end** (`includeCancellations: true`):
LowStock (`[LOW STOCK]` / `[RESTOCKED]`) and BackOrders (`[BACKORDER]` /
`[RELEASED]`). For that to mean "restocked", LowStock had to become the
real-world condition — a product now stays in it until the goods arrive — while
Reordering is the separate process state. Both are "state = position".

## Why this is a streaming-graph argument, not a Neo4j-vs-Quine one

- **The query is armed before the data.** Nothing here polls. The recommendation
  exists milliseconds after the stock drops, because the pattern was already
  watching the LowStock collection.
- **The whole shape is in the pattern.** Where an automation needs more than the
  anchor node (the rejecter, the delivery, the carrier), that edge is in the
  standing-query pattern, so it fires only once the whole shape exists — never
  against a half-written one.
- **State = position pays off twice.** The article uses it to avoid status
  properties. Here it also makes every business event a *membership change*,
  which is exactly what a standing query watches best.
- **Isotopes pay off twice too.** Mutable counts on their own nodes are what let
  the concurrent streams and enrichments update stock, spend and scorecards with
  atomic adds (`int.add` / `float.add`) instead of read-modify-write races.
- **Rule 4 is what makes the lineage query trivial.** The rejected PO is still
  there, still in RejectedPoS, with the resubmission pointing at it.

## Files

| File | What |
|---|---|
| `northwind-plus-streaming.yaml` | the recipe: 2 seed streams, 8 business streams, 6 standing queries, UI config |
| `run-demo.sh` | launcher with the Quine jar (standalone / `--loop`); arms the feeds through Quine's tap-query API |
| `run-demo-docker.sh` | the same launcher, starting Quine in Docker |
| `feeds.json` | the 6 graph feeds |
| `DEMO_PLAN.md` | the plan this was built from, with the decisions and the evidence for them |
| `tap-queries-api (3).md` | reference for the tap-query API |

## Verification

See the **Verification** section at the bottom of `DEMO_PLAN.md` for the measured
runs (per-day tallies, invariants checked against the graph after each day, and
the loop test).

## Known limits, said plainly

- The day is deterministic in the tick number; concurrent streams can still
  reorder within a tick, so per-day tallies vary by a few in the families that
  depend on timing (back orders, episodes). The invariants don't.
- A recommendation raised after ~tick 268 cannot close inside the same day; its
  PO ends the day in SubmittedPoS. The tally says so.
- `toString()` on money prints `1170.0`, not `1,170.00`.
- Quine open source has no per-node TTL; the day-restart is the bound on graph
  size. Left running for 64 hours without one, the earlier version reached
  232k ticks and a 1.5 GB log.


[Curtesy of the Thatdot/Quine team. Thanks Adam and Ryan for reaching out and showing me some new perspectives using streaming.]
