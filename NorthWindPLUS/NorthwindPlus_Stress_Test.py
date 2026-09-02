#!/usr/bin/env python3
"""
NorthWind PLUS Concurrency Stress Harness
==========================================

Runs one workflow step of the NorthWind PLUS Graph Data Model as an
independent, rate-limited, indefinitely-repeating loop -- intended to be
launched as several separate OS processes (one per --loop) so they behave
like genuinely independent real-world actors (Sales, Procurement,
Warehouse, Finance, Suppliers) hammering the same graph concurrently.

Usage:
    export NEO4J_URI="neo4j://localhost:7687"
    export NEO4J_USER="neo4j"
    export NEO4J_PASSWORD="your-password"
    export NEO4J_DATABASE="your-database"

    python NorthwindPlus_Stress_Test.py --loop customer-order --rate 6
    python NorthwindPlus_Stress_Test.py --loop po-creation --rate 2 &
    python NorthwindPlus_Stress_Test.py --loop po-vetting --rate 4 &
    python NorthwindPlus_Stress_Test.py --loop rfq-vetting --rate 4 &
    python NorthwindPlus_Stress_Test.py --loop warehouse-finance --rate 4 &
    python NorthwindPlus_Stress_Test.py --loop order-fulfillment --rate 4 &
    ... (launch each loop as its own process/terminal)

--rate is executions per minute. Ctrl+C stops a loop cleanly and prints a
summary (executions, retries, errors, achieved rate).

All six loops are now implemented -- the full pipeline can run concurrently:
    customer-order    -- creates one random Open Customer Order with 1-11 lines
    po-creation       -- creates one PO per Supplier currently below restock threshold
    po-vetting        -- L1/L2/L3 approve/reject/passthrough + rejected-PO resubmission
    rfq-vetting       -- Buyer submits PO to Supplier, Supplier submits RFQ,
                          Buyer approves/rejects/resubmits the RFQ
    warehouse-finance -- Warehouse Clerk receives a delivered PO's items (updates
                          Inventory/OrderLevel), Finance pays and closes the PO
    order-fulfillment -- ships an Open Customer Order once every line has stock,
                          decrementing Inventory (oldest Order served first)

Each loop plugs into the same LOOPS dispatch table and reuses
execute_with_retry() and the rate limiter below -- adding a seventh loop
later needs no changes anywhere else in this file.

Why this file is so small
--------------------------
Notice what's deliberately absent: no approval-threshold constants, no
state-machine definitions, no hardcoded rule for when a PO needs Level 2 or
Level 3 sign-off, no validation logic for what makes an RFQ "fit budget."
Search this file for a literal 2000, 4000, or 20000 -- you won't find one
outside a Cypher string. Every dollar threshold, every "who can approve
what," lives on RolE.ApprovalBase/ApprovalLimit in the graph and is read
fresh at query time. The Collection (hub) nodes and their relationships ARE
the state machine; GRAPH TYPE enforces what's structurally valid. This
file's job is orchestration only: pick a rate, open a transaction, run one
Cypher statement, retry on contention, log the result. Every action below
reduces to a name, a weight, and two strings of Cypher -- the graph does
the rest. That's the practical payoff of the Graph-Native approach this
whole project demonstrates: application code shrinks to plumbing once the
business logic lives in the data model itself, rather than being
re-implemented (and kept in sync by hand) in every application that
touches the graph.
"""

from __future__ import annotations

import argparse
import logging
import os
import random
import signal
import sys
import time
from dataclasses import dataclass, field
from typing import Callable

from neo4j import GraphDatabase, Driver, NotificationDisabledClassification
from neo4j.exceptions import TransientError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("northwind-stress")


# ---------------------------------------------------------------------------
# Retry-on-deadlock wrapper
# ---------------------------------------------------------------------------

@dataclass
class RunStats:
    executions: int = 0
    retries: int = 0
    errors: int = 0
    no_op: int = 0          # executions where the query ran but matched nothing
    start_time: float = field(default_factory=time.perf_counter)


def execute_with_retry(driver: Driver, work_fn: Callable, stats: RunStats, database: str, max_retries: int = 5):
    """Runs work_fn inside session.execute_write(), which retries
    automatically on Neo4j's own TransientError classification (deadlocks,
    lock timeouts). We wrap it a second time only to count and log retries
    for our own stress-test visibility -- the driver does the actual retry.
    database is applied here, at session level, which is where the driver
    actually reads it -- see the no-op note at driver construction above."""
    attempt = 0
    while True:
        try:
            with driver.session(database=database) as session:
                result = session.execute_write(work_fn)
            return result
        except TransientError as exc:
            attempt += 1
            stats.retries += 1
            if attempt > max_retries:
                log.error(f"Gave up after {max_retries} retries: {exc}")
                stats.errors += 1
                return None
            wait = min(2 ** attempt * 0.1, 2.0) + random.uniform(0, 0.1)
            log.warning(f"Transient error (attempt {attempt}/{max_retries}), retrying in {wait:.2f}s: {exc}")
            time.sleep(wait)
        except Exception as exc:
            log.error(f"Non-retryable error: {exc}")
            stats.errors += 1
            return None


# ---------------------------------------------------------------------------
# Loop: customer-order
# ---------------------------------------------------------------------------

CUSTOMER_ORDER_QUERY = """
MATCH (e:Employee)-[]-(:RolE {Title: "Sales Representative"}), (op:OrderStatusOpeN {Status: "Open"})
WITH e, op ORDER BY rand() LIMIT 1
MATCH (c:Customer)
WITH e, c, op ORDER BY rand() LIMIT 1
CREATE (o:Order {
    OrderID: "CO-" + left(randomUUID(), 3) + right(randomUUID(), 3),
    OrderDate: datetime(),
    RequiredDate: datetime() + duration("P7D")
})<-[:IS_OPEN_ORDER_STATE]-(op)
CREATE (o)-[:HAS_ORDER_CUSTOMER]->(c)
CREATE (o)-[:SOLD_BY]->(e)
WITH o
MATCH (p:Product)-[]-(:ProductStatusAvailablE {Status: "Available"})
ORDER BY rand() LIMIT toInteger(round(rand() * 10 + 1))
WITH o, p, toInteger(round(rand() * 19) + 1) AS qty
CREATE (o)-[:HAS_ORDER_PRODUCT {Quantity: qty, UnitPrice: p.UnitPrice, Discount: 0.0}]->(p)
RETURN o.OrderID AS OrderID, p.ProductName AS ProductName, qty AS Quantity
"""


def run_customer_order(tx):
    result = tx.run(CUSTOMER_ORDER_QUERY)
    return [(r["OrderID"], r["ProductName"], r["Quantity"]) for r in result]


def iterate_customer_order(driver: Driver, stats: RunStats, database: str) -> None:
    lines = execute_with_retry(driver, run_customer_order, stats, database)
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
# resubmitted, so nothing can get permanently stuck -- see the design
# discussion this loop implements.
#
# FIXED (previously a known gap): po_resubmit's eligibility check now mirrors
# the execute query's own low-stock filter, not just "hasn't been resubmitted
# yet." Without this, a rejected PO whose Products had since restocked above
# threshold stayed "eligible" forever -- it would keep getting picked, keep
# producing nothing (the size(orderItems) > 0 guard in execute blocked the
# CREATE), and the loop would appear stuck. Confirmed via a real test run
# where po_resubmit no-op'd 11 times in a row once it became the only
# eligible action left.
#
# KNOWN GAP (mirrors the original script -- no L3 passthrough exists): a PO
# costing more than Level3Approver's ApprovalLimit has no approval path at
# all. This loop won't invent one -- such a PO will simply never appear
# eligible for any action and will sit in NewPoS indefinitely, same as it
# would in a single run of the base script.

@dataclass
class VettingAction:
    name: str
    weight: int
    eligibility_query: str   # returns a single EligibleCount column
    execute_query: str       # performs the mutation; returns PONumber (+ extra columns)


def _po_level_eligibility(level: str, extra_match: str, extra_where: str, cost_condition: str) -> str:
    return f"""
    MATCH (:NewPoS {{Name:"NewPoS"}})-[]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product),
          (ro:RolE {{Title:"{level}"}}) {extra_match}
    WHERE {extra_where}
    WITH po, ro, SUM((id.POqt * (i.UnitPrice * id.POPriceDiscount))) AS POCost
    WHERE {cost_condition}
    RETURN count(po) AS EligibleCount
    """


# L1: no prerequisite level. L2/L3: require the prior level's approval and
# must not already be vetted at their own level.
_L1_NOT_VETTED = "NOT (po)-[:HAS_L1_PO_APPROVAL|HAS_L1_PO_REJECTION]-()"
_L2_PREREQ = "(po)-[:HAS_L1_PO_APPROVAL]-()"
_L2_NOT_VETTED = "NOT (po)-[:HAS_L2_PO_APPROVAL|HAS_L2_PO_REJECTION]-()"
_L3_PREREQ = "(po)-[:HAS_L2_PO_APPROVAL]-()"
_L3_NOT_VETTED = "NOT (po)-[:HAS_L3_PO_APPROVAL|HAS_L3_PO_REJECTION]-()"

PO_VETTING_ACTIONS: list[VettingAction] = [
    VettingAction(
        "l1_reject", 1,
        _po_level_eligibility("Level1Approver", "", _L1_NOT_VETTED, "POCost > ro.ApprovalBase"),
        f"""
        MATCH (l:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {{Title:"Level1Approver"}}), (a:RejectedPoS {{Name:"RejectedPoS"}})
        WITH a, ro, l ORDER BY rand() LIMIT 1
        MATCH (:NewPoS {{Name:"NewPoS"}})-[np]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)
        WHERE {_L1_NOT_VETTED}
        WITH a, ro, l, np, po, SUM((id.POqt * (i.UnitPrice * id.POPriceDiscount))) AS POCost
        WHERE POCost > ro.ApprovalBase
        WITH a, ro, l, np, po, POCost ORDER BY rand() LIMIT 1
        CREATE (po)-[:HAS_L1_PO_REJECTION {{Date:datetime(), Comment:"Rejected by L1 (stress test)."}}]->(l),
               (a)-[:IS_REJECTED_PO_STATE {{Date:datetime()}}]->(po)
        DELETE np
        RETURN po.PONumber AS PONumber, POCost AS Cost
        """,
    ),
    VettingAction(
        "l1_approve_final", 5,
        _po_level_eligibility("Level1Approver", "", _L1_NOT_VETTED, "POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit"),
        f"""
        MATCH (l:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {{Title:"Level1Approver"}}), (a:ApprovedPoS {{Name:"ApprovedPoS"}})
        WITH a, ro, l ORDER BY rand() LIMIT 1
        MATCH (:NewPoS {{Name:"NewPoS"}})-[np]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)
        WHERE {_L1_NOT_VETTED}
        WITH a, ro, l, np, po, SUM((id.POqt * (i.UnitPrice * id.POPriceDiscount))) AS POCost
        WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
        WITH a, ro, l, np, po, POCost ORDER BY rand() LIMIT 1
        CREATE (po)-[:HAS_L1_PO_APPROVAL {{Date:datetime(), Comment:"Approved by L1 (stress test)."}}]->(l),
               (a)-[:IS_APPROVED_PO_STATE {{Date:datetime()}}]->(po)
        DELETE np
        RETURN po.PONumber AS PONumber, POCost AS Cost
        """,
    ),
    VettingAction(
        "l1_approve_passthrough", 5,
        _po_level_eligibility("Level1Approver", "", _L1_NOT_VETTED, "POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit"),
        f"""
        MATCH (l:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {{Title:"Level1Approver"}})
        WITH ro, l ORDER BY rand() LIMIT 1
        MATCH (:NewPoS {{Name:"NewPoS"}})-[np]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)
        WHERE {_L1_NOT_VETTED}
        WITH ro, l, np, po, SUM((id.POqt * (i.UnitPrice * id.POPriceDiscount))) AS POCost
        WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
        WITH ro, l, np, po, POCost ORDER BY rand() LIMIT 1
        CREATE (po)-[:HAS_L1_PO_APPROVAL {{Date:datetime(), Comment:"Approved by L1, passed to L2 (stress test)."}}]->(l)
        RETURN po.PONumber AS PONumber, POCost AS Cost
        """,
    ),
    VettingAction(
        "l2_reject", 1,
        _po_level_eligibility("Level2Approver", "", f"{_L2_PREREQ} AND {_L2_NOT_VETTED}", "POCost > ro.ApprovalBase"),
        f"""
        MATCH (l:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {{Title:"Level2Approver"}}), (a:RejectedPoS {{Name:"RejectedPoS"}})
        WITH a, ro, l ORDER BY rand() LIMIT 1
        MATCH (:NewPoS {{Name:"NewPoS"}})-[np]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product), {_L2_PREREQ}
        WHERE {_L2_NOT_VETTED}
        WITH a, ro, l, np, po, SUM((id.POqt * (i.UnitPrice * id.POPriceDiscount))) AS POCost
        WHERE POCost > ro.ApprovalBase
        WITH a, ro, l, np, po, POCost ORDER BY rand() LIMIT 1
        CREATE (po)-[:HAS_L2_PO_REJECTION {{Date:datetime(), Comment:"Rejected by L2 (stress test)."}}]->(l),
               (a)-[:IS_REJECTED_PO_STATE {{Date:datetime()}}]->(po)
        DELETE np
        RETURN po.PONumber AS PONumber, POCost AS Cost
        """,
    ),
    VettingAction(
        "l2_approve_final", 5,
        _po_level_eligibility("Level2Approver", "", f"{_L2_PREREQ} AND {_L2_NOT_VETTED}", "POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit"),
        f"""
        MATCH (l:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {{Title:"Level2Approver"}}), (a:ApprovedPoS {{Name:"ApprovedPoS"}})
        WITH a, ro, l ORDER BY rand() LIMIT 1
        MATCH (:NewPoS {{Name:"NewPoS"}})-[np]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product), {_L2_PREREQ}
        WHERE {_L2_NOT_VETTED}
        WITH a, ro, l, np, po, SUM((id.POqt * (i.UnitPrice * id.POPriceDiscount))) AS POCost
        WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
        WITH a, ro, l, np, po, POCost ORDER BY rand() LIMIT 1
        CREATE (po)-[:HAS_L2_PO_APPROVAL {{Date:datetime(), Comment:"Approved by L2 (stress test)."}}]->(l),
               (a)-[:IS_APPROVED_PO_STATE {{Date:datetime()}}]->(po)
        DELETE np
        RETURN po.PONumber AS PONumber, POCost AS Cost
        """,
    ),
    VettingAction(
        "l2_approve_passthrough", 5,
        _po_level_eligibility("Level2Approver", "", f"{_L2_PREREQ} AND {_L2_NOT_VETTED}", "POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit"),
        f"""
        MATCH (l:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {{Title:"Level2Approver"}})
        WITH ro, l ORDER BY rand() LIMIT 1
        MATCH (:NewPoS {{Name:"NewPoS"}})-[np]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product), {_L2_PREREQ}
        WHERE {_L2_NOT_VETTED}
        WITH ro, l, np, po, SUM((id.POqt * (i.UnitPrice * id.POPriceDiscount))) AS POCost
        WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
        WITH ro, l, np, po, POCost ORDER BY rand() LIMIT 1
        CREATE (po)-[:HAS_L2_PO_APPROVAL {{Date:datetime(), Comment:"Approved by L2, passed to L3 (stress test)."}}]->(l)
        RETURN po.PONumber AS PONumber, POCost AS Cost
        """,
    ),
    VettingAction(
        "l3_reject", 1,
        _po_level_eligibility("Level3Approver", "", f"{_L3_PREREQ} AND {_L3_NOT_VETTED}", "POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit"),
        f"""
        MATCH (l:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {{Title:"Level3Approver"}}), (a:RejectedPoS {{Name:"RejectedPoS"}})
        WITH a, ro, l ORDER BY rand() LIMIT 1
        MATCH (:NewPoS {{Name:"NewPoS"}})-[np]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product), {_L3_PREREQ}
        WHERE {_L3_NOT_VETTED}
        WITH a, ro, l, np, po, SUM((id.POqt * (i.UnitPrice * id.POPriceDiscount))) AS POCost
        WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
        WITH a, ro, l, np, po, POCost ORDER BY rand() LIMIT 1
        CREATE (po)-[:HAS_L3_PO_REJECTION {{Date:datetime(), Comment:"Rejected by L3 (stress test)."}}]->(l),
               (a)-[:IS_REJECTED_PO_STATE {{Date:datetime()}}]->(po)
        DELETE np
        RETURN po.PONumber AS PONumber, POCost AS Cost
        """,
    ),
    VettingAction(
        "l3_approve_final", 5,
        _po_level_eligibility("Level3Approver", "", f"{_L3_PREREQ} AND {_L3_NOT_VETTED}", "POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit"),
        f"""
        MATCH (l:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {{Title:"Level3Approver"}}), (a:ApprovedPoS {{Name:"ApprovedPoS"}})
        WITH a, ro, l ORDER BY rand() LIMIT 1
        MATCH (:NewPoS {{Name:"NewPoS"}})-[np]->(po:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product), {_L3_PREREQ}
        WHERE {_L3_NOT_VETTED}
        WITH a, ro, l, np, po, SUM((id.POqt * (i.UnitPrice * id.POPriceDiscount))) AS POCost
        WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
        WITH a, ro, l, np, po, POCost ORDER BY rand() LIMIT 1
        CREATE (po)-[:HAS_L3_PO_APPROVAL {{Date:datetime(), Comment:"Approved by L3 (stress test)."}}]->(l),
               (a)-[:IS_APPROVED_PO_STATE {{Date:datetime()}}]->(po)
        DELETE np
        RETURN po.PONumber AS PONumber, POCost AS Cost
        """,
    ),
    VettingAction(
        "po_resubmit", 4,
        """
        MATCH (:RejectedPoS)-[:IS_REJECTED_PO_STATE]->(rpo:PurchaseOrder)
        WHERE NOT ()-[:HAS_PREVIOUS_PO]->(rpo)
        MATCH (rpo)-[:HAS_PO_ITEM]->(p),(s:Supplier)-[:SUPPLIES]->(p)
          <-[:IS_AVAILABLE_PRODUCT]-(:ProductStatusAvailablE),
          (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
        WHERE i.UnitsInStock - (r.StockThreshold * 0.5) <= r.StockThreshold
        RETURN count(DISTINCT rpo) AS EligibleCount
        """,
        """
        MATCH (re:RejectedPoS)-[:IS_REJECTED_PO_STATE]->(rpo:PurchaseOrder)-[:PO_CREATED_BY]->(e:Employee), (n:NewPoS {Name:"NewPoS"})
        WHERE NOT ()-[:HAS_PREVIOUS_PO]->(rpo)
        WITH n, rpo, e ORDER BY rand() LIMIT 1
        MATCH (rpo)-[:HAS_PO_ITEM]->(p),(s:Supplier)-[:SUPPLIES]->(p)
          <-[:IS_AVAILABLE_PRODUCT]-(:ProductStatusAvailablE),
          (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
        WHERE i.UnitsInStock - (r.StockThreshold * 0.5) <= r.StockThreshold
        WITH rpo, e, n, s, COLLECT({
            Product: p,
            qty: (r.StockThreshold) - i.UnitsInStock + (r.StockThreshold / 2)
        }) AS orderItems
        WHERE size(orderItems) > 0
        CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {
            PONumber: "PO-" + left(randomUUID(), 3) + right(randomUUID(), 3),
            PODate: localdatetime()
        })
        CREATE (s)<-[:PO_FOR_SUPPLIER]-(po)
        CREATE (po)-[:PO_CREATED_BY]->(e)
        CREATE (po)-[:HAS_PREVIOUS_PO {Resubmission_Justification: "Auto-resubmitted after rejection (stress test)."}]->(rpo)
        WITH po, orderItems, rpo
        UNWIND orderItems AS item
        MATCH (p:Product {ProductID: item.Product.ProductID})
        MERGE (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7}]->(p)
        RETURN DISTINCT po.PONumber AS PONumber, rpo.PONumber AS ResubmittedFrom
        """,
    ),
]


def _check_eligibility(tx, query: str) -> int:
    record = tx.run(query).single()
    return record["EligibleCount"] if record else 0


def run_weighted_action(tx, actions: list["VettingAction"]):
    """Shared by po-vetting and rfq-vetting (and future loops that fit the
    same shape): check which actions have eligible candidates right now,
    randomly pick one weighted by likelihood, execute it for a single item."""
    eligible = [a for a in actions if _check_eligibility(tx, a.eligibility_query) > 0]
    if not eligible:
        return None
    chosen = random.choices(eligible, weights=[a.weight for a in eligible], k=1)[0]
    record = tx.run(chosen.execute_query).single()
    return (chosen.name, dict(record)) if record else (chosen.name, None)


def iterate_weighted_actions(driver: Driver, stats: RunStats, database: str,
                              actions: list["VettingAction"], empty_message: str) -> None:
    outcome = execute_with_retry(driver, lambda tx: run_weighted_action(tx, actions), stats, database)
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


def iterate_po_vetting(driver: Driver, stats: RunStats, database: str) -> None:
    iterate_weighted_actions(driver, stats, database, PO_VETTING_ACTIONS,
                              "No eligible PO Vetting action this cycle (no NewPoS/RejectedPoS items awaiting action)")


# ---------------------------------------------------------------------------
# Loop: rfq-vetting
# ---------------------------------------------------------------------------
#
# Bridges PO Vetting and the Supplier side: an Approved PO first has to be
# submitted to its Supplier by the Buyer, the Supplier then submits an RFQ
# for it, and the Buyer vets that RFQ (reject/approve/resubmit), using the
# same weighted-eligibility pattern as po-vetting. Same "nothing gets stuck"
# guarantee: rfq_resubmit is itself a weighted action, eligible whenever a
# rejected RFQ hasn't already been resubmitted.
#
# DESIGN DECISION (per instruction): buyer_submit_po has no reject
# counterpart -- an Approved PO is always submitted to its Supplier, never
# declined at that step, even though a real Buyer could decline here too.
# Easy to add a buyer_reject_po action later if that changes.
#
# NOTE on rfq_reject vs rfq_approve eligibility: both use the same
# budget-fit condition the original script uses for both of its own
# reject/approve blocks (RFQ cost <= the PO's allocated budget for those
# items) -- the original script doesn't differentiate the two by a
# business condition either, it just picks arbitrarily under that same
# condition. Weighted random selection (reject=1, approve=5) does the
# actual differentiating here, matching how PO Vetting's L2/L3 reject
# conditions work (a level can reject even what it could also approve).
# An RFQ that costs MORE than its PO's allocated budget is never matched
# by either action and is left unaddressed -- mirrors the original script,
# and in practice shouldn't occur since RFQ items are seeded at cost
# exactly equal to the PO's own price-discount formula.

BUDGET_FITS_CONDITION = "poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost"

RFQ_VETTING_ACTIONS: list[VettingAction] = [
    VettingAction(
        "buyer_submit_po", 4,
        """
        MATCH (:ApprovedPoS)-[]->(po:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->()
        RETURN count(po) AS EligibleCount
        """,
        """
        MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title:"Buyer"}), (su:SubmittedPoS {Name:"SubmittedPoS"})
        WITH su, bu ORDER BY rand() LIMIT 1
        MATCH (a:ApprovedPoS {Name:"ApprovedPoS"})-[ap]->(po:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(s:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp)
        WITH ap, s, bu, su, po, snp ORDER BY rand() LIMIT 1
        CREATE (po)-[:HAS_BUYER_PO_APPROVAL {Date:datetime(), Comment:"Submitted to Supplier by Buyer (stress test)."}]->(bu),
               (su)-[:IS_SUBMITTED_PO_STATE {Date:datetime()}]->(po),
               (snp)-[:IS_SUPPLIER_NEW_PO_STATE {Date:datetime()}]->(po),
               (po)-[:HAS_SUPPLIER_NEW_RFQ]->(:PoNewRFQ),
               (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(:PoRejectedRFQ)
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
        WITH su, r, po ORDER BY rand() LIMIT 1
        MATCH (po)-[pq:HAS_PO_ITEM]-(p), (po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr), (su)-[:HAS_SUPPLIER_OPEN_POS]->(sop)
        WITH su, r, po, snr, sop, COLLECT({
            Product: p,
            qty: pq.POqt,
            cost: p.UnitPrice * 0.7
        }) AS rfqItems
        CREATE (rfq:RFQ {
            RFQNumber: "RFQ-" + left(randomUUID(), 3) + right(randomUUID(), 3),
            RFQDate: localdatetime(),
            RFQComments: "Thanks for your order, we are able to supply the full PO product request at the discounted price negotiated on our master agreement (stress test)."
        })-[:IS_RFQ_FOR_PO]->(po),
        (rfq)-[:RFQ_FROM_SUPPLIER]->(su),
        (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq),
        (sop)-[:IS_SUPPLIER_OPEN_PO_STATE {Date:datetime()}]->(po)
        DELETE r
        WITH rfq, rfqItems, po
        UNWIND rfqItems AS item
        MATCH (p:Product {ProductID: item.Product.ProductID})
        MERGE (rfq)-[:HAS_RFQ_ITEM {RFQqt: item.qty, RFQcost: item.cost}]->(p)
        RETURN DISTINCT rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
        """,
    ),
    VettingAction(
        "rfq_reject", 1,
        f"""
        MATCH (:SubmittedPoS)-[]->(po:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po)
        WHERE {BUDGET_FITS_CONDITION}
        RETURN count(DISTINCT rfq) AS EligibleCount
        """,
        f"""
        MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {{Title:"Buyer"}})
        WITH bu ORDER BY rand() LIMIT 1
        MATCH (:SubmittedPoS)-[]->(po:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po), (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(prr)
        WHERE {BUDGET_FITS_CONDITION}
        WITH bu, po, pnr, r, rfq, prr ORDER BY rand() LIMIT 1
        CREATE (rfq)-[:HAS_BUYER_RFQ_REJECTION {{Date:datetime(), Comment:"Rejected by Buyer (stress test)."}}]->(bu),
                (prr)-[:IS_SUPPLIER_REJECTED_RFQ_STATE {{Date:datetime()}}]->(rfq)
        DELETE r
        RETURN rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
        """,
    ),
    VettingAction(
        "rfq_approve", 5,
        f"""
        MATCH (:SubmittedPoS)-[]->(po:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po)
        WHERE {BUDGET_FITS_CONDITION}
        RETURN count(DISTINCT rfq) AS EligibleCount
        """,
        f"""
        MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {{Title:"Buyer"}})
        WITH bu ORDER BY rand() LIMIT 1
        MATCH (:SubmittedPoS)-[]->(po:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po)
        WHERE {BUDGET_FITS_CONDITION}
        WITH bu, po, rfq, r, COLLECT({{rfi: rfi, p: p}}) AS items
        WITH bu, po, rfq, r, items ORDER BY rand() LIMIT 1
        UNWIND items AS item
        WITH bu, po, rfq, r, item.rfi AS rfi, item.p AS p
        MATCH (inv)<-[:HAS_INVENTORY_LEVEL]-(p)-[:HAS_SUPPLY_ORDER]-(suo)
        MERGE (rfq)-[:HAS_BUYER_RFQ_APPROVAL {{Date:datetime(), Comment:"Approved by Buyer (stress test)."}}]->(bu)
        MERGE (po)-[:HAS_APPROVED_RFQ {{Date:datetime()}}]->(rfq)
        SET   suo.UnitsOnOrder = suo.UnitsOnOrder + rfi.RFQqt
        DELETE r
        RETURN DISTINCT rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
        """,
    ),
    VettingAction(
        "rfq_resubmit", 4,
        """
        MATCH (rrfq:RFQ)<-[:IS_SUPPLIER_REJECTED_RFQ_STATE]-()
        WHERE NOT ()-[:HAS_PREVIOUS_RFQ]->(rrfq)
        RETURN count(rrfq) AS EligibleCount
        """,
        """
        MATCH (su:Supplier)<-[:RFQ_FROM_SUPPLIER]-(rrfq:RFQ)<-[:IS_SUPPLIER_REJECTED_RFQ_STATE]-(), (rrfq)-[:IS_RFQ_FOR_PO]-(po:PurchaseOrder)
        WHERE NOT ()-[:HAS_PREVIOUS_RFQ]->(rrfq)
        WITH su, rrfq, po ORDER BY rand() LIMIT 1
        MATCH (p)<-[pq:HAS_PO_ITEM]-(po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr), (su)-[:HAS_SUPPLIER_OPEN_POS]->(sop)
        WITH rrfq, su, po, snr, sop, COLLECT({
            Product: p,
            qty: pq.POqt,
            cost: p.UnitPrice * 0.65
        }) AS rfqItems
        CREATE (rfq:RFQ {
            RFQNumber: "RFQ-" + left(randomUUID(), 3) + right(randomUUID(), 3),
            RFQDate: localdatetime(),
            RFQComments: "Thanks for your order, we are resubmitting our RFQ with updated pricing (stress test)."
        })-[:IS_RFQ_FOR_PO]->(po),
        (rfq)-[:RFQ_FROM_SUPPLIER]->(su),
        (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq),
        (sop)-[:IS_SUPPLIER_OPEN_PO_STATE {Date:datetime()}]->(po),
        (rfq)-[:HAS_PREVIOUS_RFQ {Justification: "Auto-resubmitted after rejection (stress test)."}]->(rrfq)
        WITH rfq, rfqItems, po
        UNWIND rfqItems AS item
        MATCH (p:Product {ProductID: item.Product.ProductID})
        MERGE (rfq)-[:HAS_RFQ_ITEM {RFQqt: item.qty, RFQcost: item.cost}]->(p)
        RETURN DISTINCT rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
        """,
    ),
]


def iterate_rfq_vetting(driver: Driver, stats: RunStats, database: str) -> None:
    iterate_weighted_actions(driver, stats, database, RFQ_VETTING_ACTIONS,
                              "No eligible RFQ Vetting action this cycle (no ApprovedPoS/SupplierNewPoS/RFQ items awaiting action)")


# ---------------------------------------------------------------------------
# Loop: warehouse-finance
# ---------------------------------------------------------------------------
#
# Two independent forward-progress actions, not a reject/approve tradeoff,
# so both get equal weight -- whichever has eligible work happens.
# warehouse_delivery is guarded against double-processing (NOT already
# HAS_WAREHOUSE_DELIVERY), matching the fix applied to the main script after
# we found it could otherwise re-add inventory and re-decrement UnitsOnOrder
# every time it ran. finance_closure is naturally self-limiting the same way
# PO Payment/Closure always was: it requires r1/r2 (the SubmittedPoS and
# IS_SUPPLIER_OPEN_PO_STATE edges), which it DELETEs, so a closed PO can
# never be matched again.

WAREHOUSE_FINANCE_ACTIONS: list[VettingAction] = [
    VettingAction(
        "warehouse_delivery", 5,
        """
        MATCH (p)<-[poi:HAS_PO_ITEM]-(po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(:RFQ)-[rfi:HAS_RFQ_ITEM]->(p)
        WHERE poi.POqt = rfi.RFQqt AND NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
        RETURN count(DISTINCT po) AS EligibleCount
        """,
        """
        MATCH (wc:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title:"WarehouseClerk"})
        WITH wc ORDER BY rand() LIMIT 1
        MATCH (p)<-[poi:HAS_PO_ITEM]-(po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(:RFQ)-[rfi:HAS_RFQ_ITEM]->(p)
        WHERE poi.POqt = rfi.RFQqt AND NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
        WITH wc, po, COLLECT({p: p, rfi: rfi}) AS items
        WITH wc, po, items ORDER BY rand() LIMIT 1
        MERGE (po)-[:HAS_WAREHOUSE_DELIVERY {Date:datetime(), Comment:"The products have been received as per PO at the Warehouse and the Inventory Levels have been updated accordingly (stress test)."}]->(wc)
        WITH po, items
        UNWIND items AS item
        WITH po, item.p AS p, item.rfi AS rfi
        MATCH (p)-[:HAS_INVENTORY_LEVEL]->(inv), (p)-[:HAS_SUPPLY_ORDER]->(suo)
        SET inv.UnitsInStock = inv.UnitsInStock + rfi.RFQqt,
            inv.LastUpdate = datetime(),
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
        MATCH (f:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title:"Finance"})
        WITH f ORDER BY rand() LIMIT 1
        MATCH (cpo)<-[:HAS_CLOSED_PO_STATE]-(:PoS)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS)-[r1]->(po:PurchaseOrder)-[:HAS_WAREHOUSE_DELIVERY]->(:Employee),
              (po)<-[r2:IS_SUPPLIER_OPEN_PO_STATE]-()<-[]-(:Supplier)-[:HAS_SUPPLIER_CLOSED_POS]->(scp)
        WITH f, cpo, scp, r1, r2, po ORDER BY rand() LIMIT 1
        MERGE (po)-[:HAS_FINANCE_PAYMENT {Date:datetime(), Comment:"The PO has been paid by Finance and the PO is now closed (stress test)."}]->(f)
        MERGE (cpo)-[:IS_CLOSED_PO_STATE {Date:datetime(), Comment:"The PO has been paid by Finance and the PO is now closed (stress test)."}]->(po)
        MERGE (scp)-[:HAS_SUPPLIER_CLOSED_PO_STATE {Date:datetime(), Comment:"The PO has been paid by Finance and the PO is now closed (stress test)."}]->(po)
        DELETE r1, r2
        RETURN po.PONumber AS PONumber
        """,
    ),
]


def iterate_warehouse_finance(driver: Driver, stats: RunStats, database: str) -> None:
    iterate_weighted_actions(driver, stats, database, WAREHOUSE_FINANCE_ACTIONS,
                              "No eligible Warehouse/Finance action this cycle (nothing awaiting delivery or closure)")


# ---------------------------------------------------------------------------
# Loop: po-creation
# ---------------------------------------------------------------------------
#
# Single well-defined action, not a branching decision -- no eligibility/
# weighting machinery needed, same shape as customer-order.
#
# NOTE: this creates one PO PER QUALIFYING SUPPLIER, not one PO total (per
# the original script's own "Create ONE Purchase Order per Supplier"
# comment) -- a single execution can create several POs at once if multiple
# Suppliers have low-stock Products simultaneously. RETURN DISTINCT is
# needed for the same reason customer-order needed it: without it, the
# UNWIND over each PO's items would return one row per item, not per PO.
#
# FIXED (previously a known limitation): PO Creation now subtracts quantity
# already committed via any active (not yet closed) PO for the same Product
# before deciding whether it's still genuinely low-stock, and before sizing
# the new order. Without this, the same low-stock condition kept re-firing
# every cycle -- confirmed via a real test run where po-creation created the
# same ~28 POs four cycles in a row, 30 seconds apart, since UnitsInStock
# never changes on its own (that only happens once warehouse-finance
# actually delivers). Confirmed fixed via a real test run too: the first
# execution created 25 POs, the second (immediately after) created zero,
# since everything was now covered by the first round's pending POs.
#
# NOTE: this creates one PO PER QUALIFYING SUPPLIER, not one PO total (per
# the original script's own "Create ONE Purchase Order per Supplier"
# comment) -- a single execution can create several POs at once if multiple
# Suppliers have low-stock Products simultaneously. RETURN DISTINCT is
# needed for the same reason customer-order needed it: without it, the
# UNWIND over each PO's items would return one row per item, not per PO.

PO_CREATION_QUERY = """
MATCH (pa:RolE {Title: "Procurement Assistant"})-[:IS_ACTIVE_ROLE]->(e:Employee), (n:NewPoS {Name:"NewPoS"})
WITH n, e ORDER BY rand() LIMIT 1
MATCH (s:Supplier)-[:SUPPLIES]->(p:Product)
  <-[:IS_AVAILABLE_PRODUCT]-(a:ProductStatusAvailablE),
  (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
OPTIONAL MATCH (activePO:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p)
WHERE (activePO)<-[:IS_NEW_PO_STATE]-(:NewPoS)
   OR (activePO)<-[:IS_APPROVED_PO_STATE]-(:ApprovedPoS)
   OR (activePO)<-[:IS_SUBMITTED_PO_STATE]-(:SubmittedPoS)
WITH e, n, s, p, r, i, SUM(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty
WHERE i.UnitsInStock + AlreadyPendingQty - (r.StockThreshold * 0.5) <= r.StockThreshold
WITH e, n, s, COLLECT({
    Product: p,
    qty: (r.StockThreshold) - (i.UnitsInStock + AlreadyPendingQty) + (r.StockThreshold * 2)
}) AS orderItems
CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {
    PONumber: "PO-" + left(randomUUID(), 3) + right(randomUUID(), 3),
    PODate: localdatetime()
})
CREATE (s)<-[:PO_FOR_SUPPLIER]-(po)
CREATE (po)-[:PO_CREATED_BY]->(e)
WITH po, orderItems, s
UNWIND orderItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7}]->(p)
RETURN DISTINCT po.PONumber AS PONumber, s.SupplierID AS SupplierID, size(orderItems) AS ItemCount
"""


def run_po_creation(tx):
    result = tx.run(PO_CREATION_QUERY)
    return [(r["PONumber"], r["SupplierID"], r["ItemCount"]) for r in result]


def iterate_po_creation(driver: Driver, stats: RunStats, database: str) -> None:
    pos = execute_with_retry(driver, run_po_creation, stats, database)
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
# Single well-defined action, same shape as po-creation -- no eligibility/
# weighting machinery needed. Self-limiting by construction, same as
# finance_closure: requires and then DELETEs the Order's IS_OPEN_ORDER_STATE
# relationship, so a fulfilled Order can never be re-selected on a later run.
#
# NOTE: unlike every other loop's ORDER BY rand() candidate selection, this
# one deliberately keeps ORDER BY o.OrderDate (oldest-first) from the main
# script -- serving the longest-waiting Customer first is a real business
# rule here, not an arbitrary demo pick, so it wasn't randomized away.
#
# Only fulfills an Order if EVERY line has sufficient stock (won't partially
# ship or push Inventory negative) -- an Order missing stock for any Product
# is skipped and stays Open, same as the main script's own design.

ORDER_FULFILLMENT_QUERY = """
MATCH (wc:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title:"WarehouseClerk"}), (s:Shipper)
WITH wc, s ORDER BY rand() LIMIT 1
MATCH (op:OrderStatusOpeN {Status:"Open"})-[r:IS_OPEN_ORDER_STATE]->(o:Order)-[details:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
WITH wc, s, op, r, o, count(details) AS TotalLines, sum(CASE WHEN inv.UnitsInStock >= details.Quantity THEN 1 ELSE 0 END) AS LinesWithStock
WHERE TotalLines = LinesWithStock
WITH wc, s, op, r, o ORDER BY o.OrderDate LIMIT 1
MATCH (a)<-[:HAS_CUSTOMER_ADDRESS]-(:Customer)<-[:HAS_ORDER_CUSTOMER]-(o), (f:OrderStatusFulfilleD {Status:"Fulfilled"})
CREATE (i:ShipInfo {ShippmentID:randomUUID(), ShippedDate:date()})
CREATE (o)-[:HAS_SHIPMENT_INFO]->(i)
CREATE (i)-[:HAS_SHIPPER]->(s)
CREATE (i)-[:HAS_SHIPMENT_ADDRESS]->(a)
CREATE (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: datetime()}]->(o)
CREATE (o)-[:HAS_WAREHOUSE_FULFILLMENT {Date:datetime(), Comment:"Order picked, packed, and shipped by the Warehouse Clerk (stress test)."}]->(wc)
DELETE r
WITH o
MATCH (o)-[details:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
SET inv.UnitsInStock = inv.UnitsInStock - details.Quantity,
    inv.LastUpdate = datetime()
RETURN DISTINCT o.OrderID AS OrderID
"""


def run_order_fulfillment(tx):
    result = tx.run(ORDER_FULFILLMENT_QUERY)
    record = result.single()
    return record["OrderID"] if record else None


def iterate_order_fulfillment(driver: Driver, stats: RunStats, database: str) -> None:
    order_id = execute_with_retry(driver, run_order_fulfillment, stats, database)
    if order_id:
        log.info(f"Fulfilled Order {order_id}")
    else:
        stats.no_op += 1
        log.info("No Order Fulfillment this cycle (no Open Order currently has full stock coverage for every line)")


# ---------------------------------------------------------------------------
# Loop dispatch table -- all six loops now implemented.
# ---------------------------------------------------------------------------

LOOPS: dict[str, Callable[[Driver, RunStats, str], None]] = {
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


def run_loop(driver: Driver, loop_name: str, rate_per_minute: float, duration_seconds: float | None, database: str) -> None:
    fn = LOOPS[loop_name]
    interval = 60.0 / rate_per_minute
    stats = RunStats()

    signal.signal(signal.SIGINT, _handle_sigint)
    log.info(f"Starting loop '{loop_name}' at {rate_per_minute}/min (every {interval:.2f}s) against database '{database}'. Ctrl+C to stop.")

    while not _shutdown_requested:
        iteration_start = time.perf_counter()
        fn(driver, stats, database)
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


def main() -> None:
    parser = argparse.ArgumentParser(description="NorthWind PLUS concurrency stress harness.")
    parser.add_argument("--loop", required=True, choices=sorted(LOOPS.keys()),
                         help="Which workflow step to run repeatedly.")
    parser.add_argument("--rate", type=float, default=6.0, help="Executions per minute (default: 6).")
    parser.add_argument("--duration", type=float, default=None, help="Stop after this many seconds (default: run until Ctrl+C).")
    args = parser.parse_args()

    if args.loop not in LOOPS:
        log.error(f"Loop '{args.loop}' is defined on the CLI but not implemented yet -- only {list(LOOPS.keys())} are wired up so far.")
        sys.exit(1)

    uri = os.environ.get("NEO4J_URI", "neo4j://localhost:7687")
    user = os.environ.get("NEO4J_USER", "neo4j")
    password = os.environ.get("NEO4J_PASSWORD")
    database = os.environ.get("NEO4J_DATABASE", "neo4j")
    if not password:
        raise SystemExit("Set the NEO4J_PASSWORD environment variable before running.")

    # NOTE: passing database= here is a confirmed no-op -- GraphDatabase.driver()
    # accepts it silently via a generic **config catch-all but never uses it.
    # Verified by inspecting the installed driver directly: the resulting Driver
    # object retains no trace of it. Left here only so you can compare against
    # the session-level version below if you want to debug what went wrong
    # with that approach -- database routing needs to happen per-session.
    driver = GraphDatabase.driver(
        uri, auth=(user, password),
        notifications_disabled_classifications=[NotificationDisabledClassification.PERFORMANCE],
    )
    try:
        driver.verify_connectivity()
        run_loop(driver, args.loop, args.rate, args.duration, database)
    finally:
        driver.close()


if __name__ == "__main__":
    main()