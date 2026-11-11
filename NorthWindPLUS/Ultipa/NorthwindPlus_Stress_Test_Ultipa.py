#!/usr/bin/env python3
"""
NorthWind PLUS Concurrency Stress Harness -- Ultipa GQLDB (ISO GQL) port
========================================================================

Same harness as NorthwindPlus_Stress_Test.py (Neo4j), ported to Ultipa GQLDB
("Ultipa Graph v6") and its Python driver. Runs one workflow step of the
NorthWind PLUS Graph Data Model as an independent, rate-limited,
indefinitely-repeating loop -- intended to be launched as several separate OS
processes (one per --loop) so they behave like genuinely independent
real-world actors (Sales, Procurement, Warehouse, Finance, Suppliers)
hammering the same graph concurrently.

Usage:
    pip install ultipa            # the GQLDB driver; it is imported as "gqldb"

    export ULTIPA_HOSTS="localhost:9000"      # comma-separated host:port list
    export ULTIPA_USER="root"
    export ULTIPA_PASSWORD="your-password"
    export ULTIPA_GRAPH="NorthWindPLUS"
    export ULTIPA_TIMEOUT="60"                 # optional: per-query deadline in seconds
    export ULTIPA_TLS="1"                      # optional: only if your instance requires TLS (default off)

    python NorthwindPlus_Stress_Test_Ultipa.py --loop customer-order --rate 6
    python NorthwindPlus_Stress_Test_Ultipa.py --loop po-creation --rate 2 &
    python NorthwindPlus_Stress_Test_Ultipa.py --loop po-vetting --rate 4 &
    python NorthwindPlus_Stress_Test_Ultipa.py --loop rfq-vetting --rate 4 &
    python NorthwindPlus_Stress_Test_Ultipa.py --loop warehouse-finance --rate 4 &
    python NorthwindPlus_Stress_Test_Ultipa.py --loop order-fulfillment --rate 4 &
    ... (launch each loop as its own process/terminal)

--rate is executions per minute. Ctrl+C stops a loop cleanly and prints a
summary (executions, retries, errors, achieved rate).

All six loops are implemented -- the full pipeline can run concurrently:
    customer-order    -- creates one random Open Customer Order with 1-11 lines
    po-creation       -- creates one PO per Supplier currently below restock threshold
    po-vetting        -- L1/L2/L3 approve/reject/passthrough + rejected-PO resubmission
    rfq-vetting       -- Buyer submits PO to Supplier, Supplier submits RFQ,
                          Buyer approves/rejects/resubmits the RFQ
    warehouse-finance -- Warehouse Clerk receives a delivered PO's items (updates
                          Inventory/OrderLevel), Finance pays and closes the PO
    order-fulfillment -- ships an Open Customer Order once every line has stock,
                          decrementing Inventory (oldest Order served first)

Why this file is so small
--------------------------
Notice what's deliberately absent: no approval-threshold constants, no
state-machine definitions, no hardcoded rule for when a PO needs Level 2 or
Level 3 sign-off, no validation logic for what makes an RFQ "fit budget."
Every dollar threshold, every "who can approve what," lives on
RolE.ApprovalBase/ApprovalLimit in the graph and is read fresh at query time.
The Collection (hub) nodes and their relationships ARE the state machine. This
file's job is orchestration only: pick a rate, open a transaction, run one
GQL statement, retry on contention, log the result. Every action below reduces
to a name, a weight, and two strings of GQL -- the graph does the rest.

What changed from the Neo4j version (and why)
---------------------------------------------
1. Driver: neo4j -> gqldb (GqldbClient / GqldbConfig). Each unit of work runs
   in an explicit transaction (begin_transaction / commit / rollback), and
   every statement is sent with QueryConfig(transaction_id=...).

2. Concurrency control -- the big one. Neo4j: pick a candidate, take a write
   lock with apoc.lock.nodes([...]), re-check the guard under the lock.
   GQLDB has no APOC and no explicit lock statement. Its documented model is
   snapshot isolation with conflict detection at COMMIT: if two transactions
   read the same node and both modify it, the one that commits second is
   refused with error 3011 (write conflict), which is retryable. Re-checking a
   guard inside a snapshot is pointless (it re-reads the same snapshot), so
   the lock + re-check pairs are gone and the retry loop does that job: the
   refused transaction is rolled back, retried, and on its fresh snapshot the
   guard (e.g. "not yet vetted") fails, so it becomes the harmless "lost the
   race" no-op the harness already logs.

   The catch: Ultipa's docs describe the conflict rule for a node that both
   transactions MODIFY. Many of these actions only add/delete edges around the
   chosen PO/RFQ/Order and never change the node itself, and the docs don't say
   whether edge changes count as modifying the endpoint. So every action that
   used apoc.lock.nodes() now also bumps a counter on the node it used to lock:
       SET po.OCCVersion = coalesce(po.OCCVersion, 0) + 1
   That guarantees the second transaction conflicts -- the GQLDB stand-in for
   apoc.lock.nodes(). It is the one deliberate departure from the model's
   Read-Only Nodes principle in this port. If Ultipa confirms that edge
   inserts/deletes conflict on their endpoints, set OCC_TOUCH = False below and
   no extra property is written.

3. GQL syntax: WITH -> RETURN ... NEXT / LET / FILTER; CREATE -> INSERT;
   UNWIND -> FOR; datetime() -> local_datetime(); randomUUID() -> built from
   the node's auto-generated UUID _id right after INSERT; LIMIT takes a
   literal, so the customer-order line count is chosen in Python.
"""

from __future__ import annotations

import argparse
import logging
import math
import os
import random
import re
import signal
import sys
import time
from dataclasses import dataclass, field
from typing import Callable

from gqldb import GqldbClient, GqldbConfig
from gqldb.client import QueryConfig
from gqldb.errors import GqldbError, ConnectionFailedError, WriteConflictError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("northwind-stress-ultipa")


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

# See note 2 in the module docstring. True = write OCCVersion on the node each
# guarded action used to lock with apoc.lock.nodes().
OCC_TOUCH = True

# Ultipa's documented error code for a write conflict at COMMIT (retryable).
WRITE_CONFLICT_CODE = 3011


# ---------------------------------------------------------------------------
# GQLDB workaround: name every element created by INSERT
# ---------------------------------------------------------------------------
# Found while testing on a live GQLDB instance: an INSERT that copies a value
# from another variable (e.g. {UnitsInStock: r.UnitsInStock}) into an
# ANONYMOUS element -- (:InventoryLevel {...}) or -[:HAS_PO_ITEM {...}]-> --
# stored null. The same INSERT with named elements stored the value. So every
# anonymous node/edge with a property map inside an INSERT clause is given a
# variable name (ins_n1, ins_e2, ...) before the query is sent.
KW = re.compile(r'\b(SET|DELETE|DETACH|MATCH|OPTIONAL|FOR|RETURN|NEXT|LET|FILTER|ORDER|LIMIT|CALL|REMOVE|MERGE|INSERT)\b|[;}]\s*$', re.M)
def name_anonymous_insert_elements(q: str) -> str:
    """Give every anonymous node/edge that has a property map inside an INSERT clause a variable name."""
    out, pos, k = [], 0, 0
    for m in re.finditer(r'\bINSERT\b', q):
        if m.start() < pos:
            continue
        out.append(q[pos:m.end()])
        nxt = KW.search(q, m.end())
        end = nxt.start() if nxt else len(q)
        seg = q[m.end():end]
        def node(mm):
            nonlocal k; k += 1
            return f"(ins_n{k}:{mm.group(1)} {{"
        def edge(mm):
            nonlocal k; k += 1
            return f"-[ins_e{k}:{mm.group(1)} {{"
        seg = re.sub(r'\(:(\w+)\s*\{', node, seg)
        seg = re.sub(r'-\[:(\w+)\s*\{', edge, seg)
        out.append(seg)
        pos = end
    out.append(q[pos:])
    return "".join(out)


def _occify(query: str) -> str:
    """Replace each @OCC(var) marker with the OCCVersion bump (or nothing)."""
    def repl(m: re.Match) -> str:
        var = m.group(1)
        return f"SET {var}.OCCVersion = coalesce({var}.OCCVersion, 0) + 1" if OCC_TOUCH else ""
    return re.sub(r"@OCC\((\w+)\)", repl, query)


# ---------------------------------------------------------------------------
# Transaction + retry-on-conflict wrapper
# ---------------------------------------------------------------------------

@dataclass
class RunStats:
    executions: int = 0
    retries: int = 0
    errors: int = 0
    no_op: int = 0          # executions where the query ran but matched nothing
    start_time: float = field(default_factory=time.perf_counter)


class Tx:
    """Thin handle passed to each work function: tx.run(gql) -> list[dict]."""

    def __init__(self, client: GqldbClient, tx_id, graph: str):
        self._client = client
        self._cfg = QueryConfig(transaction_id=tx_id, graph_name=graph)

    def run(self, query: str) -> list[dict]:
        response = self._client.gql(name_anonymous_insert_elements(_occify(query)), self._cfg)
        return response.to_dicts() if response is not None else []


def _is_retryable(exc: Exception) -> bool:
    """Write conflicts (3011) and dropped connections are worth retrying.
    The gqldb driver (checked against ultipa 6.2.15) raises WriteConflictError
    for 3011 -- from commit() AND from individual statements -- so the whole
    unit of work is re-run. The code/message checks are a fallback."""
    if isinstance(exc, (WriteConflictError, ConnectionFailedError)):
        return True
    if getattr(exc, "code", 0) == WRITE_CONFLICT_CODE:
        return True
    msg = str(exc).lower()
    return str(WRITE_CONFLICT_CODE) in msg or "write conflict" in msg or "aborted" in msg


def _safe_rollback(client: GqldbClient, tx) -> None:
    if tx is None:
        return
    try:
        client.rollback(tx.id)
    except Exception:
        pass  # a transaction refused at COMMIT is usually already gone


def execute_with_retry(client: GqldbClient, work_fn: Callable, stats: RunStats, graph: str, max_retries: int = 5):
    """Runs work_fn(tx) inside one explicit GQLDB transaction and commits it.
    On a write conflict (3011) the transaction is rolled back and the whole
    unit of work is re-run on a fresh snapshot, with exponential backoff --
    the GQLDB equivalent of Neo4j's execute_write() retry on TransientError.

    Expect retries to rise under heavy concurrency: that is the conflict
    detection doing the job apoc.lock.nodes() did in the Neo4j version. A
    sharp rise in the retries count confirms contention is being caught,
    rather than silently corrupting data."""
    attempt = 0
    while True:
        tx = None
        try:
            tx = client.begin_transaction(graph)
            result = work_fn(Tx(client, tx.id, graph))
            client.commit(tx.id)
            return result
        except GqldbError as exc:
            _safe_rollback(client, tx)
            if not _is_retryable(exc):
                log.error(f"Non-retryable error: {exc}")
                stats.errors += 1
                return None
            attempt += 1
            stats.retries += 1
            if attempt > max_retries:
                log.error(f"Gave up after {max_retries} retries: {exc}")
                stats.errors += 1
                return None
            wait = min(2 ** attempt * 0.1, 2.0) + random.uniform(0, 0.1)
            log.warning(f"Conflict/transient error (attempt {attempt}/{max_retries}), retrying in {wait:.2f}s: {exc}")
            time.sleep(wait)
        except Exception as exc:
            _safe_rollback(client, tx)
            log.error(f"Non-retryable error: {exc}")
            stats.errors += 1
            return None


# ---------------------------------------------------------------------------
# Loop: customer-order
# ---------------------------------------------------------------------------
#
# GQLDB's LIMIT takes a literal integer, so the random number of order lines
# (Cypher: LIMIT toInteger(round(rand() * 10 + 1))) is picked here in Python
# with the same formula and written into the query.

CUSTOMER_ORDER_QUERY = """
MATCH (e:Employee)-[]-(:RolE {Title: "Sales Representative"}), (op:OrderStatusOpeN {Status: "Open"})
ORDER BY random() LIMIT 1
MATCH (c:Customer)
ORDER BY random() LIMIT 1
INSERT (op)-[:IS_OPEN_ORDER_STATE]->(o:Order {OrderDate: local_datetime(), RequiredDate: date_add(local_datetime(), 7, "day")}),
       (o)-[:HAS_ORDER_CUSTOMER]->(c),
       (o)-[:SOLD_BY]->(e)
SET o.OrderID = "CO-" || left(o._id, 5) || right(o._id, 5)
MATCH (p:Product)<-[]-(:ProductStatusAvailablE {Status: "Available"})
ORDER BY random() LIMIT __LINE_COUNT__
LET qty = to_integer(round(random() * 19) + 1)
INSERT (o)-[:HAS_ORDER_PRODUCT {Quantity: qty, UnitPrice: p.UnitPrice, Discount: random() * 0.07}]->(p)
RETURN o.OrderID AS OrderID, p.ProductName AS ProductName, qty AS Quantity
"""


def run_customer_order(tx: Tx):
    line_count = int(math.floor(random.random() * 10 + 1 + 0.5))   # same distribution as round(rand()*10 + 1)
    rows = tx.run(CUSTOMER_ORDER_QUERY.replace("__LINE_COUNT__", str(line_count)))
    return [(r["OrderID"], r["ProductName"], r["Quantity"]) for r in rows]


def iterate_customer_order(client: GqldbClient, stats: RunStats, graph: str) -> None:
    lines = execute_with_retry(client, run_customer_order, stats, graph)
    if lines:
        order_id = lines[0][0]
        items = ", ".join(f"{name} x{int(qty)}" for _, name, qty in lines)
        log.info(f"Created Order {order_id} ({len(lines)} line(s)): {items}")
    else:
        stats.no_op += 1
        log.warning("Customer Order creation matched no eligible Employee/Customer/Product -- check base data")


# ---------------------------------------------------------------------------
# Loop: po-vetting
# ---------------------------------------------------------------------------
#
# Each execution checks which vetting sub-steps currently have eligible
# candidates, then randomly picks ONE (weighted so approval/passthrough is
# far more likely than rejection) and applies it to a single PurchaseOrder.
# Rejection is deliberately not a dead end: po_resubmit is itself one of the
# weighted actions, eligible whenever a RejectedPoS item hasn't already been
# resubmitted, so nothing can get permanently stuck.
#
# po_resubmit's eligibility check mirrors the execute query's own low-stock
# filter, and re-matches its Supplier via the rejected PO's own
# PO_FOR_SUPPLIER edge (both carried over from the Neo4j version's fixes).
#
# Concurrency: every action bumps OCCVersion on its chosen PurchaseOrder right
# before writing (@OCC(po)), replacing apoc.lock.nodes([po]) + re-check. Two
# processes that pick the same PO now conflict at COMMIT; the loser retries,
# sees the PO already vetted, and no-ops -- no more "double vetting".
#
# KNOWN GAP (mirrors the original script -- no L3 passthrough exists): a PO
# costing more than Level3Approver's ApprovalLimit has no approval path at
# all. Such a PO will sit in NewPoS indefinitely.

@dataclass
class VettingAction:
    name: str
    weight: int
    eligibility_query: str   # returns a single EligibleCount column
    execute_query: str       # performs the mutation; returns PONumber (+ extra columns)


PO_COST = "sum(poi.POqt * (i.UnitPrice * poi.POPriceDiscount))"

# L1: no prerequisite level. L2/L3: require the prior level's approval and
# must not already be vetted at their own level.
_L1_NOT_VETTED = "NOT EXISTS { MATCH (po)-[:HAS_L1_PO_APPROVAL|HAS_L1_PO_REJECTION]-() }"
_L2_PREREQ_PATTERN = "(po)-[:HAS_L1_PO_APPROVAL]-()"
_L2_NOT_VETTED = "NOT EXISTS { MATCH (po)-[:HAS_L2_PO_APPROVAL|HAS_L2_PO_REJECTION]-() }"
_L3_PREREQ_PATTERN = "(po)-[:HAS_L2_PO_APPROVAL]-()"
_L3_NOT_VETTED = "NOT EXISTS { MATCH (po)-[:HAS_L3_PO_APPROVAL|HAS_L3_PO_REJECTION]-() }"


def _po_level_eligibility(level: str, prereq_pattern: str, not_vetted: str, cost_condition: str) -> str:
    extra_match = f", {prereq_pattern}" if prereq_pattern else ""
    return f"""
    MATCH (:NewPoS {{Name: "NewPoS"}})-[]->(po:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product),
          (ro:RolE {{Title: "{level}"}}){extra_match}
    WHERE {not_vetted}
    RETURN po, ro, {PO_COST} AS POCost
    NEXT
    FILTER {cost_condition}
    RETURN count(po) AS EligibleCount
    """


def _po_level_execute(level: str, level_tag: str, prereq_pattern: str, not_vetted: str,
                      cost_condition: str, outcome: str) -> str:
    """outcome: 'reject' (-> RejectedPoS), 'approve_final' (-> ApprovedPoS), 'passthrough' (approval edge only)."""
    extra_match = f", {prereq_pattern}" if prereq_pattern else ""
    if outcome == "reject":
        state_match = ', (a:RejectedPoS {Name: "RejectedPoS"})'
        writes = (f'INSERT (po)-[:HAS_{level_tag}_PO_REJECTION {{Date: local_datetime(), Comment: "Rejected by {level_tag} (stress test)."}}]->(l),\n'
                  f'               (a)-[:IS_REJECTED_PO_STATE {{Date: local_datetime()}}]->(po)\n'
                  f'        DELETE np')
    elif outcome == "approve_final":
        state_match = ', (a:ApprovedPoS {Name: "ApprovedPoS"})'
        writes = (f'INSERT (po)-[:HAS_{level_tag}_PO_APPROVAL {{Date: local_datetime(), Comment: "Approved by {level_tag} (stress test)."}}]->(l),\n'
                  f'               (a)-[:IS_APPROVED_PO_STATE {{Date: local_datetime()}}]->(po)\n'
                  f'        DELETE np')
    elif outcome == "passthrough":
        state_match = ""
        next_level = {"L1": "L2", "L2": "L3"}[level_tag]
        writes = (f'INSERT (po)-[:HAS_{level_tag}_PO_APPROVAL {{Date: local_datetime(), '
                  f'Comment: "Approved by {level_tag}, passed to {next_level} (stress test)."}}]->(l)')
    else:
        raise ValueError(outcome)
    carried = "a, ro, l, np, po" if state_match else "ro, l, np, po"
    return f"""
        MATCH (l:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {{Title: "{level}"}}){state_match}
        ORDER BY random() LIMIT 1
        MATCH (:NewPoS {{Name: "NewPoS"}})-[np]->(po:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product){extra_match}
        WHERE {not_vetted}
        RETURN {carried}, {PO_COST} AS POCost
        NEXT
        FILTER {cost_condition}
        ORDER BY random() LIMIT 1
        @OCC(po)
        {writes}
        RETURN po.PONumber AS PONumber, POCost AS Cost
        """


def _po_action(name: str, weight: int, level: str, tag: str, prereq: str, not_vetted: str, cost: str, outcome: str) -> VettingAction:
    elig_where = not_vetted
    if prereq:
        elig_where = f"EXISTS {{ MATCH {prereq} }} AND {not_vetted}"
    return VettingAction(
        name, weight,
        _po_level_eligibility(level, "", elig_where, cost),
        _po_level_execute(level, tag, prereq, not_vetted, cost, outcome),
    )


_COST_ABOVE_BASE = "POCost > ro.ApprovalBase"
_COST_WITHIN = "POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit"
_COST_OVER_LIMIT = "POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit"

_LOW_STOCK_PIPELINE = """
        MATCH (rpo)-[:HAS_PO_ITEM]->(p)<-[:SUPPLIES]-(s),
              (p)<-[:IS_AVAILABLE_PRODUCT]-(:ProductStatusAvailablE),
              (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
        OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p)
        RETURN __KEEP__, p, r, i, sum(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty
        NEXT
        OPTIONAL MATCH (p)<-[op:HAS_ORDER_PRODUCT]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
        RETURN __KEEP__, p, r, i, AlreadyPendingQty, sum(coalesce(op.Quantity, 0)) AS OpenOrderQty
        NEXT
        FILTER i.UnitsInStock + AlreadyPendingQty - OpenOrderQty - (r.StockThreshold * 0.5) <= r.StockThreshold
"""

PO_VETTING_ACTIONS: list[VettingAction] = [
    _po_action("l1_reject",              1, "Level1Approver", "L1", "",                 _L1_NOT_VETTED, _COST_ABOVE_BASE, "reject"),
    _po_action("l1_approve_final",       5, "Level1Approver", "L1", "",                 _L1_NOT_VETTED, _COST_WITHIN,     "approve_final"),
    _po_action("l1_approve_passthrough", 5, "Level1Approver", "L1", "",                 _L1_NOT_VETTED, _COST_OVER_LIMIT, "passthrough"),
    _po_action("l2_reject",              1, "Level2Approver", "L2", _L2_PREREQ_PATTERN, _L2_NOT_VETTED, _COST_ABOVE_BASE, "reject"),
    _po_action("l2_approve_final",       5, "Level2Approver", "L2", _L2_PREREQ_PATTERN, _L2_NOT_VETTED, _COST_WITHIN,     "approve_final"),
    _po_action("l2_approve_passthrough", 5, "Level2Approver", "L2", _L2_PREREQ_PATTERN, _L2_NOT_VETTED, _COST_OVER_LIMIT, "passthrough"),
    _po_action("l3_reject",              1, "Level3Approver", "L3", _L3_PREREQ_PATTERN, _L3_NOT_VETTED, _COST_WITHIN,     "reject"),
    _po_action("l3_approve_final",       5, "Level3Approver", "L3", _L3_PREREQ_PATTERN, _L3_NOT_VETTED, _COST_WITHIN,     "approve_final"),
    VettingAction(
        "po_resubmit", 4,
        """
        MATCH (:RejectedPoS)-[:IS_REJECTED_PO_STATE]->(rpo:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(s:Supplier)
        WHERE NOT EXISTS { MATCH ()-[:HAS_PREVIOUS_PO]->(rpo) }
        """ + _LOW_STOCK_PIPELINE.replace("__KEEP__", "rpo, s") + """
        RETURN count(DISTINCT rpo) AS EligibleCount
        """,
        """
        MATCH (re:RejectedPoS)-[:IS_REJECTED_PO_STATE]->(rpo:PurchaseOrder)-[:PO_CREATED_BY]->(e:Employee),
              (rpo)-[:PO_FOR_SUPPLIER]->(s:Supplier),
              (n:NewPoS {Name: "NewPoS"})
        WHERE NOT EXISTS { MATCH ()-[:HAS_PREVIOUS_PO]->(rpo) }
        ORDER BY random() LIMIT 1
        """ + _LOW_STOCK_PIPELINE.replace("__KEEP__", "rpo, e, n, s") + """
        RETURN rpo, e, n, s, collect({ProductID: p.ProductID,
                                      qty: (r.StockThreshold) - (i.UnitsInStock + AlreadyPendingQty - OpenOrderQty) + to_integer(floor(r.StockThreshold / 2))}) AS orderItems
        NEXT
        FILTER size(orderItems) > 0
        @OCC(rpo)
        INSERT (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {PODate: local_datetime()}),
               (po)-[:PO_FOR_SUPPLIER]->(s),
               (po)-[:PO_CREATED_BY]->(e),
               (po)-[:HAS_PREVIOUS_PO {Resubmission_Justification: "Auto-resubmitted after rejection (stress test)."}]->(rpo)
        SET po.PONumber = "PO-" || left(po._id, 5) || right(po._id, 5)
        FOR item IN orderItems
        MATCH (p:Product WHERE p.ProductID = item.ProductID)
        INSERT (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7}]->(p)
        RETURN DISTINCT po.PONumber AS PONumber, rpo.PONumber AS ResubmittedFrom
        """,
    ),
]


def _check_eligibility(tx: Tx, query: str) -> int:
    rows = tx.run(query)
    return int(rows[0].get("EligibleCount") or 0) if rows else 0


def run_weighted_action(tx: Tx, actions: list["VettingAction"]):
    """Shared by po-vetting, rfq-vetting and warehouse-finance: check which
    actions have eligible candidates right now, randomly pick one weighted by
    likelihood, execute it for a single item."""
    eligible = [a for a in actions if _check_eligibility(tx, a.eligibility_query) > 0]
    if not eligible:
        return None
    chosen = random.choices(eligible, weights=[a.weight for a in eligible], k=1)[0]
    rows = tx.run(chosen.execute_query)
    return (chosen.name, rows[0]) if rows else (chosen.name, None)


def iterate_weighted_actions(client: GqldbClient, stats: RunStats, graph: str,
                             actions: list["VettingAction"], empty_message: str) -> None:
    outcome = execute_with_retry(client, lambda tx: run_weighted_action(tx, actions), stats, graph)
    if outcome is None:
        stats.no_op += 1
        log.info(empty_message)
        return
    action_name, details = outcome
    if details is None:
        stats.no_op += 1
        log.warning(f"Action '{action_name}' was eligible but matched nothing at execution time (likely lost a race to another process) -- no-op")
        return
    log.info(f"[{action_name}] {details}")


def iterate_po_vetting(client: GqldbClient, stats: RunStats, graph: str) -> None:
    iterate_weighted_actions(client, stats, graph, PO_VETTING_ACTIONS,
                             "No eligible PO Vetting action this cycle (no NewPoS/RejectedPoS items awaiting action)")


# ---------------------------------------------------------------------------
# Loop: rfq-vetting
# ---------------------------------------------------------------------------
#
# Bridges PO Vetting and the Supplier side: an Approved PO first has to be
# submitted to its Supplier by the Buyer, the Supplier then submits an RFQ
# for it, and the Buyer vets that RFQ (reject/approve/resubmit), using the
# same weighted-eligibility pattern as po-vetting. rfq_resubmit is itself a
# weighted action, so nothing gets stuck.
#
# DESIGN DECISION (carried over): buyer_submit_po has no reject counterpart.
#
# rfq_reject and rfq_approve share the same budget-fit condition; weighted
# random selection (reject=1, approve=5) does the differentiating.
#
# Concurrency: each action bumps OCCVersion on the PO/RFQ it used to lock.
# rfq_approve also SETs every OrderLevel node it updates, so concurrent writes
# to the same OrderLevel conflict on their own.

BUDGET_FITS_CONDITION = "poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost"

_NEW_RFQ_PATTERN = ("(:SubmittedPoS)-[]->(po:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->"
                    "(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po)")

RFQ_VETTING_ACTIONS: list[VettingAction] = [
    VettingAction(
        "buyer_submit_po", 4,
        """
        MATCH (:ApprovedPoS)-[]->(po:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->()
        RETURN count(po) AS EligibleCount
        """,
        """
        MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title: "Buyer"}), (su:SubmittedPoS {Name: "SubmittedPoS"})
        ORDER BY random() LIMIT 1
        MATCH (a:ApprovedPoS {Name: "ApprovedPoS"})-[ap]->(po:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(s:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp)
        ORDER BY random() LIMIT 1
        @OCC(po)
        INSERT (po)-[:HAS_BUYER_PO_APPROVAL {Date: local_datetime(), Comment: "Submitted to Supplier by Buyer (stress test)."}]->(bu),
               (su)-[:IS_SUBMITTED_PO_STATE {Date: local_datetime()}]->(po),
               (snp)-[:IS_SUPPLIER_NEW_PO_STATE {Date: local_datetime()}]->(po),
               (po)-[:HAS_SUPPLIER_NEW_RFQ]->(:PoNewRFQ {Name: "PoNewRFQ"}),
               (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(:PoRejectedRFQ {Name: "PoRejectedRFQ"})
        DELETE ap
        RETURN po.PONumber AS PONumber
        """,
    ),
    VettingAction(
        "supplier_submit_rfq", 4,
        """
        MATCH (:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->()-[]->(po:PurchaseOrder)
        RETURN count(po) AS EligibleCount
        """,
        """
        MATCH (su:Supplier)-[np:HAS_SUPPLIER_NEW_PENDING_POS]->()-[r]->(po:PurchaseOrder)
        ORDER BY random() LIMIT 1
        MATCH (po)-[pq:HAS_PO_ITEM]-(p), (po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr), (su)-[:HAS_SUPPLIER_OPEN_POS]->(sop)
        RETURN su, r, po, snr, sop, collect({ProductID: p.ProductID, qty: pq.POqt, cost: p.UnitPrice * 0.7}) AS rfqItems
        NEXT
        @OCC(po)
        INSERT (rfq:RFQ {RFQDate: local_datetime(),
                         RFQComments: "Thanks for your order, we are able to supply the full PO product request at the discounted price negotiated on our master agreement (stress test)."}),
               (rfq)-[:IS_RFQ_FOR_PO]->(po),
               (rfq)-[:RFQ_FROM_SUPPLIER]->(su),
               (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq),
               (sop)-[:IS_SUPPLIER_OPEN_PO_STATE {Date: local_datetime()}]->(po)
        SET rfq.RFQNumber = "RFQ-" || left(rfq._id, 5) || right(rfq._id, 5)
        DELETE r
        FOR item IN rfqItems
        MATCH (p:Product WHERE p.ProductID = item.ProductID)
        INSERT (rfq)-[:HAS_RFQ_ITEM {RFQqt: item.qty, RFQcost: item.cost}]->(p)
        RETURN DISTINCT rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
        """,
    ),
    VettingAction(
        "rfq_reject", 1,
        f"""
        MATCH {_NEW_RFQ_PATTERN}
        WHERE {BUDGET_FITS_CONDITION}
        RETURN count(DISTINCT rfq) AS EligibleCount
        """,
        f"""
        MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {{Title: "Buyer"}})
        ORDER BY random() LIMIT 1
        MATCH {_NEW_RFQ_PATTERN}, (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(prr)
        WHERE {BUDGET_FITS_CONDITION}
        RETURN DISTINCT bu, po, r, rfq, prr
        NEXT
        ORDER BY random() LIMIT 1
        @OCC(rfq)
        INSERT (rfq)-[:HAS_BUYER_RFQ_REJECTION {{Date: local_datetime(), Comment: "Rejected by Buyer (stress test)."}}]->(bu),
               (prr)-[:IS_SUPPLIER_REJECTED_RFQ_STATE {{Date: local_datetime()}}]->(rfq)
        DELETE r
        RETURN rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
        """,
    ),
    VettingAction(
        "rfq_approve", 5,
        f"""
        MATCH {_NEW_RFQ_PATTERN}
        WHERE {BUDGET_FITS_CONDITION}
        RETURN count(DISTINCT rfq) AS EligibleCount
        """,
        f"""
        MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {{Title: "Buyer"}})
        ORDER BY random() LIMIT 1
        MATCH {_NEW_RFQ_PATTERN}
        WHERE {BUDGET_FITS_CONDITION}
        RETURN DISTINCT bu, po, r, rfq
        NEXT
        ORDER BY random() LIMIT 1
        @OCC(rfq)
        INSERT (rfq)-[:HAS_BUYER_RFQ_APPROVAL {{Date: local_datetime(), Comment: "Approved by Buyer (stress test)."}}]->(bu),
               (po)-[:HAS_APPROVED_RFQ {{Date: local_datetime()}}]->(rfq)
        DELETE r
        MATCH (rfq)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po), (inv)<-[:HAS_INVENTORY_LEVEL]-(p)-[:HAS_SUPPLY_ORDER]-(suo)
        WHERE {BUDGET_FITS_CONDITION}
        SET suo.UnitsOnOrder = suo.UnitsOnOrder + rfi.RFQqt
        RETURN DISTINCT rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
        """,
    ),
    VettingAction(
        "rfq_resubmit", 4,
        """
        MATCH (rrfq:RFQ)<-[:IS_SUPPLIER_REJECTED_RFQ_STATE]-()
        WHERE NOT EXISTS { MATCH ()-[:HAS_PREVIOUS_RFQ]->(rrfq) }
        RETURN count(rrfq) AS EligibleCount
        """,
        """
        MATCH (su:Supplier)<-[:RFQ_FROM_SUPPLIER]-(rrfq:RFQ)<-[:IS_SUPPLIER_REJECTED_RFQ_STATE]-(), (rrfq)-[:IS_RFQ_FOR_PO]-(po:PurchaseOrder)
        WHERE NOT EXISTS { MATCH ()-[:HAS_PREVIOUS_RFQ]->(rrfq) }
        ORDER BY random() LIMIT 1
        MATCH (p)<-[pq:HAS_PO_ITEM]-(po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr)
        RETURN rrfq, su, po, snr, collect({ProductID: p.ProductID, qty: pq.POqt, cost: p.UnitPrice * 0.65}) AS rfqItems
        NEXT
        @OCC(rrfq)
        INSERT (rfq:RFQ {RFQDate: local_datetime(),
                         RFQComments: "Thanks for your order, we are resubmitting our RFQ with updated pricing (stress test)."}),
               (rfq)-[:IS_RFQ_FOR_PO]->(po),
               (rfq)-[:RFQ_FROM_SUPPLIER]->(su),
               (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq),
               (rfq)-[:HAS_PREVIOUS_RFQ {Justification: "Auto-resubmitted after rejection (stress test)."}]->(rrfq)
        SET rfq.RFQNumber = "RFQ-" || left(rfq._id, 5) || right(rfq._id, 5)
        FOR item IN rfqItems
        MATCH (p:Product WHERE p.ProductID = item.ProductID)
        INSERT (rfq)-[:HAS_RFQ_ITEM {RFQqt: item.qty, RFQcost: item.cost}]->(p)
        RETURN DISTINCT rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
        """,
    ),
]


def iterate_rfq_vetting(client: GqldbClient, stats: RunStats, graph: str) -> None:
    iterate_weighted_actions(client, stats, graph, RFQ_VETTING_ACTIONS,
                             "No eligible RFQ Vetting action this cycle (no ApprovedPoS/SupplierNewPoS/RFQ items awaiting action)")


# ---------------------------------------------------------------------------
# Loop: warehouse-finance
# ---------------------------------------------------------------------------
#
# Two independent forward-progress actions, equal weight. warehouse_delivery
# SETs the InventoryLevel/OrderLevel nodes of every line it receives (so two
# concurrent deliveries touching the same Product conflict on their own) and
# bumps OCCVersion on the PO; finance_closure bumps OCCVersion on the PO.
# Either way a second, concurrent attempt on the same PO is refused at COMMIT
# and, on retry, finds the delivery/payment already recorded.

WAREHOUSE_FINANCE_ACTIONS: list[VettingAction] = [
    VettingAction(
        "warehouse_delivery", 5,
        """
        MATCH (p)<-[poi:HAS_PO_ITEM]-(po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(:RFQ)-[rfi:HAS_RFQ_ITEM]->(p)
        WHERE poi.POqt = rfi.RFQqt AND NOT EXISTS { MATCH (po)-[:HAS_WAREHOUSE_DELIVERY]->() }
        RETURN count(DISTINCT po) AS EligibleCount
        """,
        """
        MATCH (wc:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title: "WarehouseClerk"})
        ORDER BY random() LIMIT 1
        MATCH (p)<-[poi:HAS_PO_ITEM]-(po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(:RFQ)-[rfi:HAS_RFQ_ITEM]->(p)
        WHERE poi.POqt = rfi.RFQqt AND NOT EXISTS { MATCH (po)-[:HAS_WAREHOUSE_DELIVERY]->() }
        RETURN DISTINCT wc, po
        NEXT
        ORDER BY random() LIMIT 1
        @OCC(po)
        INSERT (po)-[:HAS_WAREHOUSE_DELIVERY {Date: local_datetime(), Comment: "The products have been received as per PO at the Warehouse and the Inventory Levels have been updated accordingly (stress test)."}]->(wc)
        MATCH (p)<-[poi:HAS_PO_ITEM]-(po)-[:HAS_APPROVED_RFQ]->(:RFQ)-[rfi:HAS_RFQ_ITEM]->(p),
              (p)-[:HAS_INVENTORY_LEVEL]->(inv), (p)-[:HAS_SUPPLY_ORDER]->(suo)
        WHERE poi.POqt = rfi.RFQqt
        SET inv.UnitsInStock = inv.UnitsInStock + rfi.RFQqt,
            inv.LastUpdate = local_datetime(),
            suo.UnitsOnOrder = suo.UnitsOnOrder - rfi.RFQqt
        RETURN DISTINCT po.PONumber AS PONumber
        """,
    ),
    VettingAction(
        "finance_closure", 5,
        """
        MATCH (:PoS)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS)-[r1]->(po:PurchaseOrder)-[:HAS_WAREHOUSE_DELIVERY]->(),
              (po)<-[r2:IS_SUPPLIER_OPEN_PO_STATE]-()
        RETURN count(DISTINCT po) AS EligibleCount
        """,
        """
        MATCH (f:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title: "Finance"})
        ORDER BY random() LIMIT 1
        MATCH (cpo)<-[:HAS_CLOSED_PO_STATE]-(:PoS)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS)-[r1]->(po:PurchaseOrder)-[:HAS_WAREHOUSE_DELIVERY]->(:Employee),
              (po)<-[r2:IS_SUPPLIER_OPEN_PO_STATE]-()<-[]-(:Supplier)-[:HAS_SUPPLIER_CLOSED_POS]->(scp)
        WHERE NOT EXISTS { MATCH (po)-[:HAS_FINANCE_PAYMENT]->() }
        ORDER BY random() LIMIT 1
        @OCC(po)
        INSERT (po)-[:HAS_FINANCE_PAYMENT {Date: local_datetime(), Comment: "The PO has been paid by Finance and the PO is now closed (stress test)."}]->(f),
               (cpo)-[:IS_CLOSED_PO_STATE {Date: local_datetime(), Comment: "The PO has been paid by Finance and the PO is now closed (stress test)."}]->(po),
               (scp)-[:HAS_SUPPLIER_CLOSED_PO_STATE {Date: local_datetime(), Comment: "The PO has been paid by Finance and the PO is now closed (stress test)."}]->(po)
        DELETE r1, r2
        RETURN po.PONumber AS PONumber
        """,
    ),
]


def iterate_warehouse_finance(client: GqldbClient, stats: RunStats, graph: str) -> None:
    iterate_weighted_actions(client, stats, graph, WAREHOUSE_FINANCE_ACTIONS,
                             "No eligible Warehouse/Finance action this cycle (nothing awaiting delivery or closure)")


# ---------------------------------------------------------------------------
# Loop: po-creation
# ---------------------------------------------------------------------------
#
# Single well-defined action. Creates one PO PER QUALIFYING SUPPLIER, not one
# PO total. Subtracts quantity already committed via active POs and via open
# Customer Orders before deciding whether a Product is genuinely low-stock
# (both fixes carried over from the Neo4j version). Like the Neo4j version,
# it takes no lock: two concurrent po-creation processes can both order the
# same shortfall.

PO_CREATION_QUERY = """
MATCH (pa:RolE {Title: "Procurement Assistant"})-[:IS_ACTIVE_ROLE]->(e:Employee), (n:NewPoS {Name: "NewPoS"})
ORDER BY random() LIMIT 1
MATCH (s:Supplier)-[:SUPPLIES]->(p:Product)<-[:IS_AVAILABLE_PRODUCT]-(a:ProductStatusAvailablE),
      (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p)
RETURN e, n, s, p, r, i, sum(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty
NEXT
OPTIONAL MATCH (p)<-[op:HAS_ORDER_PRODUCT]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
RETURN e, n, s, p, r, i, AlreadyPendingQty, sum(coalesce(op.Quantity, 0)) AS OpenOrderQty
NEXT
FILTER i.UnitsInStock + AlreadyPendingQty - OpenOrderQty - (r.StockThreshold * 0.5) <= r.StockThreshold
RETURN e, n, s, collect({ProductID: p.ProductID,
                         qty: (r.StockThreshold) - (i.UnitsInStock + AlreadyPendingQty - OpenOrderQty) + (r.StockThreshold * 2)}) AS orderItems
NEXT
INSERT (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {PODate: local_datetime()}),
       (po)-[:PO_FOR_SUPPLIER]->(s),
       (po)-[:PO_CREATED_BY]->(e)
SET po.PONumber = "PO-" || left(po._id, 5) || right(po._id, 5)
FOR item IN orderItems
MATCH (p:Product WHERE p.ProductID = item.ProductID)
INSERT (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7}]->(p)
RETURN DISTINCT po.PONumber AS PONumber, s.SupplierID AS SupplierID, size(orderItems) AS ItemCount
"""


def run_po_creation(tx: Tx):
    rows = tx.run(PO_CREATION_QUERY)
    return [(r["PONumber"], r["SupplierID"], r["ItemCount"]) for r in rows]


def iterate_po_creation(client: GqldbClient, stats: RunStats, graph: str) -> None:
    pos = execute_with_retry(client, run_po_creation, stats, graph)
    if pos:
        summary = ", ".join(f"{pn} (Supplier {sid}, {ic} item(s))" for pn, sid, ic in pos)
        log.info(f"Created {len(pos)} PO(s): {summary}")
    else:
        stats.no_op += 1
        log.info("No PO Creation this cycle (no Supplier currently has qualifying low-stock Products, or no eligible employee)")


# ---------------------------------------------------------------------------
# Loop: order-fulfillment
# ---------------------------------------------------------------------------
#
# Single well-defined action. Requires and then DELETEs the Order's
# IS_OPEN_ORDER_STATE edge, so a fulfilled Order can't be re-selected.
# Keeps ORDER BY o.OrderDate (oldest-first) -- a real business rule.
# Only fulfills an Order if EVERY line has sufficient stock.
#
# Concurrency (replaces apoc.lock.nodes([inv...] + [o]) + re-check): this
# statement SETs every InventoryLevel node the Order touches, and bumps
# OCCVersion on the Order. If two processes fulfill Orders that share a
# Product, or pick the same Order, the second COMMIT is refused (3011), the
# retry re-reads current stock, and an Order that no longer has full stock
# coverage is simply skipped -- inventory can't go negative.

ORDER_FULFILLMENT_QUERY = """
MATCH (wc:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title: "WarehouseClerk"}), (s:Shipper)<-[:HAS_SHIPPER]-(si:ShipInfo)
ORDER BY random() LIMIT 1
MATCH (op:OrderStatusOpeN {Status: "Open"})-[r:IS_OPEN_ORDER_STATE]->(o:Order)-[details:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
RETURN wc, si, s, op, r, o,
       count(details) AS TotalLines,
       sum(CASE WHEN inv.UnitsInStock > details.Quantity THEN 1 ELSE 0 END) AS LinesWithStock
NEXT
FILTER TotalLines = LinesWithStock
ORDER BY o.OrderDate
LIMIT 1
@OCC(o)
MATCH (a)<-[:HAS_CUSTOMER_ADDRESS]-(:Customer)<-[:HAS_ORDER_CUSTOMER]-(o)
MATCH (f:OrderStatusFulfilleD {Status: "Fulfilled"})
INSERT (i:ShipInfo {ShippedDate: local_datetime(), ShipName: si.ShipName, Freight: round(random() * 100, 2)}),
       (o)-[:HAS_SHIPMENT_INFO]->(i),
       (i)-[:HAS_SHIPPER]->(s),
       (i)-[:HAS_SHIPMENT_ADDRESS]->(a),
       (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: local_datetime()}]->(o),
       (o)-[:HAS_WAREHOUSE_FULFILLMENT {Date: local_datetime(), Comment: "Order picked, packed, and shipped by the Warehouse Clerk."}]->(wc)
SET i.ShippmentID = "SH-" || i._id
DELETE r
MATCH (o)-[line:HAS_ORDER_PRODUCT]->(:Product)-[:HAS_INVENTORY_LEVEL]->(stock:InventoryLevel)
SET stock.UnitsInStock = stock.UnitsInStock - line.Quantity,
    stock.LastUpdate = local_datetime()
RETURN DISTINCT o.OrderID AS OrderID
"""


def run_order_fulfillment(tx: Tx):
    rows = tx.run(ORDER_FULFILLMENT_QUERY)
    return rows[0]["OrderID"] if rows else None


def iterate_order_fulfillment(client: GqldbClient, stats: RunStats, graph: str) -> None:
    order_id = execute_with_retry(client, run_order_fulfillment, stats, graph)
    if order_id:
        log.info(f"Fulfilled Order {order_id}")
    else:
        stats.no_op += 1
        log.info("No Order Fulfillment this cycle (no Open Order currently has full stock coverage for every line)")


# ---------------------------------------------------------------------------
# Loop dispatch table -- all six loops implemented.
# ---------------------------------------------------------------------------

LOOPS: dict[str, Callable[[GqldbClient, RunStats, str], None]] = {
    "customer-order": iterate_customer_order,
    "po-creation": iterate_po_creation,
    "po-vetting": iterate_po_vetting,
    "rfq-vetting": iterate_rfq_vetting,
    "warehouse-finance": iterate_warehouse_finance,
    "order-fulfillment": iterate_order_fulfillment,
}


# ---------------------------------------------------------------------------
# Rate-limited runner
# ---------------------------------------------------------------------------

_shutdown_requested = False


def _handle_sigint(signum, frame):
    global _shutdown_requested
    _shutdown_requested = True
    log.info("Shutdown requested -- finishing current execution, then stopping...")


def run_loop(client: GqldbClient, loop_name: str, rate_per_minute: float, duration_seconds: float | None, graph: str) -> None:
    fn = LOOPS[loop_name]
    interval = 60.0 / rate_per_minute
    stats = RunStats()

    signal.signal(signal.SIGINT, _handle_sigint)
    log.info(f"Starting loop '{loop_name}' at {rate_per_minute}/min (every {interval:.2f}s) against graph '{graph}'"
             f" (OCC_TOUCH={OCC_TOUCH}). Ctrl+C to stop.")

    while not _shutdown_requested:
        iteration_start = time.perf_counter()
        fn(client, stats, graph)
        stats.executions += 1

        if duration_seconds is not None and (time.perf_counter() - stats.start_time) >= duration_seconds:
            break

        elapsed = time.perf_counter() - iteration_start
        sleep_for = max(0.0, interval - elapsed)
        if sleep_for == 0.0:
            log.warning(f"Execution took {elapsed:.2f}s, longer than the {interval:.2f}s interval -- falling behind target rate")
        time.sleep(sleep_for)

    total_elapsed = time.perf_counter() - stats.start_time
    achieved_rate = (stats.executions / total_elapsed * 60.0) if total_elapsed > 0 else 0.0
    log.info(
        f"=== '{loop_name}' summary === "
        f"executions={stats.executions} retries={stats.retries} errors={stats.errors} "
        f"no_op={stats.no_op} elapsed={total_elapsed:.1f}s achieved_rate={achieved_rate:.2f}/min"
    )


def connect_from_env() -> tuple[GqldbClient, str]:
    """Builds and logs in a GqldbClient from ULTIPA_* environment variables.
    Shared with run_gql_script.py."""
    user = os.environ.get("ULTIPA_USER", "root")
    password = os.environ.get("ULTIPA_PASSWORD")
    graph = os.environ.get("ULTIPA_GRAPH", "NorthWindPLUS")
    if not password:
        raise SystemExit("Set the ULTIPA_PASSWORD environment variable before running.")
    client = GqldbClient(make_config())
    client.login(user, password)
    client.use_graph(graph)
    return client, graph


def make_config() -> GqldbConfig:
    """GqldbConfig from ULTIPA_HOSTS / ULTIPA_TIMEOUT / ULTIPA_TLS.
    TLS: the gqldb driver only opens an encrypted channel when ssl_context is
    set. Off by default (a plain-text instance on port 443 rejected TLS with
    WRONG_VERSION_NUMBER); set ULTIPA_TLS=1 for an instance that requires it."""
    import ssl
    hosts = [h.strip() for h in os.environ.get("ULTIPA_HOSTS", "localhost:9000").split(",") if h.strip()]
    timeout = int(os.environ.get("ULTIPA_TIMEOUT", "60"))   # seconds per query (driver default is 30)
    tls_env = os.environ.get("ULTIPA_TLS", "").strip()
    use_tls = tls_env == "1"
    return GqldbConfig(hosts=hosts, timeout=timeout,
                       ssl_context=ssl.create_default_context() if use_tls else None)


def main() -> None:
    parser = argparse.ArgumentParser(description="NorthWind PLUS concurrency stress harness (Ultipa GQLDB).")
    parser.add_argument("--loop", required=True, choices=sorted(LOOPS.keys()),
                        help="Which workflow step to run repeatedly.")
    parser.add_argument("--rate", type=float, default=6.0, help="Executions per minute (default: 6).")
    parser.add_argument("--duration", type=float, default=None, help="Stop after this many seconds (default: run until Ctrl+C).")
    parser.add_argument("--print-queries", action="store_true",
                        help="Print every GQL statement this loop can send (after @OCC expansion) and exit, without connecting.")
    args = parser.parse_args()

    if args.print_queries:
        _print_queries(args.loop)
        return

    client, graph = connect_from_env()
    try:
        run_loop(client, args.loop, args.rate, args.duration, graph)
    finally:
        try:
            client.close()
        except Exception:
            pass


def _print_queries(loop_name: str) -> None:
    """Debug helper: paste the output into Ultipa Manager to test one statement at a time."""
    single = {
        "customer-order": [("customer_order", CUSTOMER_ORDER_QUERY.replace("__LINE_COUNT__", "3"))],
        "po-creation": [("po_creation", PO_CREATION_QUERY)],
        "order-fulfillment": [("order_fulfillment", ORDER_FULFILLMENT_QUERY)],
    }
    weighted = {"po-vetting": PO_VETTING_ACTIONS, "rfq-vetting": RFQ_VETTING_ACTIONS,
                "warehouse-finance": WAREHOUSE_FINANCE_ACTIONS}
    if loop_name in single:
        for name, q in single[loop_name]:
            print(f"// ---- {name} ----\n{name_anonymous_insert_elements(_occify(q)).strip()}\n")
    else:
        for a in weighted[loop_name]:
            print(f"// ---- {a.name} (eligibility) ----\n{name_anonymous_insert_elements(_occify(a.eligibility_query)).strip()}\n")
            print(f"// ---- {a.name} (execute, weight {a.weight}) ----\n{name_anonymous_insert_elements(_occify(a.execute_query)).strip()}\n")


if __name__ == "__main__":
    main()
