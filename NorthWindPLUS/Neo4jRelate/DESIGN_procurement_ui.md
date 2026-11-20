# Design: a web UI for the Procurement Assistant

Status: **built**: refactor, `$source`, rebuild trigger, demand template, API (`api/`), React app (`ui/`), `run_ui.bat`.
Tested offline (60 + 40 checks), clicked through on the toy graph, and **run live against Aura** (Chrome and Edge).
Model v2.3.3.

Changes after the first live run:
- **Who raised each rejected PO.** The resubmission recommendation returns `RaisedBy` (EmployeeID, name, Source), so
  the agent sees it too. Rejected POs stay one shared queue: any Procurement Assistant may resubmit or cancel any of
  them; the screen and the template's comment say so.
- **Restock cards start left out;** the person includes the POs to create now. The Review button sits in a bar
  pinned to the bottom of the window.
- **Every screen reloads after a write,** and the page scrolls to the result.
- **Drafts use the agent's model** (`DRAFT_MODEL` overrides) with room to answer; a failed or empty draft shows its
  reason on screen.
- **`index.html` is served with `Cache-Control: no-cache`,** so a browser never keeps running a previous build.
- **The Aura connection is retried** (`agent/aura.py`): Aura briefly had no server for reads during the first run.
Builds on [DESIGN_procurement_agent.md](DESIGN_procurement_agent.md).

## Goal

Close the loop on "same graph, same Cypher, different front ends". The PO jobs handed over in Stage 6 can already be
done two ways:

| Front end | Who drives it | Writes recorded as |
|---|---|---|
| Simulation loop (`NorthwindPlus_Stress_Test.py`) | Python, on a timer | `Source: "simulation"` |
| AI agent (`agent/agent.py`, notebooks) | a person, in natural language | `Source: "agent"` |
| **Web UI (this design)** | a person, with forms and buttons | `Source: "ui"` |

The UI does what the Procurement Assistant agent does, and nothing more: recommend restocking, create POs, list
rejected POs, resubmit or cancel them, and show the audit trail. Same recommendation queries, same governed Cypher
templates, same guard rails. The only new code is presentation.

## Decisions

1. **Python backend reusing `agent/procurement.py`.** One implementation of the rules for the agent and the UI. The
   React app is TypeScript; the API is a thin FastAPI layer.
2. **The browser never talks to Aura.** It would expose the credentials and let anyone pick any identity, which
   defeats the role checks. The API holds the Aura connection and the session identity. (The RideHailing prototype
   connects the browser directly through `use-neo4j`; its README already flags that as demo-only.)
3. **Front-end stack from the RideHailing app:** Vite, React, TypeScript, Chakra UI, react-query, react-hook-form,
   zustand, react-router. Minus `use-neo4j` and `neo4j-driver`. Package versions to be checked when the project is
   set up.
4. **Agents mode only.** The UI refuses to write, like the agent, when `SIMULATION_MODE` isn't `agents` or the PO
   Creation loop wrote a PO in the last 3 minutes.
5. **Local only.** Runs with `npm run dev` + `uvicorn` against the user's Aura instance. Colab doesn't fit a web UI.

## Refactor: prepare / commit

Today each write method in `Procurement` validates, prints the list, asks `self.s.confirm()` (`input()`), then writes,
all in one call. An HTTP API can't pause for `input()`. Each write splits in two:

```
prepare_create(pos)   -> {"entries": [...cost, level, flags, justification...]} | {"refused": ...}
commit_create(entries) -> {"created": [...], "left_out": [...]}
```

(and the same for resubmit and cancel). The existing tool methods become `prepare → _show → confirm → commit`, so the
agent behaves exactly as before: the 43 existing checks in `tests/test_procurement_offline.py` pass unchanged. All guard rails stay in
`prepare` (one justification per PO, one PO per Supplier per batch, recommendation first, 3× flags) and in the Cypher
(role re-check, product locks, recompute what's still needed). `commit` re-runs the loop guard, since time passes
between preview and confirmation.

The class also stops depending on things only a chat session has: `input()` and `print` are used only by the
agent's one-call tools, and provenance in the knowledge store is recorded only when there is an `Interaction`. The
role and mode check (`check_access`) now runs at the top of every entry point, not only in the agent's `handle()`,
so a front end that calls `prepare_*` or `commit_*` directly can't skip it. `Procurement(session, source="ui")`
selects the front end; anything other than `"agent"` or `"ui"` is refused, in Python and again in the Cypher.

## Model change: `$source`

The three governed templates wrote the literal `Source: "agent"`. They now take a `$source` parameter (and write
nothing unless it's `"agent"` or `"ui"`); the agent passes `"agent"`, the API `"ui"`. The GRAPH TYPE declares
`Source :: STRING` with no allowed values, so the schema doesn't change and no data upgrade is needed. The "where
people changed the recommendation" query widens from `Source = "agent"` to `Source IN ["agent", "ui"]`.

**Decided: the version stays v2.3.3.** Existing knowledge stores (the Colab one on Google Drive, too) held the old
template text, and the notebooks only rebuilt when the model version changed. The store now records a hash of the
five files it's built from (`modelHash`); the notebooks rebuild when it differs (`needs_rebuild`), and the terminal
agent prints a note to run `build_kb.py`. Learned knowledge is kept, as on every rebuild. The hash ignores line
endings, so a Windows checkout and Colab agree. The import script's line ranges in the README (109–1186, 1286–1349)
are unchanged.

## API

Server-side session (in memory; a POC), keyed by a cookie. The session holds the `Procurement` instance, because
recommendations are stateful: a write is checked against the last recommendation.

| Method and path | Does | Wraps |
|---|---|---|
| `POST /api/session` `{employeeId}` | Demo sign-in: name, roles, mode, whether PO tools are allowed | `aura.identity` + `Procurement.allowed` |
| `GET /api/status` | Mode, approval limits, whether the PO loops look active | `_limits`, `loops_running` |
| `GET /api/restock` | Recommended POs per Supplier, level each needs, totals | `recommend_restock` |
| `GET /api/resubmissions` | Rejected POs: who, level, why, what's still needed | `recommend_resubmissions` |
| `POST /api/purchase-orders/preview` | Validate + cost + level + flags; writes nothing | `prepare_create` |
| `POST /api/purchase-orders` | Commit a previewed batch | `commit_create` |
| `POST /api/resubmissions/preview`, `POST /api/resubmissions` | Same for resubmissions | `prepare_resubmit`, `commit_resubmit` |
| `POST /api/cancellations/preview`, `POST /api/cancellations` | Same for cancellations | `prepare_cancel`, `commit_cancel` |
| `GET /api/demand?products=...` | Recent demand and the cover-based suggestion per product (also folded into `/api/restock` and `/api/resubmissions`) | the *Recent demand* template |
| `POST /api/justification-draft` | A Claude draft from the facts sent with it; writes nothing | Anthropic SDK |
| `GET /api/audit` | POs by `Source`, and where people changed the recommendation | a read template |

Commit takes the preview's id, so what's written is exactly what the person saw.

**Identity:** a picker of employees, standing in for a login, like `--as-employee`. Documented as demo-only.

**Templates:** tested: relate 1.0.1 refuses any other connection, even read-only, while a process has the store
open for writing (`storage locked`). The API runs next to the agent, so it doesn't open the knowledge store at all:
`kb/model_templates.py` reads the templates from the import script with the same parser `build_kb.py` uses, behind
the same `template_by_title` interface. A test checks that both give byte-identical Cypher.

## Behind the scenes: AI drafts and demand suggestions

No chat in the UI. Two kinds of help appear on the Restock and Rejected POs screens, both advisory: the person still
sets every quantity and writes (or accepts) every justification, and confirms every write.

**Justification drafts (Claude).** A *Suggest* button next to each justification box asks Claude for a short draft,
built only from facts the screen already has: the recommendation's lines (stock, threshold, what's on order, open
customer orders), the demand figures below and, for a resubmission, the rejecter's level and comment. The prompt
forbids anything not in those facts. On request, never pre-filled, so writing your own reason stays the default.
**Only the submitted text is recorded** (`Justification`), as today: no model change. The API needs
`ANTHROPIC_API_KEY` from `.env`; without it the button is hidden.

**Demand suggestions (Cypher, with an optional Claude sentence).** A new read template, *Recent demand for products*,
returns per product: units ordered by customers in the last *N* days (all orders, open or fulfilled, by `OrderDate`),
the daily rate, and days of cover after the recommended PO arrives:

- The rate is units divided by the time actually covered by orders in the window, so a simulation that has run for a
  few hours isn't averaged over a full week of nothing.
- If cover after the PO is below a target, the suggestion is the quantity that reaches it, with the PO's new
  estimated cost and **the approval level it would then need** (raising a quantity can move a PO from L1 to L2; the
  UI says so, and never suggests splitting).
- Defaults: a 7-day window and a 7-day cover target, set in `.env` (`DEMAND_WINDOW_DAYS`, `DEMAND_COVER_DAYS`).
- The numbers come from the Cypher; Claude only turns them into one sentence ("Chai sold about 40 units a day this
  week; 55 covers 2 days. 280 would cover 7 and moves the PO to L2."). Without an API key, a plain templated
  sentence is shown instead.
- `RecommendedQt` stays the loop's rule, so the audit still shows the person raised the quantity, and why, in their
  justification.

This is live analytics on Aura, not a simulation: it doesn't need `relate pull`. The template also lands in the
knowledge store, so the agent can answer "what's the recent demand for Chai?" with it for free. Demand in the
simulation is whatever the Customer Order loop's rate makes it, so suggestions follow that setting.

## Screens

1. **Sign in:** pick a Procurement Assistant (EmployeeID 16, 17 or 18). A banner shows the mode and, if the PO
   Creation loop looks active, why writing is blocked.
2. **Restock:** one card per Supplier: products, recommended quantity (editable), estimated cost, the approval level
   the PO will need (recomputed as quantities change), the demand suggestion per product, a required justification
   with a *Suggest* button. Include/exclude per PO. *Review* →
   confirmation dialog with the flags → *Create*. Results show what was created and any line left out because it was
   no longer needed.
3. **Rejected POs:** who rejected each, at which level and why, what's still needed now. Per PO: *Resubmit* (editable
   quantities + justification) or *Cancel* (reason). Same review step.
4. **Audit:** POs created, resubmitted and cancelled, filterable by `Source` (simulation, agent, ui), with the
   recommended vs. ordered quantity and the justification.

No "split this PO" control exists, matching the agent's refusal.

## Running all three at once

The loops (agents mode), the agent and the UI can run together. Two people ordering the same need at the same time
is already handled in the Cypher: the create template locks the products and recomputes the need, so the second PO
leaves the covered line out and reports it. That makes a good demo, with the audit screen showing all three sources.

## Testing

- `tests/test_procurement_offline.py`: the 43 agent checks unchanged, plus 12 for this design (55 in all): prepare
  writes nothing, commit writes `Source: "ui"`, the Cypher refuses an unknown source, commit re-checks the loop
  guard, resubmit and cancel from the UI, role checks in prepare and commit, model templates = store templates, and
  the rebuild trigger. **Done.**
- `tests/test_procurement_api.py` (38 checks, **done**): FastAPI's test client against the relate stand-in for Aura used by the other
  offline tests: sign-in and role checks, preview vs. commit, refusal when the loop is active, `Source: "ui"`
  written, a stale preview rejected.
- UI: a build check and a short manual test script against a live Aura instance.

## Layout

```
Neo4jRelate/
  api/            FastAPI app (main.py), sessions, request/response models
  ui/             Vite + React + TypeScript app
  agent/procurement.py   prepare/commit split, $source
```

## Out of scope

Real authentication, deployment, the vetting agents, any change to the business rules, a chat interface, storing
AI drafts.
