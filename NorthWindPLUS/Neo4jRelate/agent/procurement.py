"""
Procurement Assistant tools (model v2.3.3): recommend restocking and resubmissions, then create, resubmit or cancel POs.

Offered only to an employee holding the "Procurement Assistant" role. The recommendations are read templates with the
same rules and formulas as the simulation loops they replace. The writes are the governed templates from the import
script's **Procurement Assistant** section: fixed Cypher that re-checks the role, locks the products, recomputes what
is still needed, and records Date, Justification, Source:"agent" and RecommendedQt. A person confirms every write.

Guard rails here, in code (the Cypher repeats the ones that matter):
  - recommend before writing: create/resubmit need a recommendation from this session (the write re-checks anyway);
  - one justification per PO, required;
  - one PO per Supplier per batch: splitting a PO to fit under a lower approval limit isn't allowed;
  - quantities far from the recommendation (over 3x or under a third) are flagged in the confirmation.
"""
from __future__ import annotations

ROLE = "Procurement Assistant"
RESTOCK_TITLE = "Restock recommendation"
RESUBMISSION_TITLE = "Resubmission recommendation"
CREATE_TITLE = "Create a Purchase Order (governed)"
RESUBMIT_TITLE = "Resubmit a rejected Purchase Order (governed)"
CANCEL_TITLE = "Cancel a rejected Purchase Order (governed)"
LARGE_CHANGE = 3.0
LOOP_WINDOW_MINUTES = 3     # the PO Creation loop runs once a minute: any simulated PO this recent means it's still on

# Is a simulation loop still doing this job? (SIMULATION_MODE=agents expects the PO Creation loop stopped and the PO
# Vetting loop started with --no-resubmit; run_loops_agents.bat does both.)
LOOP_CHECK = """OPTIONAL MATCH (:PurchaseOrder)-[c:PO_CREATED_BY {Source:"simulation"}]->(:Employee)
WHERE c.Date > datetime() - duration({minutes: $m})
WITH count(c) AS created
OPTIONAL MATCH (:PurchaseOrder)-[h:HAS_PREVIOUS_PO {Source:"simulation"}]->(:PurchaseOrder)
WHERE h.Date > datetime() - duration({minutes: $m})
RETURN created, count(h) AS resubmitted"""

LIMITS = """MATCH (l1:RolE {Title:"Level1Approver"}), (l2:RolE {Title:"Level2Approver"}), (l3:RolE {Title:"Level3Approver"})
RETURN l1.ApprovalLimit AS l1, l2.ApprovalLimit AS l2, l3.ApprovalLimit AS l3"""

_ITEMS = {"type": "array", "items": {"type": "object", "properties": {
    "productId": {"type": "string"}, "qty": {"type": "integer", "description": "Whole number of units, above 0."}},
    "required": ["productId", "qty"]}}

TOOLS = [
    {
        "name": "recommend_restock",
        "description": ("Procurement Assistant: which available products need a new PO now, grouped by Supplier, with the "
                        "recommended quantity (the simulation's own rule), estimated cost and the approval level each PO "
                        "will need. Read-only. Run it before create_purchase_orders."),
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "recommend_resubmissions",
        "description": ("Procurement Assistant: rejected POs not yet resubmitted or cancelled -- who rejected each, at which "
                        "level and why -- and what is still needed now (recommended quantities). A PO with nothing still "
                        "needed is a candidate for cancelling. Read-only."),
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "create_purchase_orders",
        "description": ("Procurement Assistant: create the POs the user accepted, one per Supplier, each with the user's "
                        "justification. Quantities may differ from the recommendation. Shows the final list and asks the "
                        "user to confirm (a prompt under the notebook cell, or in the terminal) before anything is written. "
                        "Lines no longer needed when written are left out and reported."),
        "input_schema": {"type": "object", "properties": {"purchaseOrders": {"type": "array", "items": {
            "type": "object", "properties": {
                "supplierId": {"type": "string"}, "items": _ITEMS,
                "justification": {"type": "string", "description": "The user's reason for this PO, in their words."}},
            "required": ["supplierId", "items", "justification"]}}}, "required": ["purchaseOrders"]},
    },
    {
        "name": "resubmit_purchase_orders",
        "description": ("Procurement Assistant: resubmit rejected POs as new POs (same Supplier, products from the rejected "
                        "PO), each with the user's justification. Confirmation as for create_purchase_orders."),
        "input_schema": {"type": "object", "properties": {"resubmissions": {"type": "array", "items": {
            "type": "object", "properties": {
                "rejectedPO": {"type": "string"}, "items": _ITEMS,
                "justification": {"type": "string", "description": "Why it's resubmitted and what changed, in the user's words."}},
            "required": ["rejectedPO", "items", "justification"]}}}, "required": ["resubmissions"]},
    },
    {
        "name": "cancel_rejected_purchase_orders",
        "description": ("Procurement Assistant: cancel rejected POs that shouldn't be resubmitted (they move to "
                        "CancelledPoS), each with the user's reason. Asks the user to confirm first."),
        "input_schema": {"type": "object", "properties": {"cancellations": {"type": "array", "items": {
            "type": "object", "properties": {
                "rejectedPO": {"type": "string"},
                "justification": {"type": "string", "description": "Why it's cancelled, in the user's words."}},
            "required": ["rejectedPO", "justification"]}}}, "required": ["cancellations"]},
    },
]
NAMES = {t["name"] for t in TOOLS}

RULES = """
Procurement Assistant work (this user holds the role):
- "What needs restocking?" -> recommend_restock. Present the POs as a numbered list: Supplier, products with
  recommended quantities, estimated cost, and the approval level each PO will need.
- The user accepts all, some, or changes quantities ("accept 1 and 3; for 2 make Chai 50"). Ask for one
  justification per PO if they haven't given one; use their words. Then call create_purchase_orders with only the
  accepted POs. It shows the final list and asks the user to confirm; nothing is written before that.
- Rejected POs -> recommend_resubmissions. For each, the user resubmits (resubmit_purchase_orders, with recomputed
  quantities they may change) or cancels (cancel_rejected_purchase_orders), each with a justification.
- Never suggest splitting a PO, or trimming quantities, to fit under a lower approval limit; decline if asked.
  Splitting POs to avoid an approval level is a procurement control failure. Show the level a PO needs, nothing more.
- If a quantity is far from the recommendation, say so and make sure the justification explains it.
- After writing, report the PO numbers, any lines left out (and why), and the approval level each PO goes to.
"""


class Procurement:
    """Bound to a Session: uses its Aura connection, knowledge store, confirmation prompt and interaction id."""

    def __init__(self, session):
        self.s = session
        kb = session.kb
        self.t_restock = kb.template_by_title(RESTOCK_TITLE)
        self.t_resub = kb.template_by_title(RESUBMISSION_TITLE)
        self.t_create = kb.template_by_title(CREATE_TITLE)
        self.t_resubmit = kb.template_by_title(RESUBMIT_TITLE)
        self.t_cancel = kb.template_by_title(CANCEL_TITLE)
        self.restock: dict[str, dict] = {}        # supplierId -> {"supplier", "lines": {productId: line}}
        self.resub: dict[str, dict] = {}          # rejected PONumber -> recommendation row

    def allowed(self) -> bool:
        """The tools are offered to a Procurement Assistant, and only in SIMULATION_MODE=agents. In full mode the
        simulation's own loops create and resubmit POs, and the agent must not compete with them."""
        return ROLE in self.s.user["roles"] and self.s.mode == "agents"

    def loops_running(self) -> dict:
        """Simulated POs created or resubmitted in the last few minutes: the loop this agent replaces is still on."""
        rows = self.s.aura.read(LOOP_CHECK, {"m": LOOP_WINDOW_MINUTES}).get("rows") or [{}]
        return {"created": rows[0].get("created") or 0, "resubmitted": rows[0].get("resubmitted") or 0}

    def _loop_refusal(self, job: str) -> dict | None:
        running = self.loops_running()
        n = running["created" if job == "create" else "resubmitted"]
        if not n:
            return None
        loop = "PO Creation loop" if job == "create" else "PO Vetting loop's resubmission (po_resubmit)"
        fix = ("stop it; run_loops_agents.bat doesn't start it" if job == "create"
               else "restart the PO Vetting loop with --no-resubmit, as run_loops_agents.bat does")
        return {"refused": f"The {loop} still seems to be running: the simulation wrote {n} in the last "
                           f"{LOOP_WINDOW_MINUTES} minutes. Two writers would order the same need twice, so {fix}, "
                           f"then try again in a few minutes."}

    def handle(self, name: str, args: dict) -> dict:
        if ROLE not in self.s.user["roles"]:
            return {"refused": f"{self.s.user['name']} does not hold the {ROLE} role, so procurement tools can't be "
                               f"used in this session."}
        if self.s.mode != "agents":
            return {"refused": "SIMULATION_MODE is 'full': the simulation's loops create and resubmit POs. Set "
                               "SIMULATION_MODE=agents and run run_loops_agents.bat to hand those jobs to the agent."}
        return getattr(self, name)(args)

    # ---------------- recommendations ----------------

    def recommend_restock(self, args: dict) -> dict:
        result = self.s.aura.read(self.t_restock["cypher"])
        if (warning := self._loop_refusal("create")):
            result["warning"] = warning["refused"] + " Recommendations shown, but POs can't be created until then."
        if "rows" in result:
            self.restock = {r["SupplierID"]: {"supplier": r["Supplier"], "lines": {l["ProductID"]: l for l in r["Lines"]}}
                            for r in result["rows"]}
            self.s.kb.record_use(self.s.interaction_id, self.t_restock["name"])
        return result

    def recommend_resubmissions(self, args: dict) -> dict:
        result = self.s.aura.read(self.t_resub["cypher"])
        if (warning := self._loop_refusal("resubmit")):
            result["warning"] = warning["refused"] + " Recommendations shown, but POs can't be resubmitted until then."
        if "rows" in result:
            self.resub = {r["RejectedPO"]: r for r in result["rows"]}
            self.s.kb.record_use(self.s.interaction_id, self.t_resub["name"])
        return result

    # ---------------- shared checks and display ----------------

    @staticmethod
    def _bad_items(items: list[dict]) -> str | None:
        if not items:
            return "a PO needs at least one line"
        for it in items:
            q = it.get("qty")
            if not isinstance(q, int) or isinstance(q, bool) or q <= 0:
                return f"quantity for product {it.get('productId')} must be a whole number above 0 (got {q!r})"
        if len({it["productId"] for it in items}) != len(items):
            return "a product appears twice on the same PO"
        return None

    def _level(self, cost: float | None, limits: dict) -> str:
        if cost is None:
            return "unknown (a line wasn't in the recommendation)"
        for lvl in ("l1", "l2", "l3"):
            if cost <= limits[lvl]:
                return lvl.upper()
        return "above the L3 limit: no level can approve it"

    def _lines(self, items: list[dict], recommended: dict[str, dict]) -> tuple[list[dict], float | None, list[str]]:
        """Each requested line with its recommendation, cost estimate and flags."""
        lines, total, flags = [], 0.0, []
        for it in items:
            rec = recommended.get(it["productId"])
            rq = rec.get("RecommendedQt") if rec else None
            unit = (rec.get("UnitCost") or (rec.get("LineCost", 0) / rq if rq else None)) if rec else None
            line = {"productId": it["productId"], "product": rec.get("Product") if rec else f"product {it['productId']}",
                    "qty": it["qty"], "recommendedQt": rq if rq else None}
            if not rq:
                flags.append(f"{line['product']}: not in the current recommendation (it will be left out if it isn't needed)")
            elif it["qty"] > LARGE_CHANGE * rq or it["qty"] * LARGE_CHANGE < rq:
                flags.append(f"{line['product']}: {it['qty']} vs {rq} recommended ({it['qty'] / rq:.1f}x)")
            if unit is None or total is None:
                total = None
            else:
                total += unit * it["qty"]
            lines.append(line)
        return lines, (round(total, 2) if total is not None else None), flags

    def _limits(self) -> dict:
        rows = self.s.aura.read(LIMITS).get("rows") or [{}]
        return rows[0]

    def _show(self, header: str, entries: list[dict]) -> None:
        print(f"\n  >>> {header}")
        for i, e in enumerate(entries, 1):
            print(f"      {i}. {e['title']}  |  est. {e['cost'] if e['cost'] is not None else '?'}  |  needs {e['level']}")
            for l in e.get("lines", []):
                rec = f" (recommended {l['recommendedQt']})" if l["recommendedQt"] not in (None, l["qty"]) else ""
                print(f"         - {l['product']}: {l['qty']}{rec}")
            for f in e.get("flags", []):
                print(f"         ! {f}")
            print(f"         Justification: {e['justification']}")

    # ---------------- writes ----------------

    def create_purchase_orders(self, args: dict) -> dict:
        pos = args.get("purchaseOrders") or []
        if not pos:
            return {"refused": "No POs given."}
        if not self.restock:
            return {"refused": "Run recommend_restock first, so the POs are checked against the current recommendation."}
        if (refusal := self._loop_refusal("create")):
            return refusal
        suppliers = [p["supplierId"] for p in pos]
        if len(set(suppliers)) != len(suppliers):
            return {"refused": "One PO per Supplier per batch. Splitting a Supplier's order into several POs (for example "
                               "to stay under a lower approval limit) isn't allowed; combine the lines into one PO."}
        limits, entries = self._limits(), []
        for p in pos:
            if not (p.get("justification") or "").strip():
                return {"refused": f"PO for Supplier {p['supplierId']} has no justification. Ask the user for one."}
            if (bad := self._bad_items(p["items"])):
                return {"refused": f"PO for Supplier {p['supplierId']}: {bad}."}
            rec = self.restock.get(p["supplierId"], {})
            lines, cost, flags = self._lines(p["items"], rec.get("lines", {}))
            entries.append({"title": f"New PO for {rec.get('supplier', 'Supplier ' + p['supplierId'])}", "lines": lines,
                            "cost": cost, "level": self._level(cost, limits), "flags": flags,
                            "justification": p["justification"].strip(), "p": p})
        self._show(f"Create {len(entries)} purchase order(s) as {self.s.user['name']}:", entries)
        if not self.s.confirm("      Create them? [y/N] "):
            return {"refused": "The user did not confirm. Nothing was written."}
        created, left_out = [], []
        for e in entries:
            p = e["p"]
            items = [{"productId": l["productId"], "qty": l["qty"], "recommendedQt": l["recommendedQt"]} for l in e["lines"]]
            r = self.s.aura.run_governed(self.t_create["cypher"], {
                "requesterId": self.s.employee_id, "supplierId": p["supplierId"], "items": items,
                "justification": e["justification"]})
            if "error" in r:
                return {"error": r["error"], "created": created, "left_out": left_out}
            row = (r.get("rows") or [None])[0]
            written = set(row["ProductIDs"]) if row else set()
            for l in e["lines"]:
                if l["productId"] not in written:
                    left_out.append({"supplierId": p["supplierId"], "product": l["product"],
                                     "reason": "not needed any more (already covered by a PO, above the restock threshold, "
                                               "not supplied by this Supplier, or not available)"})
            if row:
                created.append({**row, "supplierId": p["supplierId"], "approvalLevel": self._level(row["EstimatedCost"], limits)})
        if created:
            self.s.kb.record_use(self.s.interaction_id, self.t_create["name"])
            self.restock = {}            # stale now: ask for a fresh recommendation before the next batch
        return {"created": created, "left_out": left_out}

    def resubmit_purchase_orders(self, args: dict) -> dict:
        subs = args.get("resubmissions") or []
        if not subs:
            return {"refused": "No resubmissions given."}
        if not self.resub:
            return {"refused": "Run recommend_resubmissions first."}
        if (refusal := self._loop_refusal("resubmit")):
            return refusal
        limits, entries = self._limits(), []
        for sbm in subs:
            rec = self.resub.get(sbm["rejectedPO"])
            if not rec:
                return {"refused": f"{sbm['rejectedPO']} isn't in the current resubmission recommendation."}
            if not (sbm.get("justification") or "").strip():
                return {"refused": f"{sbm['rejectedPO']} has no justification. Ask the user for one."}
            if (bad := self._bad_items(sbm["items"])):
                return {"refused": f"{sbm['rejectedPO']}: {bad}."}
            recd = {l["ProductID"]: l for l in rec["Lines"]}
            lines, cost, flags = self._lines(sbm["items"], recd)
            entries.append({"title": f"Resubmit {sbm['rejectedPO']} ({rec['Supplier']})", "lines": lines, "cost": cost,
                            "level": self._level(cost, limits), "flags": flags,
                            "justification": sbm["justification"].strip(), "p": sbm})
        self._show(f"Resubmit {len(entries)} rejected PO(s) as {self.s.user['name']}:", entries)
        if not self.s.confirm("      Resubmit them? [y/N] "):
            return {"refused": "The user did not confirm. Nothing was written."}
        done, left_out, refused = [], [], []
        for e in entries:
            items = [{"productId": l["productId"], "qty": l["qty"], "recommendedQt": l["recommendedQt"]} for l in e["lines"]]
            r = self.s.aura.run_governed(self.t_resubmit["cypher"], {
                "requesterId": self.s.employee_id, "rejectedPO": e["p"]["rejectedPO"], "items": items,
                "justification": e["justification"]})
            if "error" in r:
                return {"error": r["error"], "resubmitted": done, "left_out": left_out}
            row = (r.get("rows") or [None])[0]
            if not row:
                refused.append({"rejectedPO": e["p"]["rejectedPO"], "reason": "nothing written: the PO was already resubmitted "
                                "or cancelled, or none of its lines is still needed"})
                continue
            written = set(row["ProductIDs"])
            left_out += [{"rejectedPO": e["p"]["rejectedPO"], "product": l["product"], "reason": "not needed any more"}
                         for l in e["lines"] if l["productId"] not in written]
            done.append({**row, "approvalLevel": self._level(row["EstimatedCost"], limits)})
        if done:
            self.s.kb.record_use(self.s.interaction_id, self.t_resubmit["name"])
        self.resub = {}
        return {"resubmitted": done, "left_out": left_out, "not_resubmitted": refused}

    def cancel_rejected_purchase_orders(self, args: dict) -> dict:
        cancels = args.get("cancellations") or []
        if not cancels:
            return {"refused": "No cancellations given."}
        for c in cancels:
            if not (c.get("justification") or "").strip():
                return {"refused": f"{c['rejectedPO']} has no justification. Ask the user for one."}
        entries = [{"title": f"Cancel {c['rejectedPO']}", "cost": None, "level": "-", "justification": c["justification"].strip(),
                    "lines": [], "flags": []} for c in cancels]
        self._show(f"Cancel {len(entries)} rejected PO(s) as {self.s.user['name']}:", entries)
        if not self.s.confirm("      Cancel them? [y/N] "):
            return {"refused": "The user did not confirm. Nothing was written."}
        done, refused = [], []
        for c in cancels:
            r = self.s.aura.run_governed(self.t_cancel["cypher"], {
                "requesterId": self.s.employee_id, "rejectedPO": c["rejectedPO"], "justification": c["justification"].strip()})
            if "error" in r:
                return {"error": r["error"], "cancelled": done}
            if r.get("rows"):
                done.append(c["rejectedPO"])
            else:
                refused.append({"rejectedPO": c["rejectedPO"], "reason": "not in RejectedPoS, or already resubmitted"})
        if done:
            self.s.kb.record_use(self.s.interaction_id, self.t_cancel["name"])
        return {"cancelled": done, "not_cancelled": refused}
