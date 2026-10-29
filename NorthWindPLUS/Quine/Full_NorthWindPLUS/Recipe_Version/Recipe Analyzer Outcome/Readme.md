# Quine Recipe Analyzer report — review of the NorthWind PLUS recipe

Marcos Pinedo · October 29, 2026

## Summary

I used Quine Recipe Analyzer (https://www.thatdot.com/quine/recipe-analyzer.html), very cool, on the Recipe yaml file. Below is a review on the findings and some elaborations around Supernodes. Something that haunts my model since day one. 

Of the 90 findings, most come from the analyzer seeing only the recipe, which is how the work is split: the batch imports the data, the recipe runs the simulation. Two points are worth acting on: an idempotent `customer-order` stream, and the supernode warnings on the history Collections. Two others are errors in the analyzer itself that thatDot may want to hear about.

The report covers `northwind-plus-simulation.yaml`: 7 ingest streams and 11 standing queries, all in `DistinctId` mode. It was produced with thatDot's [Quine Recipe Analyzer](https://www.thatdot.com/quine/recipe-analyzer.html).

## No action needed (by design)

| Finding | Count | Why it's expected |
| --- | --- | --- |
| Label X is matched but never SET (Employee, Customer, Product, …) | 25 | The batch (`northwind-plus-quine-batch.sh --import-only`) sets them; the analyzer never sees the batch. Some are analyzer errors (next section). |
| Relationship X is matched but never created (`IS_ACTIVE_ROLE`, `HAS_INVENTORY_LEVEL`, `SUPPLIES`, …) | 15 | Created by the batch. The recipe deliberately runs only the simulation. |
| Property condition on id-anchored node: `sim.Ready = true` | 8 | The go-live gate. Dropping the record until the batch finishes is exactly its job. |
| Edge endpoint could not be resolved (`sop`, `snr`, `snp`, `cpo`, `scp`, `a`) | 7 | Those nodes are reached by walking from a known node, e.g. `(su)-[:HAS_SUPPLIER_OPEN_POS]->(sop)`, not by `idFrom`. They resolve correctly at run time; the tests showed it. |
| Node RolE is keyed from multiple sources (INFO) | 1 | The batch creates every role from the same strings, so the keys match. |

## Analyzer errors worth reporting to thatDot

Feedback:

- **It doesn't count labels set in `CREATE`.** It reports `PurchaseOrder`, `RFQ`, `RFQItem`, `POItem`, `VettingDecision` and `WarehouseDelivery` as "never SET". The recipe itself creates each with its label, e.g. `CREATE (po:PurchaseOrder {PODate: …})` in `po-creation`.
- **It mis-types edges written in one multi-part `CREATE`.** The relationships table shows `PurchaseOrder -[:HAS_SUPPLIER_NEW_RFQ]-> VettingDecision`, `PurchaseOrder -[:HAS_SUPPLIER_REJECTED_RFQ]-> VettingDecision` and `VettingDecision -[:IS_SUPPLIER_REJECTED_RFQ_STATE]-> RFQ`. The real nodes are `PoNewRFQ` and `PoRejectedRFQ`. It looks like it attaches the wrong node from the comma-separated pattern in `nw-buyer-submission`.

## Worth acting on

### 1. Generated IDs: make `customer-order` idempotent

The analyzer flags 27 `CREATE (n {…})` statements that give nodes generated IDs instead of `idFrom` IDs. Most are harmless: every other stream re-checks its guard ("not already delivered", "no RFQ yet"), so a retried beat does nothing.

The exception is `customer-order`, the one caveat already in the README. If Quine retries it after a timeout, it adds one extra order. The fix the analyzer suggests:

- Key the order on the stream's beat number, e.g. `idFrom("SimOrder", n)`.
- Guard with `MATCH (o) WHERE NOT (o)-[:HAS_ORDER_CUSTOMER]->()`, so a retried beat finds the order already built and skips.

One uncertainty: if Quine restarts a stream mid-run, the beat numbers may start again from 0. Old beats would then be skipped rather than duplicated. That's safer, but some orders would be missing.

### 2. Supernodes: the one real design discussion

The analyzer flags 7 Collections as likely supernodes. The warnings aim at the core principle: every state is one Collection node with one edge per member. The risk differs a lot by Collection:

| Collection | Size over time | Risk |
| --- | --- | --- |
| `NewPoS`, `ApprovedPoS`, `SubmittedPoS`, `OrderStatusOpeN` | stays small: members pass through and leave | low |
| `LowStocK` | can never exceed the 77 products | none |
| `OrderStatusFulfilleD`, `ClosedPoS`, `RejectedPoS` | grows forever: they hold history | real, at scale |

`ClosedPoS` isn't in the report, but it grows the same way as the other history Collections.

At this demo's size (about 900 fulfilled orders) none of this is a problem; the test runs showed no slowdown. At millions of orders, one node holding every fulfilled order is a classic hot spot. That is presumably why the tool flags it, but Quine hasn't been measured at that scale here, so where the line is remains open.

The analyzer suggests storing the state as a property. That would undo *state = position*. Its other suggestion keeps the principle intact: **partition only the history Collections by period**, e.g. `idFrom("OrderStatusFulfilleD", "2026-10")`, each linked from the parent status node. The order's state is still its position; the position just has a date. The working Collections stay as they are.

This could be a follow-up article: how state-as-position scales.

## Next steps

- [ ] Decide whether to make `customer-order` idempotent (small change: the recipe only)
- [ ] Decide whether to partition the three history Collections by month (bigger: the batch, the recipe, the report queries and the checks)


## Beyond this recipe: supernodes are a storage problem for every graph engine

I'd like to open this discussion with every graph vendor: thatDot (Quine), Neo4j, Memgraph and others. In any model that runs business applications on a graph, supernodes will happen. Modeling can reduce them; it can't remove them.

**What modeling can do.** In NorthWind PLUS I deliberately keep key nodes light. State is offloaded (normalized) into Collections, and a key node keeps only its most relevant edges as outgoing edges.

**What modeling can't stop.** A node's incoming edges keep growing over time, because every new thing that refers to it adds one. In NorthWind PLUS:

- **A Shipper:** every shipment points to it. In one test run, United Package had 329 incoming edges, the most of any node in the graph.
- **An L1 approver:** every vetting decision they make points to them (`VETTED_BY`).
- **The history Collections:** `OrderStatusFulfilleD`, `ClosedPoS` and `RejectedPoS`, as above.

### The contact-list paradigm

> My contact list holds everyone I know, and it's easy to find them. If it also held everyone who knows *me*, it would get harder. And if I were a celebrity, I would never find anyone when I needed them.

That is what happens to these nodes, despite the effort to keep their own edges few. The node's own list (whom it knows) stays short. The list of everyone who points at it is what grows without bound.

### What the engine would need to do

The fix has to happen at the storage level, mirroring what the model already does. **Normalize each node's adjacency list the way the model normalizes state:**

- **A high-relevance list:** the node's outgoing edges and the edges it actually uses, kept close and fast to traverse.
- **A low-relevance collection:** the bulk of incoming edges, stored apart, still complete and queryable, but off the hot path.
- **Promotion and fading by use:** an internal algorithm that moves edges from low to high relevance as they get traversed, and lets unused ones fade back.

This mimics how neurons work. A neuron has thousands of connections. Connections that aren't used weaken over time, and the ones that get stimulated strengthen again.

### Why it matters for business applications

Analytics workloads scan large parts of a graph, so a heavy node is one cost among many. A business application is different. It runs many small, anchored traversals in real time: this order's customer, this PO's approver, this product's stock. Each must stay fast no matter how many other edges the node has collected. For graphs to *run* businesses, not only analyze them, engines will need to treat a node's edges unequally.

### Open questions for the vendors

- Does your engine already store a node's edges apart by direction or type? Some do for dense nodes; Neo4j, for example, groups a dense node's relationships by type and direction (check its current documentation for the details). Does that solve the contact-list case, or only part of it?
- Can how often an edge is traversed influence where it's stored?
- How do standing queries (Quine) or triggers behave when a pattern touches a node with hundreds of thousands of incoming edges?

## Deeper elaboration on the matter

The diagnosis above holds: modeling can move supernodes around, not remove them. Three refinements sharpen it, and a few modeling options help until engines catch up.

### 1. "Supernode" is three different problems

| Problem | When it hurts | NorthWind PLUS example |
| --- | --- | --- |
| **Loading:** reading the hub's whole adjacency list to use one edge | Reading from leaf to hub ("this shipment's shipper") | Shipper, L1 approver |
| **Write contention:** every new edge must update the hub | High insert rates | `OrderStatusFulfilleD`, `ClosedPoS` |
| **Fan-out:** a query walks all of the hub's edges | "All orders this approver vetted" | rare in a business application |

Business applications mostly hit the first two and seldom the third. So the engine must reach a hub's relevant edges without touching the rest.

### 2. For business data, recency predicts relevance better than usage

Promotion by use is adaptive caching. It works, but it makes latency hard to predict, and a business system wants the same answer at the same speed every time. In business data the edges that matter are almost always the recent ones: this month's shipments, open POs, the latest decisions. Old edges become history and are rarely read.

So the engine's split could be mostly time-based and deterministic:

- **Recent edges** in a small, fast segment.
- **Older edges** rolled into sorted, indexed segments.
- **An index on each node's own edges** by type, direction and time, so "the latest N" or "this exact edge" is a quick lookup however big the node gets.

Usage-based promotion is then a refinement on top, not the foundation. This is the automatic, engine-level version of partitioning the history Collections by month, without changing the model.

### 3. "Fading" must mean moving, never forgetting

The neuron analogy holds with one change. Synaptic pruning loses information; a business can't lose an edge. Fading changes *where* an edge is stored, never *whether* it exists. Perhaps a dynamic *edge ranking* mechanism.  

### Where existing engines stand

These notes are from general knowledge, not tested here; check each vendor's current documentation.

- **Neo4j** groups a dense node's relationships by type and direction once it passes a threshold. That helps with "find edges of type X", but not with "the latest" or "this specific one" among millions.
- **JanusGraph** (from the Titan lineage) has *vertex-centric indexes*: an index over each vertex's own edges, sorted by an edge property. It's the closest existing thing to the proposal above.
- **PowerGraph** (OSDI 2012) and similar systems split high-degree vertices across machines. That design targets analytics, not transactions.
- **Quine:** as understood here, each active node lives in memory with its edges, so a node with a huge edge set would be costly to wake and to write to. Not verified; a question for thatDot.

### Modeling options until engines catch up

- **Separate the working graph from the history graph** (the strongest option). The operational graph holds the open business: open orders, POs in flight, current stock. When something reaches a final state (closed, fulfilled, rejected), it isn't deleted; it moves. Its edges to the busy hubs are rewired to a monthly history node, or into a separate history graph used for analytics. Live hubs then hold only live work, and their size follows business volume, not age. "Never delete nodes" still holds: nothing is lost, only moved.
- **Summary isotopes for history.** Most questions about the past are counts and totals: shipments per carrier per month, POs vetted per approver. An isotope such as "United Package, 2026-10: 329 shipments" answers them without walking 329 edges. It's the isotope principle applied to history.
- **Hub-of-hubs bucketing**, e.g. `Shipper → ShipperMonth → ShipInfo`, when the reverse direction must stay walkable. Time is the natural bucket, for the same recency reason.
- **To avoid:** replacing rarely walked edges with a property key (`ShipInfo.ShipperID`). It works, but it gives up the explicit context the graph-native approach is built on.

### Next: measure it

A small benchmark would turn the vendor discussion from opinion into data:

- One Shipper with 10k, 100k and 1M incoming shipment edges.
- Three timings per size: a lookup from a shipment to its shipper, adding an edge, and reading the shipper's latest 10 shipments.
- Run on Quine and Neo4j, and Memgraph too.
