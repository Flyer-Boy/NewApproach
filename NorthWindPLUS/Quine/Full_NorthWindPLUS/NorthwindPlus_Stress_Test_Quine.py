#!/usr/bin/env python3
"""
NorthWind PLUS Concurrency Stress Harness -- Quine edition
===========================================================

Port of NorthwindPlus_Stress_Test.py (Neo4j) to Quine 2.1.x and the v2.4
model (no properties on edges). Same six loops, same weights, same
"check which actions are eligible, pick one by weight, execute it on ONE
item" design, same per-loop summary. What changed underneath:

  * Transport: Quine's REST API (POST /api/v2/graph/quine/cypher:query,
    body {"text": ..., "parameters": {}}) via the Python standard library.
    No driver, no pip install.
  * Model: v2.4. Line items are nodes (OrderItem / POItem / RFQItem), every
    vetting / delivery / payment / fulfillment is a decision or event node,
    state edges carry no properties.
  * Identity: proper-noun nodes and Collections are addressed by Quine's
    deterministic ids exactly as the batch loader created them, e.g.
    idFrom("NewPoS"), idFrom("RolE", "Buyer"). Queries start from those
    anchors instead of scanning labels.
  * Counters: UnitsInStock / UnitsOnOrder change only through Quine's atomic
    int.add(), so the loops cannot lose each other's updates.
  * LowStock: the reorder verdict is a position -- products at their reorder
    point are members of the LowStocK Collection, re-evaluated by every action
    that changes their stock, POs in flight or open-order demand. po-creation
    works from it. State edges (NewPoS, PoNewRFQ) are written LAST, after the
    items, so a future standing query never fires on a half-written PO/RFQ.
  * Numbers (CO-, PO-, RFQ-, SH-): Quine has no randomUUID(); the new node's
    own id, strId(n), is used instead.
  * No apoc.lock and no transactions in Quine. Every execute query still
    re-checks its own "not yet done" guard right before writing (the part of
    your lock + re-check fix that does not need a lock). Each loop runs on a
    single thread, and the six loops work on different stages of the
    pipeline, so the races you saw on Neo4j (two copies of the SAME loop
    picking the same PO/order) cannot happen here -- as long as you run ONE
    copy of each loop. Counters are atomic regardless.
  * Quine 2.1.1 quirk (found while testing this port): a pattern predicate
    such as WHERE NOT (po)-[:X]->() placed on a WITH that follows ORDER BY /
    LIMIT or an aggregation always evaluates to false, silently. The same
    predicate right after a MATCH works. So every re-check guard below is
    written as  MATCH (po) WHERE NOT (po)-[:X]->()  (re-binding the node
    already in hand), never as  WITH ... WHERE NOT (po)-[:X]->().
    Keep that in mind for any query you move into a standing query.

Two modes:
    --mode sq      with the standing queries registered (register-standing-queries.sh):
                   only the outside world runs here -- customer-order, order-fulfillment,
                   rfq-submission (suppliers), rfq-fulfillment (goods arrive), and the slow
                   threshold-recalibration job. Reorder, vetting, submission, RFQ vetting and
                   closure happen inside Quine as standing queries.
    --mode loops   the original six loops, no standing queries.
    (default --mode auto: sq if the nw-* standing queries are registered, else loops)

Run every loop of the mode in one process (labelled, combined log; Ctrl+C stops all):
    python3 NorthwindPlus_Stress_Test_Quine.py --check
    python3 NorthwindPlus_Stress_Test_Quine.py --rates customer-order=12,rfq-submission=8 --check

Or one loop on its own, exactly like the original:
    python3 NorthwindPlus_Stress_Test_Quine.py --loop customer-order --rate 6

Options:
    --mode M           sq | loops | auto (see above)
    --loop NAME        run only this loop (default: every loop of the mode)
    --rate N           executions per minute for --loop (default 6)
    --rates a=N,b=N    per-loop rates (defaults below; 0 disables a loop)
    --overprice F      sq mode: share of RFQs quoted above budget (default 0.15)
    --duration S       stop after S seconds
    --check            when the loops stop, run the data-quality invariants
    --check-only       just run the invariants and exit
    --quine URL        Quine base URL (default $QUINE_URL or http://localhost:8080)

The graph must already be loaded with northwind-plus-quine-batch.sh (which
creates the LowStocK Collection).

Why this file is still small: same reason as the original. Every threshold
and approval limit lives on RolE.ApprovalBase / ApprovalLimit in the graph;
the Collections are the state machine. This file only picks a rate, sends
one Cypher statement, retries on transport errors and logs the result. Each
action is a name, a weight and two strings of Cypher -- which is also the
shape a Quine standing query takes, if you later move one of them into a
recipe (eligibility pattern -> standing query pattern, execute query ->
its output's Cypher).
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import random
import signal
import sys
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Callable

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)-23s] %(levelname)-7s %(message)s",
    datefmt="%H:%M:%S",
)

# Executions per minute. "loops": the original six (no standing queries).
# "sq": the outside world only -- the company's own steps (reorder, vetting,
# submission, RFQ vetting, closure) run as standing queries inside Quine
# (register-standing-queries.sh).
DEFAULT_RATES = {
    "loops": {
        "customer-order": 6,
        "po-creation": 2,
        "po-vetting": 4,
        "rfq-vetting": 4,
        "warehouse-finance": 4,
        "order-fulfillment": 4,
    },
    "sq": {
        "customer-order": 6,
        "order-fulfillment": 4,
        "rfq-submission": 4,
        "rfq-fulfillment": 4,
        "threshold-recalibration": 0.2,     # the slow job: every 5 minutes
    },
}

# Parameters every action query may use. overprice: share of RFQs a supplier
# quotes above the PO budget (sq mode; the RFQ standing query rejects those by
# rule and the supplier resubmits at a better price). 0 in loops mode.
ACTION_PARAMS = {"overprice": 0.0}


# ---------------------------------------------------------------------------
# Quine REST client + retry wrapper
# ---------------------------------------------------------------------------

class CypherError(Exception):
    """Quine rejected the query (compile/runtime error): not worth retrying."""


class TransientQuineError(Exception):
    """Transport-level failure (timeout, 5xx, connection refused): retry."""


class Quine:
    def __init__(self, base_url: str, timeout_s: int = 120):
        self.base_url = base_url.rstrip("/")
        self.timeout_s = timeout_s
        self.endpoint = f"{self.base_url}/api/v2/graph/quine/cypher:query?timeout={timeout_s}s"

    def query(self, text: str, params: dict | None = None) -> list[dict]:
        body = json.dumps({"text": text, "parameters": params or {}}).encode("utf-8")
        req = urllib.request.Request(self.endpoint, data=body, method="POST",
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s + 10) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")
            try:
                detail = json.loads(detail)["error"]["message"]
            except Exception:
                pass
            if 400 <= exc.code < 500:
                raise CypherError(f"HTTP {exc.code}: {detail}") from None
            raise TransientQuineError(f"HTTP {exc.code}: {detail}") from None
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            raise TransientQuineError(str(exc)) from None
        cols = payload.get("columns", [])
        return [dict(zip(cols, row)) for row in payload.get("results", [])]

    def build_info(self) -> dict:
        with urllib.request.urlopen(f"{self.base_url}/api/v1/admin/build-info", timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))


@dataclass
class RunStats:
    executions: int = 0
    retries: int = 0
    errors: int = 0
    no_op: int = 0          # executions where the query ran but matched nothing
    start_time: float = field(default_factory=time.perf_counter)
    actions: dict = field(default_factory=dict)   # action name -> times executed


def execute_with_retry(q: Quine, work_fn: Callable[[Quine], object], stats: RunStats,
                       log: logging.Logger, max_retries: int = 5):
    """Runs work_fn(q). Retries transport errors with exponential backoff and
    counts them, like the original counted Neo4j TransientErrors. A Cypher
    error is logged and counted once -- retrying the same text cannot help."""
    attempt = 0
    while True:
        try:
            return work_fn(q)
        except TransientQuineError as exc:
            attempt += 1
            stats.retries += 1
            if attempt > max_retries:
                log.error(f"Gave up after {max_retries} retries: {exc}")
                stats.errors += 1
                return None
            wait = min(2 ** attempt * 0.1, 2.0) + random.uniform(0, 0.1)
            log.warning(f"Transient error (attempt {attempt}/{max_retries}), retrying in {wait:.2f}s: {exc}")
            time.sleep(wait)
        except CypherError as exc:
            log.error(f"Query error: {exc}")
            stats.errors += 1
            return None


# ---------------------------------------------------------------------------
# LowStock: the reorder verdict as a position
# ---------------------------------------------------------------------------
#
# A product is a member of the LowStocK Collection (IS_LOW_STOCK_PRODUCT edge)
# when   UnitsInStock + qty on active, not yet delivered POs
#        - qty on open customer orders - 0.5 x StockThreshold  <=  StockThreshold
# Every action that changes one of those inputs for a product re-evaluates
# exactly those products right after it writes: customer-order (demand up),
# order-fulfillment (stock and demand down), po-creation and po_resubmit (POs
# in flight up), l1/l2/l3_reject (POs in flight down), warehouse_delivery
# (stock up, POs in flight down). po-creation then works FROM LowStock. When
# you move PO creation into a standing query, its pattern is simply
# (:LowStocK)-[:IS_LOW_STOCK_PRODUCT]->(p:Product).

LOW_STOCK_EVAL_QUERY = """
MATCH (av), (ls) WHERE id(av) = idFrom("ProductStatusAvailablE") AND id(ls) = idFrom("LowStocK")
MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
WHERE p.ProductID IN $productIds
OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[:HAS_PO_ITEM]->(poi:POItem)-[:PO_ITEM_PRODUCT]->(p)
WHERE NOT (activePO)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH ls, p, r, i, sum(coalesce(poi.POqt, 0)) AS pending
OPTIONAL MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(oi:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
WITH ls, p, r, i, pending, sum(coalesce(oi.Quantity, 0)) AS openQty
WITH ls, p, i.UnitsInStock + pending - openQty - (r.StockThreshold * 0.5) <= r.StockThreshold AS low
OPTIONAL MATCH (ls)-[e:IS_LOW_STOCK_PRODUCT]->(p)
FOREACH (_ IN CASE WHEN low AND e IS NULL THEN [1] ELSE [] END | CREATE (ls)-[:IS_LOW_STOCK_PRODUCT]->(p))
FOREACH (_ IN CASE WHEN NOT low AND e IS NOT NULL THEN [1] ELSE [] END | DELETE e)
RETURN collect(CASE WHEN low AND e IS NULL THEN p.ProductName END) AS entered,
       collect(CASE WHEN NOT low AND e IS NOT NULL THEN p.ProductName END) AS left
"""


def reevaluate_low_stock(q: Quine, product_ids, stats: RunStats, log: logging.Logger) -> None:
    ids = sorted({str(p) for p in (product_ids or []) if p is not None})
    if not ids:
        return
    rows = execute_with_retry(q, lambda c: c.query(LOW_STOCK_EVAL_QUERY, {"productIds": ids}), stats, log)
    if rows:
        entered = [n for n in rows[0].get("entered") or [] if n]
        left = [n for n in rows[0].get("left") or [] if n]
        if entered:
            log.info(f"LowStock + {', '.join(entered)}")
        if left:
            log.info(f"LowStock - {', '.join(left)}")


# ---------------------------------------------------------------------------
# Loop: customer-order
# ---------------------------------------------------------------------------

CUSTOMER_ORDER_QUERY = """
MATCH (op), (cs), (sr), (av)
WHERE id(op) = idFrom("OrderStatusOpeN") AND id(cs) = idFrom("CustomerS")
  AND id(sr) = idFrom("RolE", "Sales Representative") AND id(av) = idFrom("ProductStatusAvailablE")
MATCH (sr)-[:IS_ACTIVE_ROLE]->(e:Employee)
WITH op, cs, av, e ORDER BY rand() LIMIT 1
MATCH (cs)-[:IS_CUSTOMER]->(c:Customer)
WITH op, av, e, c ORDER BY rand() LIMIT 1
CREATE (o:Order {OrderDate: datetime(), RequiredDate: datetime() + duration("P7D")})
SET o.OrderID = "CO-" + left(strId(o), 5) + right(strId(o), 5)
CREATE (op)-[:IS_OPEN_ORDER_STATE]->(o), (o)-[:HAS_ORDER_CUSTOMER]->(c), (o)-[:SOLD_BY]->(e)
WITH o, av
MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)
WITH o, p ORDER BY rand() LIMIT toInteger(round(rand() * 10 + 1))
WITH o, p, toInteger(round(rand() * 19) + 1) AS qty
CREATE (o)-[:HAS_ORDER_ITEM]->(:OrderItem {Quantity: qty, UnitPrice: p.UnitPrice, Discount: rand() * 0.07})-[:ORDER_ITEM_PRODUCT]->(p)
RETURN o.OrderID AS OrderID, p.ProductID AS ProductID, p.ProductName AS ProductName, qty AS Quantity
"""


def iterate_customer_order(q: Quine, stats: RunStats, log: logging.Logger) -> None:
    lines = execute_with_retry(q, lambda c: c.query(CUSTOMER_ORDER_QUERY), stats, log)
    if lines:
        items = ", ".join(f"{r['ProductName']} x{int(r['Quantity'])}" for r in lines)
        log.info(f"Created Order {lines[0]['OrderID']} ({len(lines)} line(s)): {items}")
        reevaluate_low_stock(q, [r["ProductID"] for r in lines], stats, log)
    else:
        stats.no_op += 1
        log.warning("Customer Order creation matched no eligible Employee/Customer/Product -- check base data")


# ---------------------------------------------------------------------------
# Weighted-action machinery (po-vetting, rfq-vetting, warehouse-finance)
# ---------------------------------------------------------------------------

@dataclass
class VettingAction:
    name: str
    weight: int
    eligibility_query: str   # returns a single EligibleCount column
    execute_query: str       # performs the mutation on ONE item; returns what it did


def _eligible_count(q: Quine, query: str) -> int:
    rows = q.query(query)
    return int(rows[0]["EligibleCount"]) if rows and rows[0].get("EligibleCount") else 0


def run_weighted_action(q: Quine, actions: list[VettingAction]):
    """Same as the original: check which actions have eligible candidates
    right now, pick one weighted by likelihood, execute it for a single item.
    (On Quine these are separate requests, not one transaction; the execute
    query re-checks its own guard, so a stale eligibility count just becomes
    a logged no-op.)"""
    eligible = [a for a in actions if _eligible_count(q, a.eligibility_query) > 0]
    if not eligible:
        return None
    chosen = random.choices(eligible, weights=[a.weight for a in eligible], k=1)[0]
    params = {k: v for k, v in ACTION_PARAMS.items() if "$" + k in chosen.execute_query}
    rows = q.query(chosen.execute_query, params)
    return (chosen.name, rows[0] if rows else None)


def iterate_weighted_actions(q: Quine, stats: RunStats, log: logging.Logger,
                             actions: list[VettingAction], empty_message: str) -> None:
    outcome = execute_with_retry(q, lambda c: run_weighted_action(c, actions), stats, log)
    if outcome is None:
        stats.no_op += 1
        log.info(empty_message)
        return
    action_name, details = outcome
    if details is None:
        stats.no_op += 1
        log.warning(f"Action '{action_name}' was eligible but matched nothing at execution time -- no-op")
        return
    stats.actions[action_name] = stats.actions.get(action_name, 0) + 1
    product_ids = details.pop("ProductIDs", None)
    log.info(f"[{action_name}] {details}")
    if product_ids:
        reevaluate_low_stock(q, product_ids, stats, log)


# ---------------------------------------------------------------------------
# Loop: po-vetting
# ---------------------------------------------------------------------------
#
# Same nine actions and weights as the original. L1 has no prerequisite;
# L2/L3 require the previous level's approval and must not already be vetted
# at their own level. KNOWN GAP kept from the original: a PO above
# Level3Approver's ApprovalLimit has no approval path and stays in NewPoS.

_NOT_VETTED = {
    "Level1Approver": "NOT (po)-[:HAS_L1_PO_APPROVAL|HAS_L1_PO_REJECTION]->()",
    "Level2Approver": "(po)-[:HAS_L1_PO_APPROVAL]->() AND NOT (po)-[:HAS_L2_PO_APPROVAL|HAS_L2_PO_REJECTION]->()",
    "Level3Approver": "(po)-[:HAS_L2_PO_APPROVAL]->() AND NOT (po)-[:HAS_L3_PO_APPROVAL|HAS_L3_PO_REJECTION]->()",
}
_LEVEL_TAG = {"Level1Approver": "L1", "Level2Approver": "L2", "Level3Approver": "L3"}

_COST_REJECT_L12 = "POCost > ro.ApprovalBase"
_COST_FINAL = "POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit"
_COST_PASSTHROUGH = "POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit"

_PO_COST = "sum(id.POqt * (i.UnitPrice * id.POPriceDiscount))"
_PO_ITEMS = "(np0)-[np:IS_NEW_PO_STATE]->(po:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)"


def _po_eligibility(level: str, cost: str) -> str:
    return f"""
    MATCH (np0), (ro) WHERE id(np0) = idFrom("NewPoS") AND id(ro) = idFrom("RolE", "{level}")
    MATCH {_PO_ITEMS}
    WHERE {_NOT_VETTED[level]}
    WITH po, ro, {_PO_COST} AS POCost
    WHERE {cost}
    RETURN count(po) AS EligibleCount
    """


# A rejection takes the PO out of the "in flight" quantity, so it returns its
# products for LowStock re-evaluation; approvals do not change that quantity.
_RETURN_WITH_PRODUCTS = """WITH po, POCost
    MATCH (po)-[:HAS_PO_ITEM]->(:POItem)-[:PO_ITEM_PRODUCT]->(x:Product)
    RETURN po.PONumber AS PONumber, round(POCost, 2) AS Cost, collect(x.ProductID) AS ProductIDs"""
_RETURN_PLAIN = "RETURN po.PONumber AS PONumber, round(POCost, 2) AS Cost"


def _po_execute(level: str, kind: str, cost: str) -> str:
    tag = _LEVEL_TAG[level]
    if kind == "passthrough":
        nxt = {"L1": "L2", "L2": "L3"}[tag]
        return f"""
        MATCH (ro), (np0) WHERE id(ro) = idFrom("RolE", "{level}") AND id(np0) = idFrom("NewPoS")
        MATCH (ro)-[:IS_ACTIVE_ROLE]->(l:Employee)
        WITH ro, np0, l ORDER BY rand() LIMIT 1
        MATCH {_PO_ITEMS}
        WHERE {_NOT_VETTED[level]}
        WITH ro, l, po, {_PO_COST} AS POCost
        WHERE {cost}
        WITH ro, l, po, POCost ORDER BY rand() LIMIT 1
        MATCH (po) WHERE {_NOT_VETTED[level]}
        CREATE (po)-[:HAS_{tag}_PO_APPROVAL]->(:VettingDecision {{Date: datetime(), Comment: "Approved by {tag}, passed to {nxt} (stress test)."}})-[:VETTED_BY]->(l)
        RETURN po.PONumber AS PONumber, round(POCost, 2) AS Cost
        """
    reject = kind == "reject"
    target = "RejectedPoS" if reject else "ApprovedPoS"
    rel = f"HAS_{tag}_PO_{'REJECTION' if reject else 'APPROVAL'}"
    state = "IS_REJECTED_PO_STATE" if reject else "IS_APPROVED_PO_STATE"
    verb = "Rejected" if reject else "Approved"
    return f"""
    MATCH (ro), (target), (np0)
    WHERE id(ro) = idFrom("RolE", "{level}") AND id(target) = idFrom("{target}") AND id(np0) = idFrom("NewPoS")
    MATCH (ro)-[:IS_ACTIVE_ROLE]->(l:Employee)
    WITH ro, target, np0, l ORDER BY rand() LIMIT 1
    MATCH {_PO_ITEMS}
    WHERE {_NOT_VETTED[level]}
    WITH ro, target, l, np, po, {_PO_COST} AS POCost
    WHERE {cost}
    WITH ro, target, l, np, po, POCost ORDER BY rand() LIMIT 1
    MATCH (po) WHERE {_NOT_VETTED[level]}
    CREATE (po)-[:{rel}]->(:VettingDecision {{Date: datetime(), Comment: "{verb} by {tag} (stress test)."}})-[:VETTED_BY]->(l),
           (target)-[:{state}]->(po)
    DELETE np
    {_RETURN_WITH_PRODUCTS if reject else _RETURN_PLAIN}
    """


_LOW_STOCK_ITEMS = """
    MATCH (rpo)-[:HAS_PO_ITEM]->(:POItem)-[:PO_ITEM_PRODUCT]->(p:Product)<-[:SUPPLIES]-(s),
          (av)-[:IS_AVAILABLE_PRODUCT]->(p),
          (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
    OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[:HAS_PO_ITEM]->(poi2:POItem)-[:PO_ITEM_PRODUCT]->(p)
    WHERE NOT (activePO)-[:HAS_WAREHOUSE_DELIVERY]->()
    WITH rpo, s, p, r, i, sum(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty
    OPTIONAL MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(op:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
    WITH rpo, s, p, r, i, AlreadyPendingQty, sum(coalesce(op.Quantity, 0)) AS OpenOrderQty
    WHERE i.UnitsInStock + AlreadyPendingQty - OpenOrderQty - (r.StockThreshold * 0.5) <= r.StockThreshold
"""

_REJECTED_NOT_RESUBMITTED = """
    MATCH (re), (av) WHERE id(re) = idFrom("RejectedPoS") AND id(av) = idFrom("ProductStatusAvailablE")
    MATCH (re)-[:IS_REJECTED_PO_STATE]->(rpo:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(s:Supplier)
    WHERE NOT ()-[:HAS_PREVIOUS_PO]->(rpo)
"""

PO_VETTING_ACTIONS: list[VettingAction] = [
    VettingAction("l1_reject", 1, _po_eligibility("Level1Approver", _COST_REJECT_L12), _po_execute("Level1Approver", "reject", _COST_REJECT_L12)),
    VettingAction("l1_approve_final", 5, _po_eligibility("Level1Approver", _COST_FINAL), _po_execute("Level1Approver", "final", _COST_FINAL)),
    VettingAction("l1_approve_passthrough", 5, _po_eligibility("Level1Approver", _COST_PASSTHROUGH), _po_execute("Level1Approver", "passthrough", _COST_PASSTHROUGH)),
    VettingAction("l2_reject", 1, _po_eligibility("Level2Approver", _COST_REJECT_L12), _po_execute("Level2Approver", "reject", _COST_REJECT_L12)),
    VettingAction("l2_approve_final", 5, _po_eligibility("Level2Approver", _COST_FINAL), _po_execute("Level2Approver", "final", _COST_FINAL)),
    VettingAction("l2_approve_passthrough", 5, _po_eligibility("Level2Approver", _COST_PASSTHROUGH), _po_execute("Level2Approver", "passthrough", _COST_PASSTHROUGH)),
    VettingAction("l3_reject", 1, _po_eligibility("Level3Approver", _COST_FINAL), _po_execute("Level3Approver", "reject", _COST_FINAL)),
    VettingAction("l3_approve_final", 5, _po_eligibility("Level3Approver", _COST_FINAL), _po_execute("Level3Approver", "final", _COST_FINAL)),
    VettingAction(
        "po_resubmit", 4,
        _REJECTED_NOT_RESUBMITTED + _LOW_STOCK_ITEMS + """
    RETURN count(DISTINCT rpo) AS EligibleCount
    """,
        # Picks among the rejected POs that still have low-stock products (the
        # original picked any rejected PO and could no-op); goes back to the
        # same Supplier via the rejected PO's own PO_FOR_SUPPLIER edge.
        _REJECTED_NOT_RESUBMITTED + _LOW_STOCK_ITEMS + """
    WITH rpo, s, collect({p: p, qty: r.StockThreshold - (i.UnitsInStock + AlreadyPendingQty - OpenOrderQty) + (r.StockThreshold / 2)}) AS orderItems
    WHERE size(orderItems) > 0
    WITH rpo, s, orderItems ORDER BY rand() LIMIT 1
    MATCH (rpo) WHERE NOT ()-[:HAS_PREVIOUS_PO]->(rpo)
    MATCH (rpo)-[:PO_CREATED_BY]->(e:Employee)
    MATCH (n) WHERE id(n) = idFrom("NewPoS")
    CREATE (po:PurchaseOrder {PODate: datetime()})
    SET po.PONumber = "PO-" + left(strId(po), 5) + right(strId(po), 5)
    CREATE (po)-[:PO_FOR_SUPPLIER]->(s), (po)-[:PO_CREATED_BY]->(e),
           (po)-[:HAS_PREVIOUS_PO]->(rpo),
           (po)-[:HAS_RESUBMISSION_NOTE]->(:ResubmissionNote {Justification: "Auto-resubmitted after rejection (stress test).", Date: datetime()})
    WITH n, po, rpo, orderItems
    UNWIND orderItems AS item
    WITH n, po, rpo, item.p AS p, item.qty AS qty
    CREATE (po)-[:HAS_PO_ITEM]->(:POItem {POqt: qty, POPriceDiscount: 0.7})-[:PO_ITEM_PRODUCT]->(p)
    WITH n, po, rpo, collect(p.ProductID) AS productIds
    CREATE (n)-[:IS_NEW_PO_STATE]->(po)
    RETURN po.PONumber AS PONumber, rpo.PONumber AS ResubmittedFrom, size(productIds) AS Items, productIds AS ProductIDs
    """,
    ),
]


def iterate_po_vetting(q: Quine, stats: RunStats, log: logging.Logger) -> None:
    iterate_weighted_actions(q, stats, log, PO_VETTING_ACTIONS,
                             "No eligible PO Vetting action this cycle (no NewPoS/RejectedPoS items awaiting action)")


# ---------------------------------------------------------------------------
# Loop: rfq-vetting
# ---------------------------------------------------------------------------
#
# Same five actions and weights. buyer_submit_po has no reject counterpart
# (design decision kept from the original). rfq_reject and rfq_approve share
# the budget-fit condition; the weights do the differentiating. rfq_approve
# also requires that the PO has no approved RFQ yet.

BUDGET_FITS_CONDITION = "poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost"

_NEW_RFQ_LINES = """
    MATCH (su) WHERE id(su) = idFrom("SubmittedPoS")
    MATCH (su)-[:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)
          -[:HAS_RFQ_ITEM]->(rfi:RFQItem)-[:RFQ_ITEM_PRODUCT]->(p:Product)<-[:PO_ITEM_PRODUCT]-(poi:POItem)<-[:HAS_PO_ITEM]-(po)
    WHERE """ + BUDGET_FITS_CONDITION

_NEW_PO_FOR_SUPPLIER = """
    MATCH (app) WHERE id(app) = idFrom("ApprovedSupplierS")
    MATCH (app)-[:IS_SUPPLIER_APPROVED_STATE]->(su:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp)-[r:IS_SUPPLIER_NEW_PO_STATE]->(po:PurchaseOrder)
"""

_REJECTED_RFQ_NOT_RESUBMITTED = """
    MATCH (sub) WHERE id(sub) = idFrom("SubmittedPoS")
    MATCH (sub)-[:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_SUPPLIER_REJECTED_RFQ]->(prr)-[:IS_SUPPLIER_REJECTED_RFQ_STATE]->(rrfq:RFQ)
    WHERE NOT ()-[:HAS_PREVIOUS_RFQ]->(rrfq)
"""

RFQ_VETTING_ACTIONS: list[VettingAction] = [
    VettingAction(
        "buyer_submit_po", 4,
        """
    MATCH (a) WHERE id(a) = idFrom("ApprovedPoS")
    MATCH (a)-[:IS_APPROVED_PO_STATE]->(po:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->()
    RETURN count(po) AS EligibleCount
    """,
        """
    MATCH (ro), (su), (a)
    WHERE id(ro) = idFrom("RolE", "Buyer") AND id(su) = idFrom("SubmittedPoS") AND id(a) = idFrom("ApprovedPoS")
    MATCH (ro)-[:IS_ACTIVE_ROLE]->(bu:Employee)
    WITH su, a, bu ORDER BY rand() LIMIT 1
    MATCH (a)-[ap:IS_APPROVED_PO_STATE]->(po:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(s:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp)
    WITH bu, su, ap, po, snp ORDER BY rand() LIMIT 1
    MATCH (po) WHERE NOT (po)-[:HAS_BUYER_PO_APPROVAL]->()
    CREATE (po)-[:HAS_BUYER_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "Submitted to Supplier by Buyer (stress test)."})-[:VETTED_BY]->(bu),
           (su)-[:IS_SUBMITTED_PO_STATE]->(po),
           (snp)-[:IS_SUPPLIER_NEW_PO_STATE]->(po),
           (po)-[:HAS_SUPPLIER_NEW_RFQ]->(:PoNewRFQ {Name: "PoNewRFQ"}),
           (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(:PoRejectedRFQ {Name: "PoRejectedRFQ"})
    DELETE ap
    RETURN po.PONumber AS PONumber
    """,
    ),
    VettingAction(
        "supplier_submit_rfq", 4,
        _NEW_PO_FOR_SUPPLIER + """
    RETURN count(po) AS EligibleCount
    """,
        _NEW_PO_FOR_SUPPLIER + """
    WITH su, r, po ORDER BY rand() LIMIT 1
    WITH su, r, po, CASE WHEN rand() < $overprice THEN 0.75 ELSE 0.7 END AS factor
    MATCH (po)-[:HAS_PO_ITEM]->(pq:POItem)-[:PO_ITEM_PRODUCT]->(p:Product), (po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr), (su)-[:HAS_SUPPLIER_OPEN_POS]->(sop)
    WITH su, r, po, snr, sop, collect({p: p, qty: pq.POqt, cost: p.UnitPrice * factor}) AS rfqItems
    MATCH (po) WHERE NOT ()-[:IS_RFQ_FOR_PO]->(po)
    CREATE (rfq:RFQ {RFQDate: datetime(), RFQComments: "Thanks for your order, we are able to supply the full PO product request at the discounted price negotiated on our master agreement (stress test)."})
    SET rfq.RFQNumber = "RFQ-" + left(strId(rfq), 5) + right(strId(rfq), 5)
    CREATE (rfq)-[:IS_RFQ_FOR_PO]->(po), (rfq)-[:RFQ_FROM_SUPPLIER]->(su), (sop)-[:IS_SUPPLIER_OPEN_PO_STATE]->(po)
    DELETE r
    WITH rfq, po, snr, rfqItems
    UNWIND rfqItems AS item
    WITH rfq, po, snr, item.p AS p, item.qty AS qty, item.cost AS cost
    CREATE (rfq)-[:HAS_RFQ_ITEM]->(:RFQItem {RFQqt: qty, RFQcost: cost})-[:RFQ_ITEM_PRODUCT]->(p)
    WITH rfq, po, snr, count(p) AS items
    CREATE (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq)
    RETURN rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber, items AS Items
    """,
    ),
    VettingAction(
        "rfq_reject", 1,
        _NEW_RFQ_LINES + """
    RETURN count(DISTINCT rfq) AS EligibleCount
    """,
        _NEW_RFQ_LINES + """
    MATCH (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(prr)
    WITH DISTINCT po, pnr, r, rfq, prr ORDER BY rand() LIMIT 1
    MATCH (ro) WHERE id(ro) = idFrom("RolE", "Buyer")
    MATCH (ro)-[:IS_ACTIVE_ROLE]->(bu:Employee)
    WITH po, r, rfq, prr, bu ORDER BY rand() LIMIT 1
    MATCH (rfq) WHERE NOT ()-[:IS_SUPPLIER_REJECTED_RFQ_STATE]->(rfq) AND NOT (po)-[:HAS_APPROVED_RFQ]->(rfq)
    CREATE (rfq)-[:HAS_BUYER_RFQ_REJECTION]->(:VettingDecision {Date: datetime(), Comment: "Rejected by Buyer (stress test)."})-[:VETTED_BY]->(bu),
           (prr)-[:IS_SUPPLIER_REJECTED_RFQ_STATE]->(rfq)
    DELETE r
    RETURN rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
    """,
    ),
    VettingAction(
        "rfq_approve", 5,
        _NEW_RFQ_LINES + """ AND NOT (po)-[:HAS_APPROVED_RFQ]->()
    RETURN count(DISTINCT rfq) AS EligibleCount
    """,
        _NEW_RFQ_LINES + """ AND NOT (po)-[:HAS_APPROVED_RFQ]->()
    WITH po, r, rfq, collect({p: p, qty: rfi.RFQqt}) AS items ORDER BY rand() LIMIT 1
    MATCH (ro) WHERE id(ro) = idFrom("RolE", "Buyer")
    MATCH (ro)-[:IS_ACTIVE_ROLE]->(bu:Employee)
    WITH po, r, rfq, items, bu ORDER BY rand() LIMIT 1
    MATCH (po) WHERE NOT (po)-[:HAS_APPROVED_RFQ]->()
    CREATE (rfq)-[:HAS_BUYER_RFQ_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "Approved by Buyer (stress test)."})-[:VETTED_BY]->(bu),
           (po)-[:HAS_APPROVED_RFQ]->(rfq)
    DELETE r
    SET rfq.OnOrderPosted = datetime()
    WITH po, rfq, items
    UNWIND items AS item
    WITH po, rfq, item.p AS p, toInteger(item.qty) AS qty
    MATCH (p)-[:HAS_SUPPLY_ORDER]->(suo)
    CALL int.add(suo, "UnitsOnOrder", qty) YIELD result
    RETURN rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber, count(result) AS LinesOnOrder
    """,
    ),
    VettingAction(
        "rfq_resubmit", 4,
        _REJECTED_RFQ_NOT_RESUBMITTED + """
    RETURN count(rrfq) AS EligibleCount
    """,
        _REJECTED_RFQ_NOT_RESUBMITTED + """
    WITH po, rrfq ORDER BY rand() LIMIT 1
    MATCH (rrfq)-[:RFQ_FROM_SUPPLIER]->(su:Supplier), (po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr)
    MATCH (po)-[:HAS_PO_ITEM]->(pq:POItem)-[:PO_ITEM_PRODUCT]->(p:Product)
    WITH rrfq, su, po, snr, collect({p: p, qty: pq.POqt, cost: p.UnitPrice * 0.65}) AS rfqItems
    MATCH (rrfq) WHERE NOT ()-[:HAS_PREVIOUS_RFQ]->(rrfq)
    CREATE (rfq:RFQ {RFQDate: datetime(), RFQComments: "Thanks for your order, we are resubmitting our RFQ with updated pricing (stress test)."})
    SET rfq.RFQNumber = "RFQ-" + left(strId(rfq), 5) + right(strId(rfq), 5)
    CREATE (rfq)-[:IS_RFQ_FOR_PO]->(po), (rfq)-[:RFQ_FROM_SUPPLIER]->(su),
           (rfq)-[:HAS_PREVIOUS_RFQ]->(rrfq),
           (rfq)-[:HAS_RESUBMISSION_NOTE]->(:ResubmissionNote {Justification: "Auto-resubmitted after rejection (stress test).", Date: datetime()})
    WITH rfq, po, snr, rfqItems
    UNWIND rfqItems AS item
    WITH rfq, po, snr, item.p AS p, item.qty AS qty, item.cost AS cost
    CREATE (rfq)-[:HAS_RFQ_ITEM]->(:RFQItem {RFQqt: qty, RFQcost: cost})-[:RFQ_ITEM_PRODUCT]->(p)
    WITH rfq, po, snr, count(p) AS items
    CREATE (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq)
    RETURN rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber, items AS Items
    """,
    ),
]


def iterate_rfq_vetting(q: Quine, stats: RunStats, log: logging.Logger) -> None:
    iterate_weighted_actions(q, stats, log, RFQ_VETTING_ACTIONS,
                             "No eligible RFQ Vetting action this cycle (no ApprovedPoS/SupplierNewPoS/RFQ items awaiting action)")


# ---------------------------------------------------------------------------
# Loop: warehouse-finance
# ---------------------------------------------------------------------------
#
# Two forward-progress actions with equal weight. Delivery adds stock and
# removes on-order quantity with atomic int.add; one WarehouseDelivery event
# node per PO. Finance pays and closes on both the procurement and the
# supplier side.

_DELIVERABLE = """
    MATCH (sub) WHERE id(sub) = idFrom("SubmittedPoS")
    MATCH (sub)-[:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(rfq:RFQ)
    WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
    MATCH (po)-[:HAS_PO_ITEM]->(poi:POItem)-[:PO_ITEM_PRODUCT]->(p:Product)<-[:RFQ_ITEM_PRODUCT]-(rfi:RFQItem)<-[:HAS_RFQ_ITEM]-(rfq)
    WHERE poi.POqt = rfi.RFQqt
"""

_CLOSABLE = """
    MATCH (t) WHERE id(t) = idFrom("PoS")
    MATCH (cpo)<-[:HAS_CLOSED_PO_STATE]-(t)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS)-[r1:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_WAREHOUSE_DELIVERY]->(:WarehouseDelivery),
          (po)<-[r2:IS_SUPPLIER_OPEN_PO_STATE]-(:SupplierOpenPoS)<-[:HAS_SUPPLIER_OPEN_POS]-(su:Supplier)-[:HAS_SUPPLIER_CLOSED_POS]->(scp)
    WHERE NOT (po)-[:HAS_FINANCE_PAYMENT]->()
"""

WAREHOUSE_FINANCE_ACTIONS: list[VettingAction] = [
    VettingAction(
        "warehouse_delivery", 5,
        _DELIVERABLE + """
    RETURN count(DISTINCT po) AS EligibleCount
    """,
        _DELIVERABLE + """
    WITH po, collect({p: p, qty: rfi.RFQqt}) AS items ORDER BY rand() LIMIT 1
    MATCH (ro) WHERE id(ro) = idFrom("RolE", "WarehouseClerk")
    MATCH (ro)-[:IS_ACTIVE_ROLE]->(wc:Employee)
    WITH po, items, wc ORDER BY rand() LIMIT 1
    MATCH (po) WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
    CREATE (po)-[:HAS_WAREHOUSE_DELIVERY]->(:WarehouseDelivery {Date: datetime(), Comment: "The products have been received as per PO at the Warehouse and the Inventory Levels have been updated accordingly (stress test)."})-[:RECEIVED_BY]->(wc)
    WITH po, items
    UNWIND items AS item
    WITH po, item.p AS p, toInteger(item.qty) AS qty
    MATCH (p)-[:HAS_INVENTORY_LEVEL]->(inv), (p)-[:HAS_SUPPLY_ORDER]->(suo)
    CALL int.add(inv, "UnitsInStock", qty) YIELD result AS stock
    CALL int.add(suo, "UnitsOnOrder", -qty) YIELD result AS onOrder
    SET inv.LastUpdate = datetime()
    RETURN po.PONumber AS PONumber, count(*) AS LinesReceived, collect(p.ProductID) AS ProductIDs
    """,
    ),
    VettingAction(
        "finance_closure", 5,
        _CLOSABLE + """
    RETURN count(DISTINCT po) AS EligibleCount
    """,
        _CLOSABLE + """
    WITH cpo, scp, r1, r2, po ORDER BY rand() LIMIT 1
    MATCH (ro) WHERE id(ro) = idFrom("RolE", "Finance")
    MATCH (ro)-[:IS_ACTIVE_ROLE]->(f:Employee)
    WITH cpo, scp, r1, r2, po, f ORDER BY rand() LIMIT 1
    MATCH (po) WHERE NOT (po)-[:HAS_FINANCE_PAYMENT]->()
    CREATE (po)-[:HAS_FINANCE_PAYMENT]->(:FinancePayment {Date: datetime(), Comment: "The PO has been paid by Finance and the PO is now closed (stress test)."})-[:PAID_BY]->(f),
           (cpo)-[:IS_CLOSED_PO_STATE]->(po),
           (scp)-[:HAS_SUPPLIER_CLOSED_PO_STATE]->(po)
    DELETE r1, r2
    RETURN po.PONumber AS PONumber
    """,
    ),
]


def iterate_warehouse_finance(q: Quine, stats: RunStats, log: logging.Logger) -> None:
    iterate_weighted_actions(q, stats, log, WAREHOUSE_FINANCE_ACTIONS,
                             "No eligible Warehouse/Finance action this cycle (nothing awaiting delivery or closure)")


# ---------------------------------------------------------------------------
# Loop: po-creation
# ---------------------------------------------------------------------------
#
# One PO per Supplier for its Products in the LowStocK Collection. The rule is
# re-checked with current numbers before ordering (quantity already on active,
# not yet delivered POs, and quantity promised to open Customer Orders -- both
# fixes from the original are kept). Order size: threshold - effective
# available + 2 x threshold, as in the original loop. The PO's NewPoS edge is
# written LAST, after its items, so a standing query on NewPoS never sees a
# PO without items.

PO_CREATION_QUERY = """
MATCH (pa), (n), (ls)
WHERE id(pa) = idFrom("RolE", "Procurement Assistant") AND id(n) = idFrom("NewPoS") AND id(ls) = idFrom("LowStocK")
MATCH (pa)-[:IS_ACTIVE_ROLE]->(e:Employee)
WITH n, ls, e ORDER BY rand() LIMIT 1
MATCH (ls)-[:IS_LOW_STOCK_PRODUCT]->(p:Product)<-[:SUPPLIES]-(s:Supplier),
      (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[:HAS_PO_ITEM]->(poi2:POItem)-[:PO_ITEM_PRODUCT]->(p)
WHERE NOT (activePO)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH e, n, s, p, r, i, sum(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty
OPTIONAL MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(op:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
WITH e, n, s, p, r, i, AlreadyPendingQty, sum(coalesce(op.Quantity, 0)) AS OpenOrderQty
WHERE i.UnitsInStock + AlreadyPendingQty - OpenOrderQty - (r.StockThreshold * 0.5) <= r.StockThreshold
WITH e, n, s, collect({p: p, qty: r.StockThreshold - (i.UnitsInStock + AlreadyPendingQty - OpenOrderQty) + (r.StockThreshold * 2)}) AS orderItems
CREATE (po:PurchaseOrder {PODate: datetime()})
SET po.PONumber = "PO-" + left(strId(po), 5) + right(strId(po), 5)
CREATE (po)-[:PO_FOR_SUPPLIER]->(s), (po)-[:PO_CREATED_BY]->(e)
WITH n, po, s, orderItems
UNWIND orderItems AS item
WITH n, po, s, item.p AS p, item.qty AS qty
CREATE (po)-[:HAS_PO_ITEM]->(:POItem {POqt: qty, POPriceDiscount: 0.7})-[:PO_ITEM_PRODUCT]->(p)
WITH n, po, s, collect(p.ProductID) AS productIds
CREATE (n)-[:IS_NEW_PO_STATE]->(po)
RETURN po.PONumber AS PONumber, s.SupplierID AS SupplierID, size(productIds) AS ItemCount, productIds AS ProductIDs
"""


def iterate_po_creation(q: Quine, stats: RunStats, log: logging.Logger) -> None:
    pos = execute_with_retry(q, lambda c: c.query(PO_CREATION_QUERY), stats, log)
    if pos:
        summary = ", ".join(f"{r['PONumber']} (Supplier {r['SupplierID']}, {r['ItemCount']} item(s))" for r in pos)
        log.info(f"Created {len(pos)} PO(s): {summary}")
        reevaluate_low_stock(q, [pid for r in pos for pid in r["ProductIDs"]], stats, log)
    else:
        stats.no_op += 1
        log.info("No PO Creation this cycle (LowStock is empty)")


# ---------------------------------------------------------------------------
# Loop: order-fulfillment
# ---------------------------------------------------------------------------
#
# Oldest fully-in-stock Open Order first (business rule kept from the
# original). Re-checks, right before writing, that the order is still Open
# and every line still has stock; then ships it and decrements stock with
# atomic int.add. Only this loop decrements stock, and it runs on a single
# thread, so it cannot oversell.

ORDER_FULFILLMENT_QUERY = """
MATCH (ro), (ss), (op), (f)
WHERE id(ro) = idFrom("RolE", "WarehouseClerk") AND id(ss) = idFrom("ShipperS")
  AND id(op) = idFrom("OrderStatusOpeN") AND id(f) = idFrom("OrderStatusFulfilleD")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(wc:Employee), (ss)-[:IS_SHIPPER]->(s:Shipper)<-[:HAS_SHIPPER]-(si:ShipInfo)
WITH op, f, wc, si, s ORDER BY rand() LIMIT 1
MATCH (op)-[:IS_OPEN_ORDER_STATE]->(o:Order)-[:HAS_ORDER_ITEM]->(details:OrderItem)-[:ORDER_ITEM_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
WITH op, f, wc, si, s, o,
     count(details) AS TotalLines,
     sum(CASE WHEN inv.UnitsInStock > details.Quantity THEN 1 ELSE 0 END) AS LinesWithStock
WHERE TotalLines = LinesWithStock
WITH op, f, wc, si, s, o ORDER BY o.OrderDate LIMIT 1
MATCH (o)-[:HAS_ORDER_ITEM]->(details:OrderItem)-[:ORDER_ITEM_PRODUCT]->(pr:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
WITH op, f, wc, si, s, o, collect({qty: details.Quantity, inv: inv, pid: pr.ProductID}) AS lines
MATCH (op)-[r:IS_OPEN_ORDER_STATE]->(o)
WHERE all(x IN lines WHERE x.inv.UnitsInStock > x.qty)
MATCH (o)-[:HAS_ORDER_CUSTOMER]->(:Customer)-[:HAS_CUSTOMER_ADDRESS]->(a)
CREATE (i:ShipInfo {ShippedDate: datetime(), ShipName: si.ShipName, Freight: round(rand() * 100, 2)})
SET i.ShippmentID = "SH-" + strId(i)
CREATE (o)-[:HAS_SHIPMENT_INFO]->(i), (i)-[:HAS_SHIPPER]->(s), (i)-[:HAS_SHIPMENT_ADDRESS]->(a),
       (f)-[:IS_FULFILLED_ORDER_STATE]->(o),
       (o)-[:HAS_WAREHOUSE_FULFILLMENT]->(:WarehouseFulfillment {Date: datetime(), Comment: "Order picked, packed, and shipped by the Warehouse Clerk."})-[:FULFILLED_BY]->(wc)
DELETE r
WITH o, lines
UNWIND lines AS x
WITH o, x.inv AS inv, toInteger(x.qty) AS qty, x.pid AS pid
CALL int.add(inv, "UnitsInStock", -qty) YIELD result
SET inv.LastUpdate = datetime()
RETURN o.OrderID AS OrderID, count(result) AS Lines, collect(pid) AS ProductIDs
"""


def iterate_order_fulfillment(q: Quine, stats: RunStats, log: logging.Logger) -> None:
    rows = execute_with_retry(q, lambda c: c.query(ORDER_FULFILLMENT_QUERY), stats, log)
    if rows:
        log.info(f"Fulfilled Order {rows[0]['OrderID']} ({rows[0]['Lines']} line(s))")
        reevaluate_low_stock(q, rows[0]["ProductIDs"], stats, log)
    else:
        stats.no_op += 1
        log.info("No Order Fulfillment this cycle (no Open Order currently has full stock coverage for every line)")


# ---------------------------------------------------------------------------
# sq mode: the outside world only
# ---------------------------------------------------------------------------
#
# rfq-submission   the suppliers: answer the POs the Buyer submitted (the
#                  nw-buyer-submission standing query) with an RFQ, sometimes
#                  above budget (--overprice), and resubmit rejected RFQs at a
#                  better price. The nw-rfq-vetting standing query vets them.
# rfq-fulfillment  the goods arrive: the warehouse receives a PO whose RFQ was
#                  approved (stock up, on-order down, LowStock re-evaluated).
#                  nw-finance-closure then pays and closes it.
# threshold-recalibration  the slow job: StockThreshold = 150% of the average
#                  monthly quantity ordered, then LowStock re-evaluated for
#                  every product (new members trigger nw-reorder-low-stock).

def _action(actions: list[VettingAction], name: str) -> VettingAction:
    return next(a for a in actions if a.name == name)


RFQ_SUBMISSION_ACTIONS = [_action(RFQ_VETTING_ACTIONS, "supplier_submit_rfq"), _action(RFQ_VETTING_ACTIONS, "rfq_resubmit")]
RFQ_FULFILLMENT_ACTIONS = [_action(WAREHOUSE_FINANCE_ACTIONS, "warehouse_delivery")]


def iterate_rfq_submission(q: Quine, stats: RunStats, log: logging.Logger) -> None:
    iterate_weighted_actions(q, stats, log, RFQ_SUBMISSION_ACTIONS,
                             "No RFQ to submit this cycle (no submitted PO waiting for its supplier, no rejected RFQ to resubmit)")


def iterate_rfq_fulfillment(q: Quine, stats: RunStats, log: logging.Logger) -> None:
    iterate_weighted_actions(q, stats, log, RFQ_FULFILLMENT_ACTIONS,
                             "No delivery this cycle (no PO with an approved RFQ awaiting its goods)")


THRESHOLD_RECALIBRATION_QUERY = """
MATCH (av) WHERE id(av) = idFrom("ProductStatusAvailablE")
MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_REORDER_LEVEL]->(re:ReorderLevel)
MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(oi:OrderItem)<-[:HAS_ORDER_ITEM]-(o:Order)
WITH p, re, re.StockThreshold AS before, sum(oi.Quantity) AS TotalQuantityOrdered,
     count(DISTINCT (toString(o.OrderDate.year) + "-" + toString(o.OrderDate.month))) AS MonthsWithOrders
WITH p, re, before, toInteger(round((toFloat(TotalQuantityOrdered) / MonthsWithOrders) * 1.5)) AS after
SET re.StockThreshold = after, re.LastUpdate = datetime()
RETURN count(p) AS Products, sum(CASE WHEN after <> before THEN 1 ELSE 0 END) AS Changed, collect(p.ProductID) AS ProductIDs
"""


def iterate_threshold_recalibration(q: Quine, stats: RunStats, log: logging.Logger) -> None:
    rows = execute_with_retry(q, lambda c: c.query(THRESHOLD_RECALIBRATION_QUERY), stats, log)
    if rows:
        log.info(f"Recalibrated stock thresholds: {rows[0]['Products']} products, {rows[0]['Changed']} changed")
        reevaluate_low_stock(q, rows[0]["ProductIDs"], stats, log)
    else:
        stats.no_op += 1
        log.info("No thresholds recalibrated (no products with order history)")


# ---------------------------------------------------------------------------
# Loop dispatch table
# ---------------------------------------------------------------------------

LOOPS: dict[str, Callable[[Quine, RunStats, logging.Logger], None]] = {
    "customer-order": iterate_customer_order,
    "po-creation": iterate_po_creation,
    "po-vetting": iterate_po_vetting,
    "rfq-vetting": iterate_rfq_vetting,
    "warehouse-finance": iterate_warehouse_finance,
    "order-fulfillment": iterate_order_fulfillment,
    "rfq-submission": iterate_rfq_submission,
    "rfq-fulfillment": iterate_rfq_fulfillment,
    "threshold-recalibration": iterate_threshold_recalibration,
}


# ---------------------------------------------------------------------------
# Data-quality invariants (from the last section of the Cypher script)
# ---------------------------------------------------------------------------

INVARIANTS = [
    ("no product with negative stock",
     "MATCH (i:InventoryLevel) WHERE i.UnitsInStock < 0 RETURN count(i) AS n"),
    ("no product with negative units on order",
     "MATCH (s:OrderLevel) WHERE s.UnitsOnOrder < 0 RETURN count(s) AS n"),
    ("every PO is in exactly one procurement state",
     """MATCH (po:PurchaseOrder)
        WITH po, size([(po)<-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE|IS_REJECTED_PO_STATE|IS_CLOSED_PO_STATE]-(c) | c]) AS states
        WHERE states <> 1 RETURN count(po) AS n"""),
    ("no PO with two decisions at the same level",
     """MATCH (po:PurchaseOrder)
        WITH po, size([(po)-[:HAS_L1_PO_APPROVAL|HAS_L1_PO_REJECTION]->(d) | d]) AS l1,
                 size([(po)-[:HAS_L2_PO_APPROVAL|HAS_L2_PO_REJECTION]->(d) | d]) AS l2,
                 size([(po)-[:HAS_L3_PO_APPROVAL|HAS_L3_PO_REJECTION]->(d) | d]) AS l3
        WHERE l1 > 1 OR l2 > 1 OR l3 > 1 RETURN count(po) AS n"""),
    ("no PO with more than one approved RFQ",
     "MATCH (po:PurchaseOrder) WITH po, size([(po)-[:HAS_APPROVED_RFQ]->(r) | r]) AS n WHERE n > 1 RETURN count(po) AS n"),
    ("no order both open and fulfilled",
     "MATCH (o:Order)<-[:IS_OPEN_ORDER_STATE]-(), (o)<-[:IS_FULFILLED_ORDER_STATE]-() RETURN count(o) AS n"),
    ("no PO paid before it was delivered",
     "MATCH (po:PurchaseOrder)-[:HAS_FINANCE_PAYMENT]->() WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->() RETURN count(po) AS n"),
    ("no PO delivered or paid twice",
     """MATCH (po:PurchaseOrder)
        WITH po, size([(po)-[:HAS_WAREHOUSE_DELIVERY]->(d) | d]) AS deliveries, size([(po)-[:HAS_FINANCE_PAYMENT]->(f) | f]) AS payments
        WHERE deliveries > 1 OR payments > 1 RETURN count(po) AS n"""),
    ("LowStock membership matches the reorder rule for every product",
     """MATCH (av), (ls) WHERE id(av) = idFrom("ProductStatusAvailablE") AND id(ls) = idFrom("LowStocK")
        MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
        OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[:HAS_PO_ITEM]->(poi:POItem)-[:PO_ITEM_PRODUCT]->(p)
        WHERE NOT (activePO)-[:HAS_WAREHOUSE_DELIVERY]->()
        WITH ls, p, r, i, sum(coalesce(poi.POqt, 0)) AS pending
        OPTIONAL MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(oi:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
        WITH ls, p, r, i, pending, sum(coalesce(oi.Quantity, 0)) AS openQty
        WITH ls, p, i.UnitsInStock + pending - openQty - (r.StockThreshold * 0.5) <= r.StockThreshold AS low
        OPTIONAL MATCH (ls)-[e:IS_LOW_STOCK_PRODUCT]->(p)
        WITH low, e WHERE (low AND e IS NULL) OR (NOT low AND e IS NOT NULL)
        RETURN count(*) AS n"""),
    ("UnitsOnOrder matches approved RFQs not yet delivered",
     """MATCH (av) WHERE id(av) = idFrom("ProductStatusAvailablE")
        MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_SUPPLY_ORDER]->(suo)
        OPTIONAL MATCH (po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(:RFQ)-[:HAS_RFQ_ITEM]->(rfi:RFQItem)-[:RFQ_ITEM_PRODUCT]->(p)
        WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
        WITH p, suo, coalesce(sum(rfi.RFQqt), 0) AS pending
        WHERE suo.UnitsOnOrder <> pending RETURN count(p) AS n"""),
]


def run_invariants(q: Quine) -> bool:
    log = logging.getLogger("invariants")
    ok = True
    for title, cypher in INVARIANTS:
        try:
            n = q.query(cypher)[0]["n"]
        except (CypherError, TransientQuineError) as exc:
            log.error(f"{title}: could not run ({exc})")
            ok = False
            continue
        if n == 0:
            log.info(f"ok        {title}")
        else:
            log.error(f"VIOLATED  {title} ({n})")
            ok = False
    return ok


# ---------------------------------------------------------------------------
# Rate-limited runner (one thread per loop)
# ---------------------------------------------------------------------------

_shutdown = threading.Event()


def _handle_sigint(signum, frame):
    if not _shutdown.is_set():
        logging.getLogger("harness").info("Shutdown requested -- finishing current executions, then stopping...")
    _shutdown.set()


def run_loop(q: Quine, loop_name: str, rate_per_minute: float, duration_seconds: float | None,
             results: dict) -> None:
    fn = LOOPS[loop_name]
    log = logging.getLogger(loop_name)
    interval = 60.0 / rate_per_minute
    stats = RunStats()
    results[loop_name] = stats
    log.info(f"Starting loop '{loop_name}' at {rate_per_minute}/min (every {interval:.2f}s) against {q.base_url}")

    while not _shutdown.is_set():
        iteration_start = time.perf_counter()
        fn(q, stats, log)
        stats.executions += 1
        if duration_seconds is not None and (time.perf_counter() - stats.start_time) >= duration_seconds:
            break
        elapsed = time.perf_counter() - iteration_start
        sleep_for = max(0.0, interval - elapsed)
        if sleep_for == 0.0:
            log.warning(f"Execution took {elapsed:.2f}s, longer than the {interval:.2f}s interval -- falling behind target rate")
        _shutdown.wait(sleep_for)


def summarize(results: dict) -> None:
    log = logging.getLogger("summary")
    for name, stats in results.items():
        total_elapsed = time.perf_counter() - stats.start_time
        achieved = (stats.executions / total_elapsed * 60.0) if total_elapsed > 0 else 0.0
        actions = (" actions=" + ",".join(f"{k}:{v}" for k, v in sorted(stats.actions.items()))) if stats.actions else ""
        log.info(f"=== '{name}' === executions={stats.executions} retries={stats.retries} errors={stats.errors} "
                 f"no_op={stats.no_op} elapsed={total_elapsed:.1f}s achieved_rate={achieved:.2f}/min{actions}")


def parse_rates(spec: str | None, mode: str) -> dict:
    rates = dict(DEFAULT_RATES[mode])
    if spec:
        for part in spec.split(","):
            name, _, value = part.partition("=")
            name = name.strip()
            if name not in LOOPS:
                raise SystemExit(f"--rates: unknown loop '{name}' (known: {', '.join(LOOPS)})")
            rates[name] = float(value)
    return {k: v for k, v in rates.items() if v > 0}


def registered_nw_standing_queries(q: Quine) -> list[str]:
    req = urllib.request.Request(f"{q.base_url}/api/v2/graph/quine/standingQueries")
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    items = payload.get("items", payload) if isinstance(payload, dict) else payload
    return sorted(sq.get("name", "") for sq in items if sq.get("name", "").startswith("nw-"))


def main() -> None:
    parser = argparse.ArgumentParser(description="NorthWind PLUS concurrency stress harness for Quine.")
    parser.add_argument("--mode", choices=["auto", "sq", "loops"], default="auto",
                        help="sq: outside-world loops only (standing queries do the rest); loops: the original six; "
                             "auto (default): sq if the nw-* standing queries are registered, else loops.")
    parser.add_argument("--overprice", type=float, default=0.15,
                        help="sq mode: share of RFQs quoted above the PO budget (default 0.15).")
    parser.add_argument("--loop", choices=sorted(LOOPS.keys()), help="Run only this loop (default: every loop of the mode, in parallel).")
    parser.add_argument("--rate", type=float, default=6.0, help="Executions per minute for --loop (default: 6).")
    parser.add_argument("--rates", help="Per-loop rates, e.g. customer-order=12,rfq-submission=8 (0 disables a loop).")
    parser.add_argument("--duration", type=float, default=None, help="Stop after this many seconds (default: run until Ctrl+C).")
    parser.add_argument("--check", action="store_true", help="Run the data-quality invariants when the loops stop.")
    parser.add_argument("--check-only", action="store_true", help="Only run the data-quality invariants, then exit.")
    parser.add_argument("--quine", default=os.environ.get("QUINE_URL", "http://localhost:8080"), help="Quine base URL.")
    args = parser.parse_args()

    q = Quine(args.quine)
    harness = logging.getLogger("harness")
    try:
        info = q.build_info()
    except Exception as exc:
        raise SystemExit(f"Quine is not answering at {args.quine}: {exc}")
    harness.info(f"Quine {info.get('version')} at {args.quine}")

    if args.check_only:
        sys.exit(0 if run_invariants(q) else 1)

    loaded = q.query('MATCH (n), (ls) WHERE id(n) = idFrom("NewPoS") AND id(ls) = idFrom("LowStocK") RETURN n.Name AS name, ls.Name AS lowStock')
    if not loaded or loaded[0]["name"] != "NewPoS":
        raise SystemExit("The NorthWind PLUS graph is not loaded -- run northwind-plus-quine-batch.sh first.")
    if loaded[0]["lowStock"] != "LowStock":
        raise SystemExit("The graph has no LowStocK Collection -- reload it with the current northwind-plus-quine-batch.sh.")

    sqs = registered_nw_standing_queries(q)
    mode = args.mode if args.mode != "auto" else ("sq" if sqs else "loops")
    if mode == "loops" and sqs:
        raise SystemExit(f"{len(sqs)} NorthWind standing queries are registered; they would compete with the loops-mode "
                         "procurement loops. Use --mode sq, or remove them: ./register-standing-queries.sh --remove")
    if mode == "sq" and not sqs:
        harness.warning("--mode sq but no nw-* standing queries are registered: POs will pile up in LowStock/NewPoS. "
                        "Run ./register-standing-queries.sh first.")
    ACTION_PARAMS["overprice"] = args.overprice if mode == "sq" else 0.0
    harness.info(f"Mode: {mode}" + (f" ({len(sqs)} standing queries active, overprice {args.overprice:.0%})" if mode == "sq" else ""))
    selected = {args.loop: args.rate} if args.loop else parse_rates(args.rates, mode)
    signal.signal(signal.SIGINT, _handle_sigint)
    signal.signal(signal.SIGTERM, _handle_sigint)

    results: dict = {}
    threads = [threading.Thread(target=run_loop, name=name, args=(q, name, rate, args.duration, results), daemon=True)
               for name, rate in selected.items()]
    for t in threads:
        t.start()
    while any(t.is_alive() for t in threads):
        for t in threads:
            t.join(timeout=0.5)

    summarize(results)
    if args.check:
        if mode == "sq":
            harness.info("Waiting 10 s for the standing queries to finish reacting before the checks...")
            time.sleep(10)
        sys.exit(0 if run_invariants(q) else 1)


if __name__ == "__main__":
    main()
