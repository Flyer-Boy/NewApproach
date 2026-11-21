# Design: unblocking stuck customer orders

Status: **built**: templates, `sandbox/unblock.py`, the governed write, API and the *Stuck orders* tab. Tested offline
(34 checks for the simulation and templates, 11 more in the API suite) and clicked through on the toy graph; **not yet
run against Aura**. Model v2.3.3 (no schema change). Builds on the web UI
([DESIGN_procurement_ui.md](DESIGN_procurement_ui.md)) and the what-if sandbox ([DESIGN_what_if_sandbox.md](DESIGN_what_if_sandbox.md)).

## The problem

The order-fulfillment loop ships **the oldest open order whose every line is in stock right now** and skips the
rest. A large order needs all its products in stock at the same moment. Each delivery that would cover part of it is
used up first by smaller orders that are complete, so large orders can wait indefinitely: starvation, as
`AI_Agents_Food_For_Thought.md` describes it. Customers with big orders wait the longest.

The restock rule doesn't fix it. It looks at totals (stock + on order − promised to open orders), so it can be
satisfied on paper while a stuck order still never sees all its lines in stock at once.

## The idea

A button on a new **Stuck orders** screen asks: *how much would have to arrive so that these orders actually ship?*
The answer can't be read off the graph; it has to be simulated, because smaller orders ahead in the queue and new
orders still coming in will consume deliveries first. The simulation replays the fulfillment rule forward, which
means shipping orders and decrementing stock, so it runs on a disposable copy in **Relate**, never on Aura. Aura stays
the system of record; Relate is where the business is played forward.

The result is a set of proposed POs, shown above everything else, each saying which orders it unblocks. A person
accepts, edits or dismisses them; accepted POs are written to Aura through governed Cypher.

## Decisions (agreed)

1. **Stuck** = an open order waiting more than **3× the median time to ship**, measured from orders fulfilled in the
   last 3 days (`OrderDate` → `IS_FULFILLED_ORDER_STATE.FulfillDate`), with at least one line short of stock. Only
   the simulation's own orders (`CO-…`) count; see *Decided while building*.
2. **Priority:** shown first in the UI, and the justification starts with a line for the approvers, for example
   `PRIORITY: unblocks customer orders 10248 (waiting 3.2 days) and 10260 (2.9 days).` No model change. A
   `PriorityPoS` collection that the approval loop handles first (v2.3.4) stays an idea for later.
3. **On demand:** a button, for the demo. No background agent yet.
4. **Overstock tolerance** per product = what customers ordered of it over the **last 3 days**. A proposal needing more
   extra than that is still shown, flagged for a person to judge.

## How it works

### 1. Find the stuck orders (Aura, read template *Stuck customer orders*)

Per open order older than 3× the median time to ship: customer, age, value, lines (ordered vs in stock), and which
lines are short. Ranked by age, then value. The median and the 3× threshold are returned too, so the screen can say
what "stuck" means right now.

### 2. Measure the business's pace (Aura, read template *Fulfillment pace*)

All from the last 3 days, span-adjusted like the demand template (a simulation that has run a few hours isn't
averaged over three days):

- orders shipped per hour, and new orders per hour;
- units ordered per product per hour (the expected new demand);
- **PO lead time**: median time from PO created to warehouse delivery (`HAS_WAREHOUSE_DELIVERY.Date`).

### 3. Copy the relevant part of the graph into Relate

One `relate pull` (or the driver fallback, as the what-if does) into a scratch store: the stuck orders; every open
order that shares a product with them (the competition); those products' inventory, reorder levels and suppliers; and
the active POs carrying them, with their state and creation date. One warehouse clerk and one shipper, so the
fulfillment Cypher runs as written.

### 4. Play the business forward (Relate)

Time advances in fulfillment cycles. In each cycle:

- the **simulation's own fulfillment Cypher** runs (imported from the harness, without the APOC locks): the oldest
  fully stocked open order ships and stock is decremented;
- new orders arrive at the measured rate, with products drawn from the measured demand mix;
- POs whose lead time has elapsed deliver into stock (active POs at created + lead time; proposed POs at now + lead
  time).

**The search:** for each stuck order, oldest first, find the smallest extra quantity per short product such that the
order ships within a horizon (lead time plus a margin) in at least 4 of 5 runs. Extras found for earlier stuck orders
are kept when searching for later ones, since they compete for the same stock. Random arrivals mean results are
estimates; the screen says so.

### 5. Propose

One PO per Supplier: each line shows the normal restock quantity (if the product needs one anyway), the extra for
stuck orders, and the total; the orders it unblocks and how long they've waited; estimated cost; the approval level it
will need; and an overstock flag where the extra exceeds the 3-day tolerance. Orders the search couldn't unblock within
the horizon are listed with the reason.

## Writing the POs: a new governed template

The existing *Create a Purchase Order (governed)* writes a line only if the product passes the restock rule, so it
would silently drop most stuck-order lines. New template, **Create a Purchase Order for stuck customer orders
(governed)**:

- same checks as the create template: active Procurement Assistant role, a justification, `$source` is `"agent"` or
  `"ui"`, the Supplier supplies each product and it's available;
- **instead of the restock rule:** each line's product must be on one of the given stuck orders, and each of those
  orders must still be open and still past the stuck threshold. A line whose order has shipped meanwhile is left out
  and reported, as the create template does for lines no longer needed;
- the justification must start with `PRIORITY:`, so the approvers always see it;
- records `Source`, `Justification` and `RecommendedQt` (the simulated quantity) like every other PO, so the audit
  shows where people changed the proposal.

`agent/procurement.py` gets `recommend_unblock` / `prepare_unblock` / `commit_unblock`, so the agent can offer the
same thing later ("which customer orders are stuck, and what would free them?").

## Where the pieces live

- `sandbox/unblock.py`: pull, play forward, search. Reuses `sandbox/pull.py` and the harness's fulfillment Cypher.
- The two read templates and the governed template in the import script (after line 1360, so the README's import
  ranges don't move).
- API: `GET /api/stuck-orders`, `POST /api/stuck-orders/simulate`, preview/commit like the other writes.
- UI: a **Stuck orders** tab: the stuck orders, a *Find what would free them* button, the proposals with their
  evidence, a *Suggest* draft (pre-filled with the `PRIORITY:` line), review, create.
- The scratch store is deleted after each run, as the what-if's are. It's a separate file from the agent's knowledge
  store, so no lock conflict.

## Testing

- Toy graph: a large order starved by a stream of small ones (deterministic seed), checking the search finds the
  quantity that frees it, and that the naive shortfall would not.
- The governed template: lines for orders that shipped meanwhile are left out; a justification without `PRIORITY:`
  writes nothing; role and source checks.
- API and UI as for the other screens; a click-through on the toy graph.

## Decided while building

- **Horizon:** an order counts as freed if it ships within the PO lead time plus the median time to ship.
- **The 5 oldest stuck orders per run** (`MAX_STUCK_ORDERS`); stuck rule and window in `.env` (`STUCK_FACTOR`,
  `STUCK_WINDOW_DAYS`).
- **The search uses one observation:** a stuck order is the oldest open order, and the loop ships the oldest fully
  stocked order, so once its lines are all in stock it ships next. The extra per product is
  `(stuck quantities, oldest first) + 1 - stock when the delivery lands` (stock must be strictly above the quantity),
  taken at the 80th percentile over 5 runs, then verified by a second replay (bumped and re-verified up to 3 rounds).
  Seconds, not minutes.
- **The naive quantity is replayed too,** so the screen can show it would not free the orders.
- **Reservation comparison: included.** A variant of the fulfillment Cypher where stock promised to open stuck orders
  can't be used by other orders; reported as stuck orders freed and other orders delayed.
- **Ticks** are one minute, longer when the lead time is long, so a replay stays around 600 ticks.
- **Overstock:** an extra above what customers ordered of the product in the last 3 days is flagged, not blocked.
- **Only the simulation's own orders count (`ORDER_ID_PREFIX`, default `CO-`).** Found on the first live run: after
  a fresh load, the loop ships imported historical orders placed decades ago, which pushed the median time to ship to
  about 29 years (15,327,319 minutes) and made nothing look stuck. The prefix applies to the median, to what counts as
  stuck, and to the governed template's check; orders shipped per hour still counts every order, since shipping an
  imported order uses the warehouse's capacity too.
- **Older orders that ship first are part of the search.** Imported orders still open are the oldest of all, so when an
  extra delivery lands, one that becomes fully stocked ships before the stuck order and takes its share.
  `need_at_delivery` replays that moment (ship the oldest fully stocked order, repeatedly) on the queue and stock
  recorded at delivery time, and adds what the stuck orders are still short of; the replay with the loop's own Cypher
  then confirms. On the toy graph, an imported order needing 35 Chai raises the simulated extra from 26 to 61.
- **Little history, low quantities.** The simulation projects the next hours from the recent past, so on a young
  database (few own orders shipped, a short window, no PO delivered yet) it under-estimates the competition. The pace
  template now reports how much history it rests on (`ShippedOwn`, `ObservedHours`); the screen warns in plain words,
  and `UNBLOCK_SAFETY_PERCENT` adds an optional margin on top of the simulated quantity (verified by the replay like
  the rest).
- **Agent tool:** not yet. `recommend_unblock` / `prepare_unblock` / `commit_unblock` are ready for one.
