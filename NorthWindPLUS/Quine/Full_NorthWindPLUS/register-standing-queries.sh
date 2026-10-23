#!/usr/bin/env bash
# =============================================================================
# NorthWind PLUS v2.4 on Quine -- the company's own rules as standing queries
#
# The Python loops play the outside world (customers order, suppliers quote
# and deliver, the warehouse ships, a slow job recalibrates thresholds).
# These standing queries are the business reacting to it, inside the graph,
# the moment a pattern appears -- no polling:
#
#   nw-reorder-low-stock        product in LowStocK, supplier approved  -> one PO per supplier for its low products
#   nw-po-vetting-l1            PO in NewPoS                            -> L1: reject by rule / approve within limit / pass to L2
#   nw-po-vetting-l2            PO in NewPoS with an L1 approval         -> L2: reject by rule / approve within limit / pass to L3
#   nw-po-vetting-l3            PO in NewPoS with an L2 approval         -> L3: reject by rule or over limit / approve
#   nw-low-stock-after-reject   PO in RejectedPoS                       -> re-evaluate LowStock for its products
#   nw-buyer-submission         PO in ApprovedPoS                       -> Buyer submits it to the supplier
#   nw-rfq-vetting              RFQ in a submitted PO's PoNewRFQ          -> approve if within the PO budget, else reject
#   nw-rfq-approved-on-order    PO gets an approved RFQ                 -> UnitsOnOrder += RFQ quantities (atomic)
#   nw-finance-closure          submitted PO gets a WarehouseDelivery    -> Finance pays and closes it
#
# Rejections are rule-based, never random. The rules live in the data:
#   PO  (every level): the supplier is not in ApprovedSupplierS, or a product is no longer Available
#   PO  (L3):          the cost exceeds Level3Approver.ApprovalLimit (no one can approve it)
#   RFQ:               any line costs more than the PO budgeted for it (qty x UnitPrice x POPriceDiscount),
#                      or the PO already has an approved RFQ
#
# Usage (after northwind-plus-quine-batch.sh has loaded the graph):
#     ./register-standing-queries.sh            (re)register all, then backfill them over existing data
#     ./register-standing-queries.sh --status   list the NorthWind standing queries
#     ./register-standing-queries.sh --remove   delete them all (back to the loops-only setup)
#     --quine URL                                Quine base URL (default http://localhost:8080)
#
# Watch the twin act (Docker; use your container's name from `docker ps`):
#     docker logs -f <container> 2>&1 | grep -o '"alert":"[^"]*"'
#
# Every output follows the rules found while testing on Quine 2.1.1:
#   * an OnlyPositiveMatch filter, plus a guard on $that.meta.isPositiveMatch;
#   * anchored queries only (allowAllNodeScan stays false);
#   * no pattern predicate on a WITH that follows ORDER BY/LIMIT or an
#     aggregation (Quine evaluates those as false) -- conditions after an
#     aggregation use OPTIONAL MATCH, and re-checks use MATCH (x) WHERE ...;
#   * a writer moves a node into a Collection LAST, after its parts exist, and
#     takes it OUT of its old Collection FIRST, before recording the decision:
#     otherwise, for an instant, the node matches the next level's pattern
#     (e.g. "in NewPoS with an L1 approval") and that standing query fires too;
#   * shouldRetry = false: an output is never re-run, so its writes cannot be
#     duplicated (Quine cannot prove these queries idempotent);
#   * counters are stamped: rfq.OnOrderPosted marks an RFQ already put on
#     order, so the backfill never counts an RFQ the batch had counted.
# =============================================================================

set -uo pipefail

QUINE="http://localhost:8080"
ACTION="register"
while [ $# -gt 0 ]; do
  case "$1" in
    --status) ACTION="status"; shift ;;
    --remove) ACTION="remove"; shift ;;
    --quine)  QUINE="$2"; shift 2 ;;
    -h|--help) sed -n '2,49p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
API="${QUINE}/api/v2/graph/quine/standingQueries"
command -v curl >/dev/null && command -v python3 >/dev/null || { echo "ERROR: curl and python3 are required" >&2; exit 1; }
curl -sf -m 10 "${QUINE}/api/v1/admin/build-info" >/dev/null || { echo "ERROR: Quine is not answering at $QUINE" >&2; exit 1; }

nw_names() {
  curl -s -m 20 "$API" | python3 -c 'import json,sys
d = json.load(sys.stdin); items = d.get("items", d) if isinstance(d, dict) else d
for sq in items:
    n = sq.get("name", "")
    if n.startswith("nw-"): print(n)'
}

if [ "$ACTION" = "status" ]; then
  echo "NorthWind standing queries registered in $QUINE:"; nw_names | sed 's/^/  /'; exit 0
fi

if [ "$ACTION" = "remove" ]; then
  for n in $(nw_names); do
    printf '  delete %-30s HTTP %s\n' "$n" "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$API/$n")"
  done
  exit 0
fi

# preflight: the graph must be loaded and have the LowStocK Collection
LOADED=$(python3 -c 'import json; print(json.dumps({"text": "MATCH (n), (ls) WHERE id(n) = idFrom(\"NewPoS\") AND id(ls) = idFrom(\"LowStocK\") RETURN n.Name AS n, ls.Name AS ls", "parameters": {}}))' |
         curl -s -X POST "${QUINE}/api/v2/graph/quine/cypher:query" -H 'Content-Type: application/json' --data-binary @-)
case "$LOADED" in
  *'"NewPoS","LowStock"'*) ;;
  *) echo "ERROR: the NorthWind PLUS graph (with LowStocK) is not loaded -- run northwind-plus-quine-batch.sh first." >&2; exit 1 ;;
esac

FAILED=0
# sq NAME PARALLELISM "PATTERN"  <<'CYPHER' (enrichment query) CYPHER
sq() {
  local name="$1" par="$2" pattern="$3" enrichment body code out
  enrichment="$(cat)"
  body="$(python3 -c 'import json,sys
name, par, pattern, enrichment = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
print(json.dumps({
  "name": name,
  "pattern": {"type": "Cypher", "mode": "DISTINCT_ID", "query": pattern},
  "outputs": [{
    "name": "act",
    "filter": {"type": "OnlyPositiveMatch"},
    "resultEnrichment": {"query": enrichment, "parallelism": par, "shouldRetry": False},
    "destinations": [{"type": "StandardOut"}]
  }],
  "includeCancellations": False
}))' "$name" "$par" "$pattern" "$enrichment")"
  curl -s -o /dev/null -X DELETE "$API/$name"
  out="$(printf '%s' "$body" | curl -s -w '\n%{http_code}' -X POST "$API?propagateTo=NONE" -H 'Content-Type: application/json' --data-binary @-)"
  code="${out##*$'\n'}"
  if [ "$code" = "201" ] || [ "$code" = "200" ]; then
    printf '  %-28s registered\n' "$name"
  else
    printf '  %-28s FAILED (HTTP %s): %s\n' "$name" "$code" "$(printf '%s' "${out%$'\n'*}" | cut -c1-400)"
    FAILED=$((FAILED + 1))
  fi
}

echo "Registering the NorthWind PLUS standing queries in $QUINE"

# -----------------------------------------------------------------------------
# 1. Reorder: a product in LowStocK whose supplier is approved -> one PO for that
#    supplier covering all its products still at their reorder point.
#    parallelism 1: POs are created one at a time, so two products of the same
#    supplier entering LowStock together produce ONE PO, not two.
#    The triggering product is re-checked first; if it is no longer low (a stale
#    membership), it is simply taken out of LowStock.
#    Lineage: if the supplier has a rejected, not yet resubmitted PO for one of
#    these products, the new PO points back to it (HAS_PREVIOUS_PO).
#    Products whose previous PO was rejected for exceeding every approval limit
#    are not re-ordered automatically (that would loop forever).
# -----------------------------------------------------------------------------
sq nw-reorder-low-stock 1 \
  'MATCH (ls:LowStocK)-[:IS_LOW_STOCK_PRODUCT]->(p:Product)<-[:SUPPLIES]-(s:Supplier)<-[:IS_SUPPLIER_APPROVED_STATE]-(app:ApprovedSupplierS) RETURN DISTINCT id(p) AS id' <<'CYPHER'
MATCH (p0) WHERE id(p0) = quineId($that.data.id) AND $that.meta.isPositiveMatch = true
MATCH (ls), (n), (pa), (app), (av)
WHERE id(ls) = idFrom("LowStocK") AND id(n) = idFrom("NewPoS") AND id(pa) = idFrom("RolE", "Procurement Assistant")
  AND id(app) = idFrom("ApprovedSupplierS") AND id(av) = idFrom("ProductStatusAvailablE")
MATCH (ls)-[e0:IS_LOW_STOCK_PRODUCT]->(p0)-[:HAS_REORDER_LEVEL]->(r0:ReorderLevel), (p0)-[:HAS_INVENTORY_LEVEL]->(i0:InventoryLevel)
OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(a0:PurchaseOrder)-[:HAS_PO_ITEM]->(q0:POItem)-[:PO_ITEM_PRODUCT]->(p0)
WHERE NOT (a0)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH p0, ls, n, pa, app, av, e0, r0, i0, sum(coalesce(q0.POqt, 0)) AS pending0
OPTIONAL MATCH (p0)<-[:ORDER_ITEM_PRODUCT]-(o0:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
WITH p0, ls, n, pa, app, av, e0, i0.UnitsInStock + pending0 - sum(coalesce(o0.Quantity, 0)) - (r0.StockThreshold * 0.5) <= r0.StockThreshold AS low0
FOREACH (_ IN CASE WHEN low0 THEN [] ELSE [1] END | DELETE e0)
WITH p0, ls, n, pa, app, av, low0 WHERE low0
MATCH (p0)<-[:SUPPLIES]-(s:Supplier)<-[:IS_SUPPLIER_APPROVED_STATE]-(app)
MATCH (pa)-[:IS_ACTIVE_ROLE]->(emp:Employee)
WITH ls, n, av, s, emp ORDER BY rand() LIMIT 1
MATCH (ls)-[:IS_LOW_STOCK_PRODUCT]->(p:Product)<-[:SUPPLIES]-(s), (av)-[:IS_AVAILABLE_PRODUCT]->(p),
      (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[:HAS_PO_ITEM]->(poi2:POItem)-[:PO_ITEM_PRODUCT]->(p)
WHERE NOT (activePO)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH ls, n, s, emp, p, r, i, sum(coalesce(poi2.POqt, 0)) AS pending
OPTIONAL MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(op:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
WITH ls, n, s, emp, p, r, i, pending, sum(coalesce(op.Quantity, 0)) AS openQty
WHERE i.UnitsInStock + pending - openQty - (r.StockThreshold * 0.5) <= r.StockThreshold
OPTIONAL MATCH (rej)-[:IS_REJECTED_PO_STATE]->(prev:PurchaseOrder)-[:HAS_PO_ITEM]->(:POItem)-[:PO_ITEM_PRODUCT]->(p)
WHERE id(rej) = idFrom("RejectedPoS") AND (prev)-[:PO_FOR_SUPPLIER]->(s) AND NOT ()-[:HAS_PREVIOUS_PO]->(prev)
OPTIONAL MATCH (prev)-[l3:HAS_L3_PO_REJECTION]->()
WITH ls, n, s, emp, p, r, i, pending, openQty, collect(DISTINCT prev) AS prevs, count(l3) AS overLimit
WHERE overLimit = 0
WITH ls, n, s, emp,
     collect({p: p, qty: r.StockThreshold - (i.UnitsInStock + pending - openQty) + (r.StockThreshold * 2)}) AS items,
     reduce(acc = [], x IN collect(prevs) | acc + x) AS prevPOs
CREATE (po:PurchaseOrder {PODate: datetime()})
SET po.PONumber = "PO-" + left(strId(po), 5) + right(strId(po), 5)
CREATE (po)-[:PO_FOR_SUPPLIER]->(s), (po)-[:PO_CREATED_BY]->(emp)
FOREACH (prev IN prevPOs | CREATE (po)-[:HAS_PREVIOUS_PO]->(prev))
FOREACH (_ IN CASE WHEN size(prevPOs) > 0 THEN [1] ELSE [] END |
  CREATE (po)-[:HAS_RESUBMISSION_NOTE]->(:ResubmissionNote {Justification: "Re-ordered automatically after the previous PO was rejected and the rule that rejected it no longer applies.", Date: datetime()}))
WITH ls, n, s, po, prevPOs, items
UNWIND items AS item
WITH ls, n, s, po, prevPOs, item.p AS p, item.qty AS qty
CREATE (po)-[:HAS_PO_ITEM]->(:POItem {POqt: qty, POPriceDiscount: 0.7})-[:PO_ITEM_PRODUCT]->(p)
WITH ls, n, s, po, prevPOs, p, qty
MATCH (ls)-[low:IS_LOW_STOCK_PRODUCT]->(p)
DELETE low
WITH n, s, po, prevPOs, collect(p.ProductName + " x" + toString(qty)) AS lines
CREATE (n)-[:IS_NEW_PO_STATE]->(po)
RETURN "[PO CREATED] " + po.PONumber + " to " + s.CompanyName + ": " + reduce(t = "", l IN lines | t + l + "  ")
       + CASE WHEN size(prevPOs) > 0 THEN "(re-order of " + reduce(t = "", x IN prevPOs | t + x.PONumber + " ") + ")" ELSE "" END AS alert
CYPHER

# -----------------------------------------------------------------------------
# 2. PO vetting. Each level fires on the shape that hands the PO to it; the
#    rules come from the graph (supplier state, product state, RolE limits).
# -----------------------------------------------------------------------------
sq nw-po-vetting-l1 4 \
  'MATCH (n:NewPoS)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder) RETURN DISTINCT id(po) AS id' <<'CYPHER'
MATCH (po) WHERE id(po) = quineId($that.data.id) AND $that.meta.isPositiveMatch = true
MATCH (np0)-[np:IS_NEW_PO_STATE]->(po) WHERE id(np0) = idFrom("NewPoS")
MATCH (po) WHERE NOT (po)-[:HAS_L1_PO_APPROVAL|HAS_L1_PO_REJECTION]->()
MATCH (po)-[:PO_FOR_SUPPLIER]->(s:Supplier), (po)-[:HAS_PO_ITEM]->(it:POItem)-[:PO_ITEM_PRODUCT]->(pr:Product)
OPTIONAL MATCH (av)-[avail:IS_AVAILABLE_PRODUCT]->(pr) WHERE id(av) = idFrom("ProductStatusAvailablE")
WITH po, np, s, sum(it.POqt * (pr.UnitPrice * it.POPriceDiscount)) AS POCost,
     collect(CASE WHEN avail IS NULL THEN pr.ProductName END) AS unavailable
OPTIONAL MATCH (app)-[sa:IS_SUPPLIER_APPROVED_STATE]->(s) WHERE id(app) = idFrom("ApprovedSupplierS")
MATCH (ro), (appr), (rej) WHERE id(ro) = idFrom("RolE", "Level1Approver") AND id(appr) = idFrom("ApprovedPoS") AND id(rej) = idFrom("RejectedPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l:Employee)
WITH po, np, s, POCost, unavailable, sa, ro, appr, rej, l ORDER BY rand() LIMIT 1
WITH po, np, POCost, ro, appr, rej, l,
     CASE WHEN sa IS NULL THEN "supplier " + s.CompanyName + " is not approved"
          WHEN size(unavailable) > 0 THEN "no longer available: " + reduce(t = "", x IN unavailable | t + x + " ")
          ELSE null END AS reason
WITH po, np, POCost, ro, appr, rej, l, reason,
     CASE WHEN reason IS NOT NULL THEN "reject" WHEN POCost < ro.ApprovalLimit THEN "approve" ELSE "pass" END AS decision
FOREACH (_ IN CASE WHEN decision = "reject" THEN [1] ELSE [] END |
  DELETE np
  CREATE (po)-[:HAS_L1_PO_REJECTION]->(:VettingDecision {Date: datetime(), Comment: "Rejected by L1: " + reason})-[:VETTED_BY]->(l),
         (rej)-[:IS_REJECTED_PO_STATE]->(po))
FOREACH (_ IN CASE WHEN decision = "approve" THEN [1] ELSE [] END |
  DELETE np
  CREATE (po)-[:HAS_L1_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "Approved by L1: within the L1 approval limit"})-[:VETTED_BY]->(l),
         (appr)-[:IS_APPROVED_PO_STATE]->(po))
FOREACH (_ IN CASE WHEN decision = "pass" THEN [1] ELSE [] END |
  CREATE (po)-[:HAS_L1_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "Vetted by L1, passed to L2: above the L1 approval limit"})-[:VETTED_BY]->(l))
RETURN "[L1 " + CASE decision WHEN "reject" THEN "REJECTED] " WHEN "approve" THEN "APPROVED] " ELSE "-> L2] " END
       + po.PONumber + " $" + toString(round(POCost, 2)) + CASE WHEN reason IS NULL THEN "" ELSE " (" + reason + ")" END AS alert
CYPHER

sq nw-po-vetting-l2 4 \
  'MATCH (n:NewPoS)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder)-[:HAS_L1_PO_APPROVAL]->(d:VettingDecision) RETURN DISTINCT id(po) AS id' <<'CYPHER'
MATCH (po) WHERE id(po) = quineId($that.data.id) AND $that.meta.isPositiveMatch = true
MATCH (np0)-[np:IS_NEW_PO_STATE]->(po) WHERE id(np0) = idFrom("NewPoS")
MATCH (po) WHERE (po)-[:HAS_L1_PO_APPROVAL]->() AND NOT (po)-[:HAS_L2_PO_APPROVAL|HAS_L2_PO_REJECTION]->()
MATCH (po)-[:PO_FOR_SUPPLIER]->(s:Supplier), (po)-[:HAS_PO_ITEM]->(it:POItem)-[:PO_ITEM_PRODUCT]->(pr:Product)
OPTIONAL MATCH (av)-[avail:IS_AVAILABLE_PRODUCT]->(pr) WHERE id(av) = idFrom("ProductStatusAvailablE")
WITH po, np, s, sum(it.POqt * (pr.UnitPrice * it.POPriceDiscount)) AS POCost,
     collect(CASE WHEN avail IS NULL THEN pr.ProductName END) AS unavailable
OPTIONAL MATCH (app)-[sa:IS_SUPPLIER_APPROVED_STATE]->(s) WHERE id(app) = idFrom("ApprovedSupplierS")
MATCH (ro), (appr), (rej) WHERE id(ro) = idFrom("RolE", "Level2Approver") AND id(appr) = idFrom("ApprovedPoS") AND id(rej) = idFrom("RejectedPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l:Employee)
WITH po, np, s, POCost, unavailable, sa, ro, appr, rej, l ORDER BY rand() LIMIT 1
WITH po, np, POCost, ro, appr, rej, l,
     CASE WHEN sa IS NULL THEN "supplier " + s.CompanyName + " is not approved"
          WHEN size(unavailable) > 0 THEN "no longer available: " + reduce(t = "", x IN unavailable | t + x + " ")
          ELSE null END AS reason
WITH po, np, POCost, ro, appr, rej, l, reason,
     CASE WHEN reason IS NOT NULL THEN "reject" WHEN POCost < ro.ApprovalLimit THEN "approve" ELSE "pass" END AS decision
FOREACH (_ IN CASE WHEN decision = "reject" THEN [1] ELSE [] END |
  DELETE np
  CREATE (po)-[:HAS_L2_PO_REJECTION]->(:VettingDecision {Date: datetime(), Comment: "Rejected by L2: " + reason})-[:VETTED_BY]->(l),
         (rej)-[:IS_REJECTED_PO_STATE]->(po))
FOREACH (_ IN CASE WHEN decision = "approve" THEN [1] ELSE [] END |
  DELETE np
  CREATE (po)-[:HAS_L2_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "Approved by L2: within the L2 approval limit"})-[:VETTED_BY]->(l),
         (appr)-[:IS_APPROVED_PO_STATE]->(po))
FOREACH (_ IN CASE WHEN decision = "pass" THEN [1] ELSE [] END |
  CREATE (po)-[:HAS_L2_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "Vetted by L2, passed to L3: above the L2 approval limit"})-[:VETTED_BY]->(l))
RETURN "[L2 " + CASE decision WHEN "reject" THEN "REJECTED] " WHEN "approve" THEN "APPROVED] " ELSE "-> L3] " END
       + po.PONumber + " $" + toString(round(POCost, 2)) + CASE WHEN reason IS NULL THEN "" ELSE " (" + reason + ")" END AS alert
CYPHER

sq nw-po-vetting-l3 4 \
  'MATCH (n:NewPoS)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder)-[:HAS_L2_PO_APPROVAL]->(d:VettingDecision) RETURN DISTINCT id(po) AS id' <<'CYPHER'
MATCH (po) WHERE id(po) = quineId($that.data.id) AND $that.meta.isPositiveMatch = true
MATCH (np0)-[np:IS_NEW_PO_STATE]->(po) WHERE id(np0) = idFrom("NewPoS")
MATCH (po) WHERE (po)-[:HAS_L2_PO_APPROVAL]->() AND NOT (po)-[:HAS_L3_PO_APPROVAL|HAS_L3_PO_REJECTION]->()
MATCH (po)-[:PO_FOR_SUPPLIER]->(s:Supplier), (po)-[:HAS_PO_ITEM]->(it:POItem)-[:PO_ITEM_PRODUCT]->(pr:Product)
OPTIONAL MATCH (av)-[avail:IS_AVAILABLE_PRODUCT]->(pr) WHERE id(av) = idFrom("ProductStatusAvailablE")
WITH po, np, s, sum(it.POqt * (pr.UnitPrice * it.POPriceDiscount)) AS POCost,
     collect(CASE WHEN avail IS NULL THEN pr.ProductName END) AS unavailable
OPTIONAL MATCH (app)-[sa:IS_SUPPLIER_APPROVED_STATE]->(s) WHERE id(app) = idFrom("ApprovedSupplierS")
MATCH (ro), (appr), (rej) WHERE id(ro) = idFrom("RolE", "Level3Approver") AND id(appr) = idFrom("ApprovedPoS") AND id(rej) = idFrom("RejectedPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l:Employee)
WITH po, np, s, POCost, unavailable, sa, ro, appr, rej, l ORDER BY rand() LIMIT 1
WITH po, np, POCost, ro, appr, rej, l,
     CASE WHEN sa IS NULL THEN "supplier " + s.CompanyName + " is not approved"
          WHEN size(unavailable) > 0 THEN "no longer available: " + reduce(t = "", x IN unavailable | t + x + " ")
          WHEN POCost >= ro.ApprovalLimit THEN "exceeds every approval limit"
          ELSE null END AS reason
FOREACH (_ IN CASE WHEN reason IS NOT NULL THEN [1] ELSE [] END |
  DELETE np
  CREATE (po)-[:HAS_L3_PO_REJECTION]->(:VettingDecision {Date: datetime(), Comment: "Rejected by L3: " + reason})-[:VETTED_BY]->(l),
         (rej)-[:IS_REJECTED_PO_STATE]->(po))
FOREACH (_ IN CASE WHEN reason IS NULL THEN [1] ELSE [] END |
  DELETE np
  CREATE (po)-[:HAS_L3_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "Approved by L3: within the L3 approval limit"})-[:VETTED_BY]->(l),
         (appr)-[:IS_APPROVED_PO_STATE]->(po))
RETURN "[L3 " + CASE WHEN reason IS NULL THEN "APPROVED] " ELSE "REJECTED] " END
       + po.PONumber + " $" + toString(round(POCost, 2)) + CASE WHEN reason IS NULL THEN "" ELSE " (" + reason + ")" END AS alert
CYPHER

# -----------------------------------------------------------------------------
# 3. A rejected PO no longer covers its products: re-evaluate them, so they can
#    come back into LowStock (and be re-ordered once the rule allows it).
# -----------------------------------------------------------------------------
sq nw-low-stock-after-reject 4 \
  'MATCH (r:RejectedPoS)-[:IS_REJECTED_PO_STATE]->(po:PurchaseOrder) RETURN DISTINCT id(po) AS id' <<'CYPHER'
MATCH (po) WHERE id(po) = quineId($that.data.id) AND $that.meta.isPositiveMatch = true
MATCH (av), (ls) WHERE id(av) = idFrom("ProductStatusAvailablE") AND id(ls) = idFrom("LowStocK")
MATCH (po)-[:HAS_PO_ITEM]->(:POItem)-[:PO_ITEM_PRODUCT]->(p:Product)<-[:IS_AVAILABLE_PRODUCT]-(av)
MATCH (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[:HAS_PO_ITEM]->(poi:POItem)-[:PO_ITEM_PRODUCT]->(p)
WHERE NOT (activePO)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH po, ls, p, r, i, sum(coalesce(poi.POqt, 0)) AS pending
OPTIONAL MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(oi:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
WITH po, ls, p, r, i, pending, sum(coalesce(oi.Quantity, 0)) AS openQty
WITH po, ls, p, i.UnitsInStock + pending - openQty - (r.StockThreshold * 0.5) <= r.StockThreshold AS low
OPTIONAL MATCH (ls)-[e:IS_LOW_STOCK_PRODUCT]->(p)
FOREACH (_ IN CASE WHEN low AND e IS NULL THEN [1] ELSE [] END | CREATE (ls)-[:IS_LOW_STOCK_PRODUCT]->(p))
FOREACH (_ IN CASE WHEN NOT low AND e IS NOT NULL THEN [1] ELSE [] END | DELETE e)
WITH po, collect(CASE WHEN low THEN p.ProductName END) AS backInLowStock
RETURN "[LOWSTOCK RECHECK] after rejection of " + po.PONumber + ": "
       + CASE WHEN size(backInLowStock) = 0 THEN "no product back in LowStock" ELSE "back in LowStock: " + reduce(t = "", x IN backInLowStock | t + x + " ") END AS alert
CYPHER

# -----------------------------------------------------------------------------
# 4. Buyer submission: an approved PO goes to its supplier. The supplier's
#    SupplierNewPoS edge is written last -- that is what the supplier side
#    (the rfq-submission loop) reacts to.
# -----------------------------------------------------------------------------
sq nw-buyer-submission 4 \
  'MATCH (a:ApprovedPoS)-[:IS_APPROVED_PO_STATE]->(po:PurchaseOrder) RETURN DISTINCT id(po) AS id' <<'CYPHER'
MATCH (po) WHERE id(po) = quineId($that.data.id) AND $that.meta.isPositiveMatch = true
MATCH (a)-[ap:IS_APPROVED_PO_STATE]->(po) WHERE id(a) = idFrom("ApprovedPoS")
MATCH (po) WHERE NOT (po)-[:HAS_BUYER_PO_APPROVAL]->()
MATCH (po)-[:PO_FOR_SUPPLIER]->(s:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp)
MATCH (ro), (su) WHERE id(ro) = idFrom("RolE", "Buyer") AND id(su) = idFrom("SubmittedPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(bu:Employee)
WITH po, ap, s, snp, su, bu ORDER BY rand() LIMIT 1
CREATE (po)-[:HAS_BUYER_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "Submitted to the Supplier by the Buyer"})-[:VETTED_BY]->(bu),
       (po)-[:HAS_SUPPLIER_NEW_RFQ]->(:PoNewRFQ {Name: "PoNewRFQ"}),
       (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(:PoRejectedRFQ {Name: "PoRejectedRFQ"}),
       (su)-[:IS_SUBMITTED_PO_STATE]->(po)
DELETE ap
WITH po, s, snp
CREATE (snp)-[:IS_SUPPLIER_NEW_PO_STATE]->(po)
RETURN "[SUBMITTED] " + po.PONumber + " sent to " + s.CompanyName + ", awaiting its RFQ" AS alert
CYPHER

# -----------------------------------------------------------------------------
# 5. RFQ vetting (rule: every line within the PO's budget for it).
# -----------------------------------------------------------------------------
sq nw-rfq-vetting 4 \
  'MATCH (s:SubmittedPoS)-[:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr:PoNewRFQ)-[:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ) RETURN DISTINCT id(rfq) AS id' <<'CYPHER'
MATCH (rfq) WHERE id(rfq) = quineId($that.data.id) AND $that.meta.isPositiveMatch = true
MATCH (pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq)-[:IS_RFQ_FOR_PO]->(po:PurchaseOrder)-[:HAS_SUPPLIER_REJECTED_RFQ]->(prr)
MATCH (rfq)-[:HAS_RFQ_ITEM]->(rfi:RFQItem)-[:RFQ_ITEM_PRODUCT]->(p:Product)<-[:PO_ITEM_PRODUCT]-(poi:POItem)<-[:HAS_PO_ITEM]-(po)
WITH rfq, r, po, prr,
     sum(rfi.RFQqt * rfi.RFQcost) AS quoted,
     sum(poi.POqt * (p.UnitPrice * poi.POPriceDiscount)) AS budget,
     collect(CASE WHEN poi.POqt * (p.UnitPrice * poi.POPriceDiscount) < rfi.RFQqt * rfi.RFQcost THEN p.ProductName END) AS overBudget
OPTIONAL MATCH (po)-[already:HAS_APPROVED_RFQ]->()
MATCH (ro) WHERE id(ro) = idFrom("RolE", "Buyer")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(bu:Employee)
WITH rfq, r, po, prr, quoted, budget, overBudget, already, bu ORDER BY rand() LIMIT 1
WITH rfq, r, po, prr, quoted, budget, bu,
     CASE WHEN already IS NOT NULL THEN "the PO already has an approved RFQ"
          WHEN size(overBudget) > 0 THEN "over budget on " + reduce(t = "", x IN overBudget | t + x + " ")
          ELSE null END AS reason
FOREACH (_ IN CASE WHEN reason IS NOT NULL THEN [1] ELSE [] END |
  DELETE r
  CREATE (rfq)-[:HAS_BUYER_RFQ_REJECTION]->(:VettingDecision {Date: datetime(), Comment: "Rejected by the Buyer: " + reason})-[:VETTED_BY]->(bu),
         (prr)-[:IS_SUPPLIER_REJECTED_RFQ_STATE]->(rfq))
FOREACH (_ IN CASE WHEN reason IS NULL THEN [1] ELSE [] END |
  DELETE r
  CREATE (rfq)-[:HAS_BUYER_RFQ_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "Approved by the Buyer: within the PO budget"})-[:VETTED_BY]->(bu),
         (po)-[:HAS_APPROVED_RFQ]->(rfq))
RETURN "[RFQ " + CASE WHEN reason IS NULL THEN "APPROVED] " ELSE "REJECTED] " END + rfq.RFQNumber + " for " + po.PONumber
       + " quoted $" + toString(round(quoted, 2)) + " / budget $" + toString(round(budget, 2))
       + CASE WHEN reason IS NULL THEN "" ELSE " (" + reason + ")" END AS alert
CYPHER

# -----------------------------------------------------------------------------
# 6. An approved RFQ puts its quantities on order (atomic int.add), once:
#    rfq.OnOrderPosted stamps that it was counted. Without the stamp the
#    backfill would count again the RFQs the batch already put on order.
# -----------------------------------------------------------------------------
sq nw-rfq-approved-on-order 4 \
  'MATCH (po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(rfq:RFQ) RETURN DISTINCT id(rfq) AS id' <<'CYPHER'
MATCH (rfq) WHERE id(rfq) = quineId($that.data.id) AND $that.meta.isPositiveMatch = true
  AND rfq.OnOrderPosted IS NULL
SET rfq.OnOrderPosted = datetime()
WITH rfq
MATCH (po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(rfq)-[:HAS_RFQ_ITEM]->(rfi:RFQItem)-[:RFQ_ITEM_PRODUCT]->(p:Product)-[:HAS_SUPPLY_ORDER]->(suo)
CALL int.add(suo, "UnitsOnOrder", toInteger(rfi.RFQqt)) YIELD result
RETURN "[ON ORDER] " + po.PONumber + ": " + reduce(t = "", x IN collect(p.ProductName + " +" + toString(toInteger(rfi.RFQqt))) | t + x + "  ") AS alert
CYPHER

# -----------------------------------------------------------------------------
# 7. Finance pays and closes a delivered PO, on both the procurement and the
#    supplier side.
# -----------------------------------------------------------------------------
sq nw-finance-closure 4 \
  'MATCH (sub:SubmittedPoS)-[:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_WAREHOUSE_DELIVERY]->(d:WarehouseDelivery) RETURN DISTINCT id(po) AS id' <<'CYPHER'
MATCH (po) WHERE id(po) = quineId($that.data.id) AND $that.meta.isPositiveMatch = true
MATCH (t) WHERE id(t) = idFrom("PoS")
MATCH (cpo)<-[:HAS_CLOSED_PO_STATE]-(t)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS)-[r1:IS_SUBMITTED_PO_STATE]->(po)-[:HAS_WAREHOUSE_DELIVERY]->(:WarehouseDelivery),
      (po)<-[r2:IS_SUPPLIER_OPEN_PO_STATE]-(:SupplierOpenPoS)<-[:HAS_SUPPLIER_OPEN_POS]-(su:Supplier)-[:HAS_SUPPLIER_CLOSED_POS]->(scp)
MATCH (po) WHERE NOT (po)-[:HAS_FINANCE_PAYMENT]->()
MATCH (ro) WHERE id(ro) = idFrom("RolE", "Finance")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(f:Employee)
WITH po, cpo, scp, r1, r2, su, f ORDER BY rand() LIMIT 1
CREATE (po)-[:HAS_FINANCE_PAYMENT]->(:FinancePayment {Date: datetime(), Comment: "The PO has been paid by Finance and the PO is now closed."})-[:PAID_BY]->(f),
       (cpo)-[:IS_CLOSED_PO_STATE]->(po),
       (scp)-[:HAS_SUPPLIER_CLOSED_PO_STATE]->(po)
DELETE r1, r2
RETURN "[PO CLOSED] " + po.PONumber + " paid to " + su.CompanyName AS alert
CYPHER

if [ "$FAILED" -gt 0 ]; then
  echo "ERROR: $FAILED standing query(ies) failed to register -- nothing propagated." >&2
  exit 1
fi

# Backfill: apply all standing queries to the data already in the graph (the
# batch leaves POs and RFQs mid-workflow, and products in LowStock).
printf '  %-28s HTTP %s\n' "propagate (backfill)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API:propagate?includeSleeping=true")"
echo "Done. Start the outside-world loops with:  python3 NorthwindPlus_Stress_Test_Quine.py --mode sq"
