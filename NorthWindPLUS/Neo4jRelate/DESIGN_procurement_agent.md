# Design: the Procurement Assistant agent, and model v2.3.3

**Status:** built and tested offline (40 checks in `tests/test_procurement_offline.py`, plus the existing suites).
Not yet applied to Aura: run `model/NorthWind_PLUS_v2.3.3_Upgrade_from_v2.3.2.cypher`, which lists its steps.

The first step of moving the simulation's jobs from Python loops to agents with a person in charge. A Procurement
Assistant asks what needs restocking; the agent recommends POs computed by the same rules the `po-creation` loop
uses; the assistant accepts all, some, or changes quantities, gives one justification per PO, and confirms. The
same agent handles **resubmitting rejected POs**, which today the `po-vetting` loop does on its own.

Decisions so far (2026-11-17): the `po-creation` loop is stopped while the agent runs; the model is updated; one
justification per PO; resubmission is part of this agent.

## 1. What changes in the simulation

| Today | With the agent |
|---|---|
| `po-creation` loop, 1 per minute, a random Procurement Assistant | **stopped**. The signed-in Procurement Assistant creates POs through the agent |
| `po_resubmit`, one of the `po-vetting` loop's actions, resubmits a random rejected PO | **removed from the loop** (a harness switch, `--no-resubmit`, used by `run_loops_agents.bat`). The agent recommends resubmissions; the assistant decides |
| A rejected PO that's never resubmitted waits in `RejectedPoS` forever | the assistant can **cancel** it, with a reason (new state, see 2.4) |

Both ways of running stay available (decided 2026-11-17): `run_loops_full.bat` runs all six loops with the agent
alongside (`SIMULATION_MODE=full`, the default: no PO tools), and `run_loops_agents.bat` runs five, with PO Vetting on
`--no-resubmit` (`SIMULATION_MODE=agents`). In agents mode the PO tools refuse to write while a simulated PO created or
resubmitted in the last 3 minutes shows the loop is still on. Each later agent
(approvers, buyer, warehouse, finance) will retire its loop the same way.

## 2. Model v2.3.3

Designed once for this agent *and* the vetting agents that follow, so there's one more Aura upgrade rather than one
per agent. Every new property is **optional**, so the Python loops that remain keep running unchanged, and existing
data stays valid.

### 2.1 PO creation: who, when, why

```
(:PurchaseOrder)-[:PO_CREATED_BY => {Date :: ZONED DATETIME, Justification :: STRING, Source :: STRING}]->(:Employee)
(:PurchaseOrder)-[:HAS_PO_ITEM   => {POqt :: INTEGER NOT NULL, POPriceDiscount :: FLOAT NOT NULL,
                                     RecommendedQt :: INTEGER}]->(:Product)
```

- `Justification`: the assistant's reason, one per PO.
- `RecommendedQt`: what the agent proposed, next to `POqt`, what was ordered. When they differ, the PO shows the
  person overrode the recommendation, and the justification says why.

### 2.2 Resubmission: when, and by what

```
(:PurchaseOrder)-[:HAS_PREVIOUS_PO => {Resubmission_Justification :: STRING, Date :: ZONED DATETIME,
                                       Source :: STRING}]->(:PurchaseOrder)
```

`Resubmission_Justification` already exists. The new PO also gets `PO_CREATED_BY` as in 2.1, with the signed-in
assistant (the loop today credits the original PO's creator).

### 2.3 `Source` on every decision, for the vetting agents to come

The vetting relationships already carry `Date` and `Comment`, so an approver agent has a place for its
justification. What's missing is **how** the decision was made, once loops and agents coexist. v2.3.3 adds an
optional `Source :: STRING` to:

`PO_CREATED_BY`, `HAS_PREVIOUS_PO`, `HAS_L1/L2/L3_PO_APPROVAL`, `HAS_L1/L2/L3_PO_REJECTION`,
`HAS_BUYER_PO_APPROVAL`, `HAS_BUYER_RFQ_APPROVAL`, `HAS_BUYER_RFQ_REJECTION`, `HAS_WAREHOUSE_DELIVERY`,
`HAS_FINANCE_PAYMENT`, `HAS_WAREHOUSE_FULFILLMENT` (customer orders), and the new `PO_CANCELLED_BY`.

Values: `"simulation"` (a Python loop), `"agent"` (recommended by an agent and confirmed by the signed-in person) or
`"ui"` (a person in the web UI; see [DESIGN_procurement_ui.md](DESIGN_procurement_ui.md)).
Missing means before v2.3.3. The harness is updated to write `"simulation"`, so a query can compare, say, rejection
rates of agent-assisted and simulated vetting.

### 2.4 A new state: cancelled POs

```
(:PoS)-[:HAS_CANCELLED_PO_STATE => {}]->(:CancelledPoS)
(:CancelledPoS)-[:IS_CANCELLED_PO_STATE => {Date :: ZONED DATETIME NOT NULL, Comment :: STRING}]->(:PurchaseOrder)
(:PurchaseOrder)-[:PO_CANCELLED_BY => {Date :: ZONED DATETIME NOT NULL, Justification :: STRING,
                                       Source :: STRING}]->(:Employee)
```

A rejected PO the assistant decides not to resubmit moves from `RejectedPoS` to `CancelledPoS`, following the model's
principle: state is a relationship to a Collection node. The rejection itself (`HAS_Lx_PO_REJECTION`) stays as
history. Without this, the agent would recommend the same rejected PO for resubmission forever.

### 2.5 Optional: close the gaps between approval bands

Today's bands leave a sliver no rule matches: a cost exactly on a limit can only be rejected, and a cost inside the
one-cent gap between levels (`L2.ApprovalBase = L1 + 0.01`) can't even be rejected. The what-if flags these. Since
vetting agents will rely on the same rules, v2.3.3 could make the bands **contiguous**: each level covers
`ApprovalBase < cost <= ApprovalLimit`, with `ApprovalBase` equal to the previous level's limit. That touches the
harness's vetting Cypher, the governed limit change, the preview and what-if, and the `RolE` data, but nothing else.

### 2.6 Files

Same set as v2.3.2: import script, GRAPH TYPE, RDF/Turtle ontology, an upgrade script from v2.3.2 (safe to run while
the loops run, all `MERGE`/`ALTER`), and the harness. The knowledge store is rebuilt from them; learned templates are
kept and re-checked as usual.

## 3. The agent

### 3.1 Tools, offered by role

The session already knows the signed-in employee's roles. Tools are offered by role, which is the pattern for every
later agent:

| Role | Tools |
|---|---|
| everyone | read questions, what-if (as today) |
| Procurement Assistant | `recommend_restock`, `recommend_resubmissions`, `create_purchase_orders`, `resubmit_purchase_orders`, `cancel_rejected_purchase_orders` |
| ProcurementPolicyAdmin | the approval-limit tools (as today) |

### 3.2 Recommending

- **`recommend_restock`** runs the read half of the `po-creation` loop's Cypher: available products whose stock, plus
  quantities on active POs, minus quantities promised to open customer orders, is at or below the restock threshold.
  It returns, per supplier: products, current figures, recommended quantity (the loop's formula), estimated cost at
  the standard discount, and **the approval level the PO will need**.
- **`recommend_resubmissions`** does the same for rejected POs not yet resubmitted or cancelled. It includes who
  rejected each one, at which level and with what comment, so the assistant can decide whether to resubmit (with
  recomputed quantities) or cancel.

The two loop formulas differ today (`+ StockThreshold * 2` for new POs, `+ StockThreshold / 2` for resubmissions).
The agent reuses each one as is; aligning them is a separate business decision.

### 3.3 Deciding

The agent shows a numbered list. The assistant answers naturally: *"accept 1 and 3; for 2 make Chai 50"*,
*"resubmit PO-123 with the new quantities, cancel PO-456: supplier discontinued the product"*. The agent asks for one
justification per PO if it's missing, shows the final list, and asks for confirmation (a prompt under the notebook
cell, or in the terminal). Nothing is written before that.

### 3.4 Writing: fixed, governed Cypher

Like the approval-limit change, the writes are tested Cypher templates with parameters, never model-written Cypher.
In one Aura transaction, each template:

1. checks the requester holds `Procurement Assistant`;
2. locks the products involved (`apoc.lock.nodes`), so two assistants, or an assistant and a remaining loop, can't
   order the same need twice;
3. **recomputes what's pending** and refuses lines that are now covered by a PO created since the recommendation,
   reporting them rather than failing the whole batch;
4. checks that the supplier supplies each product, the product is available, and each quantity is a whole number
   above 0;
5. writes the PO in `NewPoS`, `PO_FOR_SUPPLIER`, `PO_CREATED_BY {Date, Justification, Source:"agent"}`, and
   `HAS_PO_ITEM {POqt, RecommendedQt, POPriceDiscount: 0.7}`; or for a resubmission, also `HAS_PREVIOUS_PO`; or for a
   cancellation, the state move and `PO_CANCELLED_BY`.

### 3.5 Guard rails

- **One justification per PO** is required; the tool refuses without it.
- **Large overrides:** a quantity above 3× the recommendation, or below a third of it, needs the justification to
  address it, and the agent says so before confirming.
- **No PO splitting.** The agent shows which approval level each PO will need and never suggests splitting a PO, or
  trimming it, to fall under a lower limit. Splitting to dodge an approval level is a classic procurement control
  failure. The prompt says so, and the agent declines if asked.
- Every interaction is kept in relate as today, with the templates used, so later questions can find what
  assistants usually change and why.

## 4. Tests and notebooks

Offline tests in the existing style: relate holding a small procurement graph as a stand-in for Aura, a scripted
client in place of Claude. They cover recommendations matching the loop's formula, accept-some, quantity changes,
refused lines already covered, role checks, the no-split rule, resubmit and cancel, and `Source`. Both notebooks get
a "Procurement" section signed in as a Procurement Assistant (Albert Camus, EmployeeID 16).

## Decisions (2026-11-17)

1. **Cancelled POs (2.4):** yes, `CancelledPoS`; a cancelled PO moves there from `RejectedPoS`.
2. **`Source` (2.3):** yes, on every decision relationship: keeping audit trails is a must.
3. **Contiguous approval bands (2.5):** yes, fixed in v2.3.3.

## As built

- The templates live in the import script's new **Procurement Assistant** section, next to the Approval Policy
  Change, so the knowledge store picks them up like any other template (`(governed)` in a title marks a governed one).
- A Procurement Assistant gets the five tools; an approver or the policy admin doesn't see them, and a tool that isn't
  offered is refused if called anyway.
- The import script's own line numbers moved: the import is now lines 109-1186, the Recommendation Engine 1286-1349.
- The upgrade script keeps limits already changed through a `PolicyChange` (only the bases move to remove the gap),
  and it can be run more than once.
- Relate's full-text search matches whole words only, so "restocking" didn't find "Restock recommendation" until the
  description used the word. The agent reaches it through `recommend_restock` anyway.
