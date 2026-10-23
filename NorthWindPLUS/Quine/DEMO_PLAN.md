# NorthWindPLUS as a looping digital-twin demo — plan

Status: **BUILT 2026-09-14 on Option A** (restart-per-day; see §2). The recipe is
now the v2-format `northwind-plus-streaming.yaml` (original archived in `_archive/`),
plus `run-demo.sh`, `feeds.json` and `README.md`. Decisions taken during the build
that differ from the plan below: opening stock 20 / threshold 12 (not 40 / 25) so
the reorder window actually bites and back orders occur; Preferred tier at $3,000;
fulfillment retries at +6/+20/+40/+60; supplier selection also honours a
`MinOrderQty` on the offer (bulk-pack SKUs 4, 8, 12 → the deterministic rejection
path). Measured results are in the **Verification** section at the end.

Goal: a 5-minute "business day" that replays forever, where an observer arriving at
any moment sees the graph (a) notice a real business change, (b) act on it, and
(c) notice when the condition is no longer true. Extends Marcos's four rules with
a fifth claim: the twin doesn't just mirror the business, it *runs* parts of it.

---

## 0. Evidence from the first run (2026-09-11 → 09-14, Quine 2.1.0)

Left running unattended for 64 h at 1 tick/s:

| Measure | Value |
|---|---|
| Ticks per stream | 232,000 |
| Shipped orders | ~116,000 (jsonl 15 MB) |
| Standing-query fires | 12,384 low-stock / 2,582 rejected / 2,582 lineage / 116,095 shipped |
| stdout log | 1.5 GB (status spinner + PrintToStandardOut) |
| JVM RSS | 1.0 GB |
| `MATCH (c:Collection)-[:CONTAINS]->(x) RETURN c.name, count(x)` | no answer in 10 s |

Conclusion: the graph and the log both need a bound. The bound comes from the
loop design (§2), not from a TTL — Quine open source has no per-node TTL, and the
Enterprise `default-ttl` is a Cassandra storage setting, not a business rule.

Also observed: the "left LowStock" branch of the low-stock alert never printed
(12,384 fires, all "entered"). Two reasons: `includeCancellations` is off, and
even with it on, the product leaves LowStock when *procurement picks it up*
(tick+2), not when it is restocked. §3 fixes the semantics, not just the flag.

---

## 1. The 5-minute day

- 1 tick = 1 s. **300 ticks = one business day = one loop.**
- Every stream computes `day = n / 300`, `t = n % 300`. Ids carry the day:
  `idFrom("order", day, t)`. Reference data (products, suppliers, customers,
  employees, roles, collections) is seeded once and never carries a day — the
  business persists, the transactions flow through it.
- The schedule is tuned so every process finishes inside the day:

| t | What happens |
|---|---|
| 0 | Day opens. Stock is at 40/product, threshold 25. |
| 1–239 | Sales: one order every 2 ticks (120 orders/day). |
| ~15 | First product drops below threshold → `[LOW STOCK]` → **A1 recommendation** (§4). |
| +2 | Procurement raises a PO from the recommendation. |
| +10 | L1 vetting. Over-limit POs rejected → `[PO REJECTED]` → **A2 auto-resubmit**. |
| +20 | Buyer submits to supplier, RFQ approved, UnitsOnOrder up. |
| +30 | Goods received, stock up, PO closed → `[PO CLOSED]` → **A3 invoice + scorecard**; product leaves LowStock → `[RESTOCKED]` (cancellation). |
| every ship | `[SHIPPED]` → **A4 customer spend + tier**; a customer crossing the tier → `[TIER]`. |
| any | Order that can't ship enters BackOrders → `[BACKORDER]`; ships later → `[RELEASED]` (cancellation). |
| 240–290 | Sales stop; open orders drain, last POs close (~t=280). |
| 295 | **Close of day**: transactional nodes archived (§2), isotopes reset, day counter rolls. |

The whole PO loop (create → reject → resubmit → submit → receive → close) is
visible inside ~90 s, so a viewer never waits more than a couple of minutes to
see every beat.

---

## 2. The loop — two options, one recommendation

**Option B (recommended): one Quine process, in-graph day cycle.**
Ingest streams run unbounded (no `ingestLimit`). A close-of-day step at t=295
`DETACH DELETE`s the day's transactional nodes (orders, lines, POs, PO lines,
RFQs, deliveries, recommendations, invoices — all addressable because ids are
`idFrom(kind, day, k)`, so it is `UNWIND range(0,299)` over ~10 id families),
resets the three isotopes per product (40 / 25 / 0), clears LowStock, Reordering,
BackOrders, RecommendedPurchases, PayablesDue, PreferredCustomers memberships.
Reference nodes are never touched. The graph holds at most one day's
transactions (~120 orders, ~240 lines, ~25 POs, …: a few thousand nodes) and
the web page's connection to Quine never drops.

- Precedent: `euc-estate-optimization/recipe.yaml:263` uses `DETACH DELETE` on
  nodes on 2.1.0. (Not on paths — that is the documented limitation.)
- Rule-4 tension ("never delete nodes"): honoured *inside* every process; the
  one exception is the day boundary, and the day's ledger is already written to
  the JSONL outputs before the archive runs. Say this out loud in the README —
  it is how real ops systems separate the hot store from the archive.

**Option A (fallback): restart every 5 minutes.**
`ingestLimit: 300` on every stream, a 10-line shell loop that kills Quine, wipes
`quine.db`, restarts. Simplest possible; byte-identical replay each loop. Cost:
~15 s of JVM startup per loop where the UI and API are down, and every viewer
reconnects. Use only if B's cycle math proves fiddly in session 1.

Decide before building: the id scheme (`day` in every `idFrom`) is the one thing
that is expensive to retrofit.

---

## 3. "No longer true" — cancellations that mean something

Turn on `includeCancellations: true` **only** on the two state queries where an
end-of-episode is a business event. The output's enrichment already branches on
`$that.meta.isPositiveMatch` (verified: cancellations do arrive with
`isPositiveMatch:false`; they are only distinguishable if the enrichment labels
them).

1. **LowStock — fix the semantics first.** Today procurement moves the product
   LowStock → Reordering, so "left LowStock" means "PO raised", not "restocked".
   Change: a product **stays in LowStock until UnitsInStock ≥ threshold**;
   Reordering becomes a second, independent membership (process state vs real-
   world state — both are "state = position", both are honest). Receiving (stream
   5) removes both. Then the cancellation reads `[RESTOCKED] Chai back to 95
   (threshold 25)`.
2. **BackOrders (new).** Fulfillment already knows when an order can't ship; it
   currently does nothing. Move it into a `BackOrders` collection (rule 2). The
   SQ fires `[BACKORDER] CO-17 waiting on Chai (needs 6, 3 in stock)`; when the
   order ships the edge is removed and the cancellation fires `[RELEASED] CO-17
   shipped after restock`. This is the clearest "condition resolved" beat in the
   whole demo and needs no cross-node comparison in the SQ pattern (Quine SQ
   patterns can't compare properties across nodes — the ingest does the
   arithmetic, the collection records the verdict).

Engine fact to design around (measured on 2.1.0, `cnapp-race-verification`):
`DistinctId` fires once per continuous match episode. Product goes low → fire;
restocked → cancellation; goes low again later the same day → fires again.
That is exactly the behaviour we want.

---

## 4. Four automations — one per existing standing query

Mechanism in every case: the standing query's `CypherQuery` output **writes to
the graph**, and that write is what the next business process consumes. No
external code. (Same pattern Agent Authority's `exfil-gate` uses to write
`status = "blocked"`.)

### A1. Low stock → purchase recommendation with supplier selection
- **New data:** every product gets **3** suppliers via `:SupplierOffer` isotope
  nodes keyed `idFrom("offer", productIdx, supplierIdx)` with `UnitCost`,
  `LeadTimeDays`, `UnitsAvailable`. A new **supplier catalog feed** ingest
  updates offers every tick with deterministic drift (cost ±10 %, availability
  rises/falls) — the "outside world streaming into the twin" beat.
- **Action:** on `[LOW STOCK]`, read the 3 offers + each supplier's scorecard
  (A3), pick lowest cost with `UnitsAvailable ≥ qty`, write a
  `:PurchaseRecommendation` (qty, chosen supplier, the two alternatives with
  their prices) into `RecommendedPurchases`, linked to product and supplier.
- **Procurement changes:** stream 2 no longer scans LowStock; it consumes
  `RecommendedPurchases` and raises the PO from the *recommended* supplier at
  the recommended qty, then removes the recommendation's CONTAINS edge.
- **Prints:** `[RECOMMEND] Chai ×75 from Exotic Liquids @ $10.80 (Tokyo Traders
  $11.40 · Las Cabras 4 units short)`.

### A2. PO rejected → auto-resubmission with escalation
- **Rule-driven rejection** replaces "every 5th tick": the L1 `RolE` node gets
  `ApprovalLimit` (e.g. 100 units). Every 5th recommendation is a "rush" at 2×
  qty (150) → over limit → L1 rejects. Deterministic, but the *reason* lives in
  the graph.
- **Action:** the SQ output (not ingest 3b) creates `PO-nn-R` with
  `HAS_PREVIOUS_PO` lineage, routes it to L2 (whose limit is higher), lands it
  in ApprovedPoS. Ingest 3b only rejects.
- **Prints:** `[AUTO-RESUBMIT] PO-50 (150 × Chai) exceeds Michael Suyama's
  limit of 100 → PO-50-R routed to Robert King (L2), approved`.

### A3. PO closed → accounts payable + supplier scorecard
- Widen SQ3 from "resubmitted PO closed" to "PO closed"; the lineage case is a
  clause in the message, not a separate query.
- **Action:** create `:Invoice` in `PayablesDue` (amount = RFQ qty × UnitCost,
  due day+30); atomically bump the supplier's `:SupplierScore` isotope
  (`POsClosed`, `UnitsDelivered`, `Resubmissions`). A1 reads the scorecard as a
  tiebreaker → **the loop closes: what the twin learns changes what it buys.**
- **Prints:** `[PO CLOSED] PO-50-R (resubmission of PO-50): invoice INV-50-R
  $4,860 to Exotic Liquids due day+30 · supplier 7 closed / 1 resubmitted`.

### A4. Order shipped → customer 360 + tier promotion
- **Action:** atomically add the order total to the customer's `:CustomerSpend`
  isotope; if the yielded total crosses the Preferred threshold (say $600) add
  the customer to `PreferredCustomers` (state = position).
- **Second-order SQ:** `PreferredCustomers CONTAINS Customer` →
  `[TIER] Around the Horn promoted to Preferred ($612 shipped today)`. An
  automation firing an automation — the chaining beat, on screen.
- The JSONL "system of record" output stays.

---

## 5. Engine rules the build must follow (all measured on 2.1.0 in this project)

- **Never plain-`SET` a multi-writer counter.** The *current* recipe already
  has this race: receiving does `UnitsInStock + x` and fulfillment does
  `UnitsInStock - qty` from concurrent streams. Convert every isotope write to
  `CALL int.add(node, "UnitsInStock", ±x) YIELD result` (node + property-name
  string, `YIELD result` — the `int.add(n.prop, 1) YIELD value` form in the
  skill docs fails on 2.1.0). A4's spend uses `float.add` and tests the
  **yielded** value, not a re-read.
- No variable-length paths and no cross-node comparisons in SQ patterns; put
  the verdict in a collection and pattern on the collection.
- SQs declared in the recipe, armed before data (golden rule 7). Seed is
  batch reference state; everything else streams against it.
- Verify across 3+ runs against independently recomputed truth (per-day
  counts must be identical every day, and the same every run).

---

## 6. Runtime and website (decide later, but don't paint over it now)

- Route every alert family to its own `WriteToFile` JSONL as well as stdout;
  a web page tails those and polls 2–3 Cypher queries (collection counts,
  inventory dashboard). That is enough to "see the twin act" without exposing
  Quine's unauthenticated OSS API/UI to the public internet.
- The 1.5 GB log came from the status spinner + stdout alerts at 1 tick/s over
  64 h. For a long-running server: alerts to files, console kept to the tail.
- Determinism means the same day replays identically — good for a site, and
  good for verification.

---

## 7. Build sequence (each session ends with a 3-run verification)

1. **Day-cycle skeleton.** Day/t in every stream and id; schedule constants;
   close-of-day archive; isotope `int.add` fix; LowStock semantics + BackOrders +
   cancellations. Verify: 3 consecutive days, node counts bounded and identical,
   alerts identical per day.
2. **A1.** SupplierOffer isotopes, catalog feed, recommendation SQ, procurement
   consumes recommendations.
3. **A2 + A3.** ApprovalLimit, rejection rule, auto-resubmit; invoices and
   scorecard; scorecard feeds A1.
4. **A4 + tier SQ**, per-family JSONL outputs, README with the §1 timeline as
   the viewer's script. Node appearances / quick queries for the new labels.
5. **Soak:** 12 days (1 h) unattended; RSS and query latency flat. Then the
   website page.

---

## 8. Open questions for Adam

1. Loop: Option B (in-graph day cycle) or A (restart)? Recommendation: B.
2. Is a delete at day close acceptable against rule 4, framed as archive-after-
   ledger? (Option A deletes everything anyway.)
3. Rejection: rule-driven (ApprovalLimit on the role) or keep every-5th?
   Recommendation: rule-driven.
4. Where does this live — stay under `Agent Authority/Marcos/`, or its own
   `Recipes/northwind-plus/` since it is a separate demo with its own docs?

---

## Verification (2026-09-14, Quine 2.1.0, jar via `_engine/resolve-jar.sh`)

**Runs.** Day A (standalone, pre-tuning: stock 40 / threshold 25 / tier $1,200) — clean but
0 back orders and all 8 customers promoted. Day B (standalone, shipped tuning) and Days C + D
(`--loop`, two consecutive fresh JVMs) — **all three tallies identical**:

| Family | B | C (loop day 1) | D (loop day 2) |
|---|---|---|---|
| LOW STOCK / RESTOCKED | 25 / 25 | 25 / 25 | 25 / 25 |
| RECOMMEND | 25 | 25 | 25 |
| AUTO-RESUBMIT | 3 | 3 | 3 |
| PO CLOSED | 25 | 25 | 25 |
| BACKORDER / RELEASED | 7 / 7 | 7 / 7 | 7 / 7 |
| SHIPPED | 119 | 119 | 119 |
| TIER | 4 | 4 | 4 |

**Invariants re-derived from the graph after Day B (Cypher over the live API, not the log):**
119 in ShippedOrders, 0 in OpenOrders / BackOrders / LowStock / Reordering / NewPoS /
ApprovedPoS / SubmittedPoS / RecommendedPurchases; 25 recommendations ↔ 25 POs raised from them
↔ 25 in ClosedPoS ↔ 25 invoices in PayablesDue; RejectedPoS = 3 and each has a `-R`
resubmission in ClosedPoS; supplier scorecards sum to 25 closed / 3 resubmissions; 0 products
with negative stock; 4 in PreferredCustomers; `{"alert":null}` lines 0; runtime errors 0.
Day A's invariants held the same way (16/16/16/16, 3 rejections, 8 promoted).

**Loop.** Days C→D: end-of-day tally printed, 20 s pause, JVM restarted, six feeds re-armed
(HTTP 204), API answered before the first tick, Day D's graph started from the seed (identical
tally is the evidence). The loop was stopped by hand during Day E.

**Not verified / limits.** Feeds were armed and accepted; nobody toggled a chip in a browser this
session, so "the canvas draws the match" is asserted from the bank-cve precedent, not observed
here. Money prints as `1170.0`. A recommendation raised after ~tick 268 cannot close in-day (none
did in these runs: SubmittedPoS was empty at every day end).

**Build gotchas found (all also in memory `northwind-marcos-demo`):** v2 enum is `DISTINCT_ID`;
quickQuery `sort: NODE|TEXT` and no `queryLanguage`; **`WITH` is required between `SET` and
`CALL`**, and that compile error kills Quine's main thread without killing the JVM (streams run,
API never comes up — the launcher now greps for it and fails fast); every enrichment runs once at
startup with a null `$that`, so each starts with an `isPositiveMatch` guard.
