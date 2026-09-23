## AI Agents in a Graph-Native Model: Food for Thought

While building NorthWind PLUS — the proof of concept behind my "New Approach" to Line-of-Business applications on a property graph — a question kept coming up while stress-testing the vetting and fulfillment loops: once the business rules *and* the business data both live in the same graph, what changes when you add an AI agent into the mix? Not as a chatbot bolted onto the UI, but as another actor that reads graph context and writes decisions back into the graph, the same way a human vetter or the fulfillment loop already do.

None of what follows has been built or tested yet. These are ideas worth exploring further, not conclusions — and one of them, below, turned out not to need AI at all, which is itself a useful data point.

### Assisting PO vetting, not replacing it

Today's PO approval chain (L1/L2/L3) is pure threshold logic: a role can approve a PO if its amount falls inside that role's approval band, evaluated entirely from graph data — no thresholds hardcoded outside the model. That's deterministic and auditable, but it can't ask whether a PO is actually *worth* approving. An agent could sit inside that same authorized band — never bypassing it — and flag or escalate the cases a pure number can't: a price that's drifted from a product's recent history, an unfamiliar supplier, a quantity out of step with recent orders.

### Learning from the decisions we already record

Every approval and rejection edge in the model already carries a `Comment` property, where the person making the decision records their reasoning. That's a ready-made, already-accumulating dataset — no new logging system required. The idea: before a human vetter acts, an agent reads that history plus the PO's current context and writes its own assessment as a separate node — a recommendation and a confidence rating, attached to the PO but distinct from the actual decision. The human sees it, then decides.

That assessment is what makes a handover measurable rather than a leap of faith: compare it against what the human actually did once the real decision lands, and track agreement over time. As it climbs, moving from *agent recommends* to *agent decides, human reviews the exceptions* becomes a data-driven call — and one that can be phased in per level, with L1 automated sooner than L3.

### Tuning the approval levels themselves

The same accuracy signal could point back at the thresholds, not just the decisions. If POs near the top of a level's band show worse outcomes than ones comfortably inside it, or if routine POs keep bottlenecking at a higher level than they need to, that's a signal a level is miscalibrated — a recommendation for a human to act on, not something the agent should be trusted to adjust on its own.

### Supplier selection in RFQ vetting — with a prerequisite

Choosing between competing supplier quotes is a genuine trade-off — price against lead time against track record — which suits an agent's judgment far better than a threshold does. But the current model has a single supplier per product, so there's nothing to choose between yet. This one needs the multi-supplier extension already proven out in the Tender Workflow model (https://github.com/Flyer-Boy/NewApproach/tree/main/TenderWorkflow) before it's worth building.

### A cautionary example: order fulfillment fairness

Large, multi-product orders can stall behind an endless stream of small ones, since an order only fulfills once every product on it is in stock at the same time — classic starvation, the same pattern schedulers have dealt with for decades. The first instinct was "an agent could notice this and intervene." Looking closer, most of the fix turned out to be a plain deterministic rule — age-weighted fulfillment, or reserving stock for orders that have waited past some threshold — no agent required. Where judgment genuinely helps is layered on top of that: choosing between several stalled large orders, weighing a customer's SLA, or deciding whether to hold an order, expedite a PO, or adjust a reorder threshold.

It's worth keeping this example in the write-up precisely because it didn't pan out as an AI use case. Reaching for a rule before reaching for an agent is very much in the spirit of the graph-native argument itself.

### Why the graph matters here

None of this needs a separate feature store or a data-warehouse pass. The context an agent needs — approval thresholds, the `Comment` history, supplier track record, current inventory — is already sitting in the same property graph the rest of the system reads and writes every day. That's the real point: agentic AI isn't a bolt-on for a graph-native LOB application, it's a natural next step once the data model is already this connected and already this queryable.
