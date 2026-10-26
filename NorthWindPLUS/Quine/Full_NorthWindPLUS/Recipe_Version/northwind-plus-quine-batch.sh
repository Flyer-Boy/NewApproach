#!/usr/bin/env bash
# =============================================================================
# NorthWind PLUS v2.4 (no edge properties) -> Quine batch loader
#
# Builds the whole NorthWind PLUS graph in a running Quine through its REST
# API: the CSV import, every state Collection, the PLUS roles and employees,
# and one pass of every workflow command the simulation loops will run later
# (customer orders, PO creation, L1/L2/L3 vetting, resubmission, Buyer
# submission, supplier RFQs, RFQ vetting and resubmission, stock threshold
# update, warehouse receiving, finance close, order fulfillment). Checkpoints
# print what the graph holds along the way; the last checkpoints are
# invariants that make the script fail if broken.
#
# LowStock: products that reached their reorder point (stock + POs in flight
# - open-order demand, against the threshold) are members of the LowStocK
# Collection. It is re-evaluated after every step that changes one of those
# inputs, and PO creation works from it -- the hook for a standing query.
# The recommendation layer is NOT part of this batch any more; it is optional,
# in northwind-plus-quine-recommendations.sh.
#
# Usage (from WSL, with Quine running WITHOUT a recipe):
#     docker run -d --name quine -p 8080:8080 thatdot/quine
#     ./northwind-plus-quine-batch.sh --reset
#
#   --reset        delete everything in the graph first (MATCH (n) DETACH DELETE n).
#                  Without it the script refuses to run on a non-empty graph.
#   --import-only  import + setup only (CSV data, Collections, PLUS roles and staff,
#                  initial LowStock), no workflow test pass; then switch the
#                  simulation on (Simulation.Ready = true). This is the mode to use
#                  with the simulation recipe (northwind-plus-simulation.yaml):
#                  start Quine with the recipe FIRST, then run this.
#   --from N       resume at step N (steps before N are skipped).
#   --quine URL    Quine base URL (default http://localhost:8080).
#
# Endpoint (checked against Quine 2.1.1's own OpenAPI spec):
#     POST /api/v2/graph/quine/cypher:query      body: {"text": "<cypher>", "parameters": {}}
# Every step is one such call: run() below builds the JSON body from the
# Cypher heredoc and sends it with curl, so the Cypher stays readable and the
# quoting inside it (e.g. "Chef Anton's") cannot break the shell command.
#
# Quine-specific choices (the model itself is v2.4, unchanged):
#   * Identity via idFrom(): every proper-noun node gets a deterministic id,
#     e.g. idFrom("Product", "11"), and every singleton Collection is
#     idFrom("<its label>"), e.g. idFrom("NewPoS"). Imports and workflow
#     commands anchor on these ids instead of scanning labels.
#   * Isotope counters (UnitsInStock, UnitsOnOrder) are changed with Quine's
#     atomic int.add(), so concurrent loops cannot lose updates.
#   * Quine has no randomUUID(): generated numbers (CO-, PO-, RFQ-, SH-) use
#     the new node's own id, strId(n).
#   * Address nodes are identified by their value (address, city, region,
#     postal code, country), so a shipment to a customer's address links to
#     the same Address node instead of looking it up by comparing fields.
#   * No apoc.lock and no transactions in Quine: queries are not isolated
#     from each other, so two loops running the SAME command concurrently can
#     both pick the same PO. The guards below (NOT ...) narrow that window.
# =============================================================================

set -uo pipefail

QUINE="http://localhost:8080"
FROM=1
RESET=0
IMPORT_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --reset) RESET=1; shift ;;
    --import-only) IMPORT_ONLY=1; shift ;;
    --from)  FROM="$2"; shift 2 ;;
    --quine) QUINE="$2"; shift 2 ;;
    -h|--help) sed -n '2,46p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

ENDPOINT="${QUINE}/api/v2/graph/quine/cypher:query?timeout=600s"
CSV="https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWindPLUS/Import"
STEP=0
for cmd in curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' is required" >&2; exit 1; }
done

# --- helpers -----------------------------------------------------------------

# post <cypher>  -> prints the response body, then the HTTP code on the last line
post() {
  python3 -c 'import json,sys; sys.stdout.write(json.dumps({"text": sys.argv[1], "parameters": {}}))' "$1" |
    curl -sS -m 900 -w '\n%{http_code}' -X POST "$ENDPOINT" \
         -H 'Content-Type: application/json' --data-binary @-
}

# exec_query <title> <cypher>  -> body on stdout; exits the script on any error
exec_query() {
  local title="$1" q="${2//\{\{CSV\}\}/$CSV}" out code body
  out="$(post "$q")" || { echo "ERROR: cannot reach Quine at $QUINE" >&2; exit 1; }
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  if [ "$code" != "200" ] || [[ "$body" == '{"error"'* ]]; then
    echo >&2
    echo "FAILED at step $STEP: $title (HTTP $code)" >&2
    printf '%s' "$body" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["error"]["message"])
except Exception: print(sys.stdin.read())' >&2
    echo "Fix it, then resume with:  $0 --from $STEP" >&2
    exit 1
  fi
  printf '%s' "$body"
}

# summarise <body>  -> one short line: row count, or the single value returned
summarise() {
  printf '%s' "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin); r = d.get("results", [])
if not d.get("columns"): print("ok")
elif len(r) == 1: print(", ".join(f"{c}={v}" for c, v in zip(d["columns"], r[0])))
else: print(f"{len(r)} rows")'
}

# table <body>  -> the result as an aligned table
table() {
  printf '%s' "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin); cols = d.get("columns", []); rows = [["" if v is None else str(v) for v in r] for r in d.get("results", [])]
w = [max([len(c)] + [len(r[i]) for r in rows]) for i, c in enumerate(cols)]
print("        " + "  ".join(c.ljust(w[i]) for i, c in enumerate(cols)))
for r in rows: print("        " + "  ".join(v.ljust(w[i]) for i, v in enumerate(r)))'
}

begin_step() { STEP=$((STEP + 1)); [ "$STEP" -ge "$FROM" ]; }
skipped()    { printf '  %3d  %-74s skipped\n' "$STEP" "$1"; }

# run "title" <<'CYPHER' ... CYPHER          one write command
run() {
  local title="$1" q; q="$(cat)"
  begin_step || { skipped "$title"; return 0; }
  printf '  %3d  %-74s ' "$STEP" "$title"
  local body; body="$(exec_query "$title" "$q")" || exit 1
  summarise "$body"
}

# repeat N "title" <<'CYPHER' ... CYPHER     the same command N times (a loop command)
repeat() {
  local n="$1" title="$2" q; q="$(cat)"
  begin_step || { skipped "$title"; return 0; }
  printf '  %3d  %-74s ' "$STEP" "$title (x$n)"
  local i body
  for i in $(seq 1 "$n"); do body="$(exec_query "$title" "$q")" || exit 1; done
  echo "ok"
}

# check "title" <<'CYPHER' ... CYPHER        checkpoint: prints the result table
check() {
  local title="$1" q; q="$(cat)"
  begin_step || { skipped "CHECK: $title"; return 0; }
  printf '  %3d  CHECK: %s\n' "$STEP" "$title"
  local body; body="$(exec_query "$title" "$q")" || exit 1
  table "$body"
}

# must_be_zero "title" <<'CYPHER' ... CYPHER  invariant: the query returns one number that must be 0
must_be_zero() {
  local title="$1" q; q="$(cat)"
  begin_step || { skipped "INVARIANT: $title"; return 0; }
  printf '  %3d  %-74s ' "$STEP" "INVARIANT: $title"
  local body v; body="$(exec_query "$title" "$q")" || exit 1
  v="$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["results"][0][0])')"
  if [ "$v" = "0" ]; then echo "ok (0)"; else echo "VIOLATED ($v)"; INVARIANT_FAILURES=$((INVARIANT_FAILURES + 1)); fi
}
INVARIANT_FAILURES=0

section() { [ "$FROM" -le "$((STEP + 1))" ] || return 0; echo; echo "== $1"; }

# LowStock re-evaluation, run after every step that changes a product's stock,
# its POs in flight, its open-order demand or its threshold. A product is in
# LowStocK when  UnitsInStock + qty on active, not yet delivered POs
#                - qty on open customer orders - 0.5 x StockThreshold  <=  StockThreshold
# (the reorder rule of v2.4's PO Creation). Membership is the IS_LOW_STOCK_PRODUCT
# edge from the LowStocK Collection: the verdict is a position, not a property.
LOWSTOCK_EVAL=$(cat <<'CYPHER'
MATCH (av), (ls) WHERE id(av) = idFrom("ProductStatusAvailablE") AND id(ls) = idFrom("LowStocK")
MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[:HAS_PO_ITEM]->(poi:POItem)-[:PO_ITEM_PRODUCT]->(p)
WHERE NOT (activePO)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH ls, p, r, i, sum(coalesce(poi.POqt, 0)) AS pending
OPTIONAL MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(oi:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
WITH ls, p, r, i, pending, sum(coalesce(oi.Quantity, 0)) AS openQty
WITH ls, p, i.UnitsInStock + pending - openQty - (r.StockThreshold * 0.5) <= r.StockThreshold AS low
OPTIONAL MATCH (ls)-[e:IS_LOW_STOCK_PRODUCT]->(p)
FOREACH (_ IN CASE WHEN low AND e IS NULL THEN [1] ELSE [] END | CREATE (ls)-[:IS_LOW_STOCK_PRODUCT]->(p))
FOREACH (_ IN CASE WHEN NOT low AND e IS NOT NULL THEN [1] ELSE [] END | DELETE e)
RETURN sum(CASE WHEN low THEN 1 ELSE 0 END) AS lowStock, count(p) AS evaluated
CYPHER
)
evaluate_low_stock() { run "Re-evaluate LowStock ($1)" <<<"$LOWSTOCK_EVAL"; }

# --- preflight ---------------------------------------------------------------

echo "NorthWind PLUS v2.4 -> Quine at $QUINE"
BUILD="$(curl -sS -m 10 "${QUINE}/api/v1/admin/build-info" 2>/dev/null)" || { echo "ERROR: Quine is not answering at $QUINE" >&2; exit 1; }
echo "Quine build: $BUILD"

SQS="$(curl -sS -m 10 "${QUINE}/api/v2/graph/quine/standingQueries" 2>/dev/null | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin); items = d.get("items", d) if isinstance(d, dict) else d
    print(" ".join(sorted(x["name"] for x in items if x.get("name", "").startswith("nw-"))))
except Exception: print("")')"
if [ -n "$SQS" ] && [ "$IMPORT_ONLY" = 0 ]; then
  echo "ERROR: NorthWind standing queries are running in this Quine ($SQS)." >&2
  echo "       They would race the workflow test pass. Use --import-only (the simulation recipe" >&2
  echo "       does the workflow), or remove them first: ./register-standing-queries.sh --remove" >&2
  exit 1
fi
[ "$IMPORT_ONLY" = 1 ] && echo "Mode: import + setup only, then switch the simulation on"

if [ "$FROM" -le 1 ]; then
  NODES="$(exec_query "count nodes" 'MATCH (n) RETURN count(n) AS n' | python3 -c 'import json,sys; print(json.load(sys.stdin)["results"][0][0])')"
  if [ "$NODES" != "0" ]; then
    if [ "$RESET" = 1 ]; then
      echo "Graph has $NODES nodes; --reset given, deleting them."
      exec_query "reset" 'MATCH (n) DETACH DELETE n' >/dev/null || exit 1
    else
      echo "ERROR: the graph already has $NODES nodes. Re-run with --reset to delete them first," >&2
      echo "       or with --from N to resume a previous run." >&2
      exit 1
    fi
  fi
fi

# =============================================================================
section "IMPORT -- the original NorthWind data, normalized"
# =============================================================================

run "Collections used by the import (CategorieS, product status, CustomerS, RoleS, ShipperS, OrderS + order statuses)" <<'CYPHER'
MATCH (k), (disc), (avail), (cs), (rs), (ss), (os), (open), (ful), (can)
WHERE id(k)     = idFrom("CategorieS")
  AND id(disc)  = idFrom("ProductStatusDiscontinueD")
  AND id(avail) = idFrom("ProductStatusAvailablE")
  AND id(cs)    = idFrom("CustomerS")
  AND id(rs)    = idFrom("RoleS")
  AND id(ss)    = idFrom("ShipperS")
  AND id(os)    = idFrom("OrderS")
  AND id(open)  = idFrom("OrderStatusOpeN")
  AND id(ful)   = idFrom("OrderStatusFulfilleD")
  AND id(can)   = idFrom("OrderStatusCanceleD")
SET k:CategorieS, k.Name = "CategorieS",
    disc:ProductStatusDiscontinueD, disc.Status = "Discontinued",
    avail:ProductStatusAvailablE, avail.Status = "Available",
    cs:CustomerS, cs.Name = "CustomerS",
    rs:RoleS, rs.Name = "RoleS",
    ss:ShipperS, ss.Name = "ShipperS",
    os:OrderS, os.Name = "OrderS",
    open:OrderStatusOpeN, open.Status = "Open",
    ful:OrderStatusFulfilleD, ful.Status = "Fulfilled",
    can:OrderStatusCanceleD, can.Status = "Canceled"
CREATE (os)-[:HAS_OPEN_ORDER_STATUS]->(open),
       (os)-[:HAS_FULFILLED_ORDER_STATUS]->(ful),
       (os)-[:HAS_CANCELED_ORDER_STATUS]->(can)
CYPHER

run "Product categories (+ CategorieS superset)" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/categories.csv" AS row
MATCH (c), (k)
WHERE id(c) = idFrom("ProductCategorY", row.CategoryID) AND id(k) = idFrom("CategorieS")
SET c:ProductCategorY, c.CategoryID = row.CategoryID, c.CategoryName = row.CategoryName, c.Description = row.Description
CREATE (k)-[:HAS_CATEGORY]->(c)
CYPHER

run "Suppliers + their Address and Contact" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/suppliers.csv" AS row
WITH row, replace(replace(replace(row.CompanyName, " ", ""), "'", ""), ".", "") AS dom
MATCH (s), (a), (c)
WHERE id(s) = idFrom("Supplier", row.SupplierID)
  AND id(a) = idFrom("Address", coalesce(row.Address, ""), coalesce(row.City, ""), coalesce(row.Region, ""), coalesce(row.PostalCode, ""), coalesce(row.Country, ""))
  AND id(c) = idFrom("Contact", "Supplier", row.SupplierID)
SET s:Supplier, s.SupplierID = row.SupplierID, s.CompanyName = row.CompanyName, s.HomePage = "https://www." + dom + ".com",
    a:Address, a.Address = row.Address, a.City = row.City, a.Region = row.Region, a.PostalCode = row.PostalCode, a.Country = row.Country,
    c:Contact, c.ContactName = row.ContactName, c.ContactTitle = row.ContactTitle, c.Phone = row.Phone, c.Fax = row.Fax,
    c.Email = replace(row.ContactName, " ", ".") + "@" + dom + ".com"
CREATE (s)-[:HAS_SUPPLIER_ADDRESS]->(a), (s)-[:HAS_SUPPLIER_CONTACT]->(c)
CYPHER

run "Products + isotopes (InventoryLevel, ReorderLevel, OrderLevel), category, status, supplier" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/products.csv" AS row
MATCH (p), (inv), (rl), (ol), (cat), (s), (disc), (avail)
WHERE id(p)     = idFrom("Product", row.ProductID)
  AND id(inv)   = idFrom("InventoryLevel", row.ProductID)
  AND id(rl)    = idFrom("ReorderLevel", row.ProductID)
  AND id(ol)    = idFrom("OrderLevel", row.ProductID)
  AND id(cat)   = idFrom("ProductCategorY", row.CategoryID)
  AND id(s)     = idFrom("Supplier", row.SupplierID)
  AND id(disc)  = idFrom("ProductStatusDiscontinueD")
  AND id(avail) = idFrom("ProductStatusAvailablE")
SET p:Product, p.ProductID = row.ProductID, p.ProductName = row.ProductName,
    p.UnitPrice = toFloat(row.UnitPrice), p.QuantityPerUnit = row.QuantityPerUnit,
    inv:InventoryLevel, inv.UnitsInStock = toInteger(row.UnitsInStock), inv.LastUpdate = datetime(),
    rl:ReorderLevel, rl.StockThreshold = toInteger(row.UnitsInStock) + 10, rl.LastUpdate = datetime(),
    ol:OrderLevel, ol.UnitsOnOrder = 0, ol.LastUpdate = datetime()
CREATE (p)-[:HAS_INVENTORY_LEVEL]->(inv),
       (p)-[:HAS_REORDER_LEVEL]->(rl),
       (p)-[:HAS_SUPPLY_ORDER]->(ol),
       (cat)-[:IS_PRODUCT_CATEGORY_OF]->(p),
       (p)-[:HAS_PRODUCT_SUPPLIER]->(s),
       (s)-[:SUPPLIES]->(p)
FOREACH (_ IN CASE WHEN toInteger(row.Discontinued) = 1 THEN [1] ELSE [] END | CREATE (disc)-[:IS_DISCONTINUED_PRODUCT]->(p))
FOREACH (_ IN CASE WHEN toInteger(row.Discontinued) = 0 THEN [1] ELSE [] END | CREATE (avail)-[:IS_AVAILABLE_PRODUCT]->(p))
CYPHER

run "Customers + Address and Contact (+ CustomerS superset)" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/customers.csv" AS row
WITH row, replace(replace(replace(row.CompanyName, " ", ""), "'", ""), ".", "") AS dom
MATCH (c), (a), (ct), (cs)
WHERE id(c)  = idFrom("Customer", row.CustomerID)
  AND id(a)  = idFrom("Address", coalesce(row.Address, ""), coalesce(row.City, ""), coalesce(row.Region, ""), coalesce(row.PostalCode, ""), coalesce(row.Country, ""))
  AND id(ct) = idFrom("Contact", "Customer", row.CustomerID)
  AND id(cs) = idFrom("CustomerS")
SET c:Customer, c.CustomerID = row.CustomerID, c.CompanyName = row.CompanyName,
    a:Address, a.Address = row.Address, a.City = row.City, a.Region = row.Region, a.PostalCode = row.PostalCode, a.Country = row.Country,
    ct:Contact, ct.ContactName = row.ContactName, ct.ContactTitle = row.ContactTitle, ct.Phone = row.Phone, ct.Fax = row.Fax,
    ct.Email = replace(row.ContactName, " ", ".") + "@" + dom + ".com"
CREATE (cs)-[:IS_CUSTOMER]->(c), (c)-[:HAS_CUSTOMER_ADDRESS]->(a), (c)-[:HAS_CUSTOMER_CONTACT]->(ct)
CYPHER

run "Roles from the employee titles (+ RoleS superset)" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/employees.csv" AS row
MATCH (l), (rs)
WHERE id(l) = idFrom("RolE", row.Title) AND id(rs) = idFrom("RoleS")
SET l:RolE, l.Title = row.Title
CREATE (rs)-[:HAS_ROLE_TITLE]->(l)
CYPHER

run "Employees + Person, home Address, Notes, active role" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/employees.csv" AS row
MATCH (e), (pr), (a), (nt), (l)
WHERE id(e)  = idFrom("Employee", row.EmployeeID)
  AND id(pr) = idFrom("Person", row.EmployeeID)
  AND id(a)  = idFrom("Address", coalesce(row.Address, ""), coalesce(row.City, ""), coalesce(row.Region, ""), coalesce(row.PostalCode, ""), coalesce(row.Country, ""))
  AND id(nt) = idFrom("Notes", row.EmployeeID)
  AND id(l)  = idFrom("RolE", row.Title)
SET e:Employee, e.EmployeeID = row.EmployeeID, e.Email = row.FirstName + "." + row.LastName + "@northwind.com",
    e.HireDate = row.HireDate, e.Extension = row.Extension, e.PhotoPath = row.PhotoPath,
    pr:Person, pr.FirstName = row.FirstName, pr.LastName = row.LastName, pr.TitleOfCourtesy = row.TitleOfCourtesy,
    pr.BirthDate = row.BirthDate, pr.PersonalPhone = row.HomePhone, pr.PersonalEmail = row.FirstName + "." + row.LastName + "@outlook.com",
    a:Address, a.Address = row.Address, a.City = row.City, a.Region = row.Region, a.PostalCode = row.PostalCode, a.Country = row.Country,
    nt:Notes, nt.Notes = row.Notes
CREATE (l)-[:IS_ACTIVE_ROLE]->(e), (e)-[:HAS_PERSON]->(pr), (pr)-[:HAS_HOME_ADDRESS]->(a), (e)-[:HAS_EMPLOYEE_NOTES]->(nt)
CYPHER

run "Employee reporting lines (REPORTS_TO)" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/employees.csv" AS row
WITH row WHERE row.ReportsTo IS NOT NULL AND row.ReportsTo <> "NULL" AND row.ReportsTo <> ""
MATCH (e), (m)
WHERE id(e) = idFrom("Employee", row.EmployeeID) AND id(m) = idFrom("Employee", row.ReportsTo)
CREATE (e)-[:REPORTS_TO]->(m)
CYPHER

run "Regions" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/regions.csv" AS row
MATCH (r) WHERE id(r) = idFrom("Regions", row.RegionID)
SET r:Regions, r.RegionID = row.RegionID, r.RegionDescription = row.RegionDescription
CYPHER

run "Territories (+ HAS_TERRITORY from their Region)" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/territories.csv" AS row
MATCH (t), (r)
WHERE id(t) = idFrom("Territory", row.TerritoryID) AND id(r) = idFrom("Regions", row.RegionID)
SET t:Territory, t.TerritoryID = row.TerritoryID, t.TerritoryDescription = row.TerritoryDescription
CREATE (r)-[:HAS_TERRITORY]->(t)
CYPHER

run "Employee territories (HAS_EMPLOYEE)" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/employee-territories.csv" AS row
MATCH (t), (e)
WHERE id(t) = idFrom("Territory", row.TerritoryID) AND id(e) = idFrom("Employee", row.EmployeeID)
CREATE (t)-[:HAS_EMPLOYEE]->(e)
CYPHER

run "Shippers (+ ShipperS superset)" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/shippers.csv" AS row
MATCH (s), (ss)
WHERE id(s) = idFrom("Shipper", row.ShipperID) AND id(ss) = idFrom("ShipperS")
SET s:Shipper, s.ShipperID = row.ShipperID, s.CompanyName = row.CompanyName, s.Phone = row.Phone
CREATE (ss)-[:IS_SHIPPER]->(s)
CYPHER

run "Orders + ShipInfo, shipment Address, customer, sales rep, Open/Fulfilled state" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/orders.csv" AS row
WITH row,
     datetime(left(row.OrderDate, 10) + "T" + right(row.OrderDate, 12) + "Z")       AS orderDate,
     datetime(left(row.RequiredDate, 10) + "T" + right(row.RequiredDate, 12) + "Z") AS requiredDate,
     datetime(left(row.ShippedDate, 10) + "T" + right(row.ShippedDate, 12) + "Z")   AS shippedDate
MATCH (o), (si), (a), (c), (e), (sh), (open), (ful)
WHERE id(o)    = idFrom("Order", row.OrderID)
  AND id(si)   = idFrom("ShipInfo", row.OrderID)
  AND id(a)    = idFrom("Address", coalesce(row.ShipAddress, ""), coalesce(row.ShipCity, ""), coalesce(row.ShipRegion, ""), coalesce(row.ShipPostalCode, ""), coalesce(row.ShipCountry, ""))
  AND id(c)    = idFrom("Customer", row.CustomerID)
  AND id(e)    = idFrom("Employee", row.EmployeeID)
  AND id(sh)   = idFrom("Shipper", row.ShipVia)
  AND id(open) = idFrom("OrderStatusOpeN")
  AND id(ful)  = idFrom("OrderStatusFulfilleD")
SET o:Order, o.OrderID = row.OrderID, o.OrderDate = orderDate, o.RequiredDate = requiredDate,
    si:ShipInfo, si.ShippmentID = "SH-" + strId(si), si.ShipName = row.ShipName, si.ShippedDate = shippedDate, si.Freight = toFloat(row.Freight),
    a:Address, a.Address = row.ShipAddress, a.City = row.ShipCity, a.Region = row.ShipRegion, a.PostalCode = row.ShipPostalCode, a.Country = row.ShipCountry
CREATE (o)-[:HAS_ORDER_CUSTOMER]->(c),
       (o)-[:SOLD_BY]->(e),
       (o)-[:HAS_SHIPMENT_INFO]->(si),
       (si)-[:HAS_SHIPPER]->(sh),
       (si)-[:HAS_SHIPMENT_ADDRESS]->(a)
FOREACH (_ IN CASE WHEN shippedDate <> datetime("9999-12-31T00:00:00.000Z") THEN [1] ELSE [] END | CREATE (ful)-[:IS_FULFILLED_ORDER_STATE]->(o))
FOREACH (_ IN CASE WHEN shippedDate =  datetime("9999-12-31T00:00:00.000Z") THEN [1] ELSE [] END | CREATE (open)-[:IS_OPEN_ORDER_STATE]->(o))
CYPHER

run "Order details -> OrderItem nodes" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "{{CSV}}/order-details.csv" AS row
MATCH (o), (oi), (p)
WHERE id(o)  = idFrom("Order", row.OrderID)
  AND id(oi) = idFrom("OrderItem", row.OrderID, row.ProductID)
  AND id(p)  = idFrom("Product", row.ProductID)
SET oi:OrderItem, oi.Quantity = toInteger(row.Quantity), oi.UnitPrice = toFloat(row.UnitPrice), oi.Discount = toFloat(row.Discount)
CREATE (o)-[:HAS_ORDER_ITEM]->(oi), (oi)-[:ORDER_ITEM_PRODUCT]->(p)
CYPHER

run "Restock: +150 units on every product before the simulation" <<'CYPHER'
MATCH (k) WHERE id(k) = idFrom("CategorieS")
MATCH (k)-[:HAS_CATEGORY]->(:ProductCategorY)-[:IS_PRODUCT_CATEGORY_OF]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(i)
CALL int.add(i, "UnitsInStock", 150) YIELD result
RETURN count(result) AS restocked
CYPHER

check "imported nodes per label" <<'CYPHER'
UNWIND ["ProductCategorY", "Supplier", "Product", "InventoryLevel", "ReorderLevel", "OrderLevel", "Customer", "Contact", "Address",
        "RolE", "Employee", "Person", "Notes", "Regions", "Territory", "Shipper", "Order", "ShipInfo", "OrderItem"] AS label
MATCH (n) WHERE label IN labels(n)
RETURN label, count(n) AS nodes
CYPHER

check "orders per state, products per status" <<'CYPHER'
MATCH (os) WHERE id(os) = idFrom("OrderS")
MATCH (os)-[]->(st)
OPTIONAL MATCH (st)-[]->(o:Order)
WITH labels(st)[0] AS collection, count(o) AS members
RETURN collection, members
UNION ALL
MATCH (st) WHERE id(st) IN [idFrom("ProductStatusAvailablE"), idFrom("ProductStatusDiscontinueD")]
MATCH (st)-[]->(p:Product)
RETURN labels(st)[0] AS collection, count(p) AS members
CYPHER

# =============================================================================
section "PLUS -- employee directory, procurement roles, suppliers' states"
# =============================================================================

run "EmployeeDirectorY + every imported employee" <<'CYPHER'
MATCH (ed) WHERE id(ed) = idFrom("EmployeeDirectorY")
SET ed:EmployeeDirectorY, ed.Name = "EmployeeDirectorY"
WITH ed
MATCH (rs) WHERE id(rs) = idFrom("RoleS")
MATCH (rs)-[:HAS_ROLE_TITLE]->(:RolE)-[:IS_ACTIVE_ROLE]->(e:Employee)
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE]->(e)
CYPHER

run "Procurement roles with approval limits" <<'CYPHER'
UNWIND [
  {Title:"Procurement Assistant", Description:"Procurement Assistant / Coordinator", Rules:"Submits purchase orders based on inventory level and demand, tracks deliveries, and coordinates day-to-day tactical tasks"},
  {Title:"SupplierApprover", Description:"Supplier Approver", Rules:"Approves Suppliers in the System"},
  {Title:"Level1Approver", ApprovalBase:0.00, ApprovalLimit:5000.00, Description:"Level 1 Approver", Rules:"Approves PO with a Budget < 5000.00"},
  {Title:"Level2Approver", ApprovalBase:5000.01, ApprovalLimit:12500.00, Description:"Level 2 Approver", Rules:"Approves PO with a Budget > 5000.01 and < 12500.00"},
  {Title:"Level3Approver", ApprovalBase:12500.01, ApprovalLimit:500000.00, Description:"Level 3 Approver", Rules:"Approves PO with a Budget > 12500.01 and < 500000.00"},
  {Title:"Buyer", Description:"Buyer / Purchasing Officer", Rules:"Manages specific product categories, handles routine vendor discovery, and executes purchase transactions."},
  {Title:"WarehouseClerk", Description:"Warehouse Clerk", Rules:"Receives and inspects incoming shipments, updates inventory records, and ensures proper storage of goods."},
  {Title:"Finance", Description:"Finance Officer", Rules:"Manages financial transactions, processes payments, and maintains financial records."}
] AS x
MATCH (r), (rs) WHERE id(r) = idFrom("RolE", x.Title) AND id(rs) = idFrom("RoleS")
SET r:RolE, r += x
CREATE (rs)-[:HAS_ROLE_TITLE]->(r)
CYPHER

run "Supplier states (SupplierS) + all suppliers Approved" <<'CYPHER'
MATCH (v), (pen), (app), (rej)
WHERE id(v) = idFrom("SupplierS") AND id(pen) = idFrom("PendingSupplierS")
  AND id(app) = idFrom("ApprovedSupplierS") AND id(rej) = idFrom("RejectedSupplierS")
SET v:SupplierS, v.Name = "SupplierS", pen:PendingSupplierS, pen.Name = "PendingSupplierS",
    app:ApprovedSupplierS, app.Name = "ApprovedSupplierS", rej:RejectedSupplierS, rej.Name = "RejectedSupplierS"
CREATE (v)-[:HAS_SUPPLIER_PENDING_STATE]->(pen), (v)-[:HAS_SUPPLIER_APPROVED_STATE]->(app), (v)-[:HAS_SUPPLIER_REJECTED_STATE]->(rej)
WITH app
MATCH (s:Supplier)
CREATE (app)-[:IS_SUPPLIER_APPROVED_STATE]->(s)
CYPHER

run "Procurement, warehouse and finance employees (+ Person, role, directory)" <<'CYPHER'
UNWIND [
  {id:"10", email:"Adam.Smith@northwind.com",      ext:"1234", role:"SupplierApprover",      first:"Adam",      last:"Smith",   birth:"1989-07-02 00:00:00.000", phone:"9551062551", pmail:"Adam@email.com"},
  {id:"11", email:"Mary.Jane@northwind.com",       ext:"1235", role:"SupplierApprover",      first:"Mary",      last:"Jane",    birth:"1995-09-10 00:00:00.000", phone:"909870092",  pmail:"Mary@email.com"},
  {id:"12", email:"Gloria.Gaynor@northwind.com",   ext:"1236", role:"Level1Approver",        first:"Gloria",    last:"Gaynor",  birth:"1983-09-7 00:00:00.000",  phone:"559831373",  pmail:"Gloria@email.com"},
  {id:"21", email:"Gabriel.Garcia@northwind.com",  ext:"1246", role:"Level1Approver",        first:"Gabriel",   last:"Garcia",  birth:"1997-03-6 00:00:00.000",  phone:"559931373",  pmail:"Gabriel@email.com"},
  {id:"13", email:"Sara.Vaughan@northwind.com",    ext:"127",  role:"Level2Approver",        first:"Sara",      last:"Vaughan", birth:"1984-03-27 00:00:00.000", phone:"4849810343", pmail:"Sara@email.com"},
  {id:"22", email:"Steve.Martin@northwind.com",    ext:"1247", role:"Level2Approver",        first:"Steve",     last:"Martin",  birth:"1984-03-27 00:00:00.000", phone:"4849910343", pmail:"Steve.Martin@email.com"},
  {id:"14", email:"Christine.McVie@northwind.com", ext:"1238", role:"Level3Approver",        first:"Christine", last:"McVie",   birth:"1973-07-12 00:00:00.000", phone:"9998344731", pmail:"Christine@email.com"},
  {id:"23", email:"Carmen.Miranda@northwind.com",  ext:"1248", role:"Level3Approver",        first:"Carmen",    last:"Miranda", birth:"1979-02-09 00:00:00.000", phone:"8898344731", pmail:"Carmen.Miranda@email.com"},
  {id:"15", email:"Cloe.Bailey@northwind.com",     ext:"1239", role:"Buyer",                 first:"Cloe",      last:"Bailey",  birth:"1998-07-01 00:00:00.000", phone:"998195044",  pmail:"Cloe@email.com"},
  {id:"16", email:"Albert.Camus@northwind.com",    ext:"1240", role:"Procurement Assistant", first:"Albert",    last:"Camus",   birth:"1993-11-07 00:00:00.000", phone:"983435644",  pmail:"Albert@email.com"},
  {id:"17", email:"Bernard.Shaw@northwind.com",    ext:"1241", role:"Procurement Assistant", first:"Bernard",   last:"Shaw",    birth:"1983-07-26 00:00:00.000", phone:"978535644",  pmail:"Bernard@email.com"},
  {id:"18", email:"Carlos.Santana@northwind.com",  ext:"1242", role:"Procurement Assistant", first:"Carlos",    last:"Santana", birth:"1987-07-20 00:00:00.000", phone:"97853474",   pmail:"Carlos@email.com"},
  {id:"19", email:"John.Doe@northwind.com",        ext:"1243", role:"WarehouseClerk",        first:"John",      last:"Doe",     birth:"1990-07-20 00:00:00.000", phone:"95644474",   pmail:"John@email.com"},
  {id:"24", email:"James.Ingram@northwind.com",    ext:"1253", role:"WarehouseClerk",        first:"James",     last:"Ingram",  birth:"1980-07-20 00:00:00.000", phone:"95656774",   pmail:"James.Ingram@email.com"},
  {id:"20", email:"Jane.Doe@northwind.com",        ext:"1244", role:"Finance",               first:"Jane",      last:"Doe",     birth:"1985-03-15 00:00:00.000", phone:"96755574",   pmail:"Jane@email.com"}
] AS x
MATCH (ed), (e), (pr), (ro)
WHERE id(ed) = idFrom("EmployeeDirectorY") AND id(e) = idFrom("Employee", x.id)
  AND id(pr) = idFrom("Person", x.id)       AND id(ro) = idFrom("RolE", x.role)
SET e:Employee, e.EmployeeID = x.id, e.Email = x.email, e.Extension = x.ext,
    pr:Person, pr.FirstName = x.first, pr.LastName = x.last, pr.BirthDate = x.birth, pr.PersonalPhone = x.phone, pr.PersonalEmail = x.pmail
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE]->(e), (e)-[:HAS_PERSON]->(pr), (ro)-[:IS_ACTIVE_ROLE]->(e)
CYPHER

run "SYSTEM user (no role)" <<'CYPHER'
MATCH (ed), (e) WHERE id(ed) = idFrom("EmployeeDirectorY") AND id(e) = idFrom("Employee", "00")
SET e:Employee, e.EmployeeID = "00", e.Email = "system@northwind.com", e.Extension = "0000"
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE]->(e)
CYPHER

run "EmploymentRecord + RoleAssignment event nodes (the start dates)" <<'CYPHER'
MATCH (ed) WHERE id(ed) = idFrom("EmployeeDirectorY")
MATCH (ed)-[:HAS_ACTIVE_EMPLOYEE]->(e:Employee)
MATCH (er) WHERE id(er) = idFrom("EmploymentRecord", e.EmployeeID)
SET er:EmploymentRecord, er.StartDate = datetime()
CREATE (e)-[:HAS_EMPLOYMENT_RECORD]->(er)
WITH e
MATCH (ro:RolE)-[:IS_ACTIVE_ROLE]->(e)
MATCH (ra) WHERE id(ra) = idFrom("RoleAssignment", e.EmployeeID, ro.Title)
SET ra:RoleAssignment, ra.StartDate = datetime()
CREATE (e)-[:HAS_ROLE_ASSIGNMENT]->(ra), (ra)-[:ASSIGNED_ROLE]->(ro)
CYPHER

check "employees per role" <<'CYPHER'
MATCH (rs) WHERE id(rs) = idFrom("RoleS")
MATCH (rs)-[:HAS_ROLE_TITLE]->(r:RolE)
OPTIONAL MATCH (r)-[:IS_ACTIVE_ROLE]->(e:Employee)
RETURN r.Title AS role, count(e) AS employees, r.ApprovalLimit AS approvalLimit
ORDER BY role
CYPHER

if [ "$IMPORT_ONLY" = 0 ]; then
# =============================================================================
section "LOOP: customer orders"
# =============================================================================

repeat 50 "Random customer order (1-11 products)" <<'CYPHER'
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
CREATE (o)-[:HAS_ORDER_ITEM]->(:OrderItem {Quantity: toInteger(round(rand() * 19) + 1), UnitPrice: p.UnitPrice, Discount: rand() * 0.07})-[:ORDER_ITEM_PRODUCT]->(p)
CYPHER

check "open customer orders" <<'CYPHER'
MATCH (op) WHERE id(op) = idFrom("OrderStatusOpeN")
MATCH (op)-[:IS_OPEN_ORDER_STATE]->(o:Order)-[:HAS_ORDER_ITEM]->(oi:OrderItem)
RETURN count(DISTINCT o) AS openOrders, count(oi) AS orderItems, sum(oi.Quantity) AS unitsDemanded
CYPHER

fi

# =============================================================================
section "PO state Collections"
# =============================================================================

run "PoS + NewPoS, ApprovedPoS, RejectedPoS, SubmittedPoS, ClosedPoS" <<'CYPHER'
MATCH (t), (n), (a), (r), (s), (c)
WHERE id(t) = idFrom("PoS") AND id(n) = idFrom("NewPoS") AND id(a) = idFrom("ApprovedPoS")
  AND id(r) = idFrom("RejectedPoS") AND id(s) = idFrom("SubmittedPoS") AND id(c) = idFrom("ClosedPoS")
SET t:PoS, t.Name = "PoS", n:NewPoS, n.Name = "NewPoS", a:ApprovedPoS, a.Name = "ApprovedPoS",
    r:RejectedPoS, r.Name = "RejectedPoS", s:SubmittedPoS, s.Name = "SubmittedPoS", c:ClosedPoS, c.Name = "ClosedPoS"
CREATE (t)-[:HAS_NEW_PO_STATE]->(n), (t)-[:HAS_APPROVED_PO_STATE]->(a), (t)-[:HAS_REJECTED_PO_STATE]->(r),
       (t)-[:HAS_SUBMITTED_PO_STATE]->(s), (t)-[:HAS_CLOSED_PO_STATE]->(c)
CYPHER

run "LowStocK Collection (products at their reorder point)" <<'CYPHER'
MATCH (ls) WHERE id(ls) = idFrom("LowStocK")
SET ls:LowStocK, ls.Name = "LowStock"
CYPHER

run "Each supplier's own PO collections (new / open / closed)" <<'CYPHER'
MATCH (app) WHERE id(app) = idFrom("ApprovedSupplierS")
MATCH (app)-[:IS_SUPPLIER_APPROVED_STATE]->(s:Supplier)
MATCH (n), (o), (c)
WHERE id(n) = idFrom("SupplierNewPoS", s.SupplierID) AND id(o) = idFrom("SupplierOpenPoS", s.SupplierID) AND id(c) = idFrom("SupplierClosedPoS", s.SupplierID)
SET n:SupplierNewPoS, n.Name = "SupplierNewPoS", o:SupplierOpenPoS, o.Name = "SupplierOpenPoS", c:SupplierClosedPoS, c.Name = "SupplierClosedPoS"
CREATE (s)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(n), (s)-[:HAS_SUPPLIER_OPEN_POS]->(o), (s)-[:HAS_SUPPLIER_CLOSED_POS]->(c)
CYPHER

if [ "$IMPORT_ONLY" = 0 ]; then
# =============================================================================
section "LOOP: PO creation and vetting"
# =============================================================================

evaluate_low_stock "after the customer orders"

check "products in LowStock" <<'CYPHER'
MATCH (ls) WHERE id(ls) = idFrom("LowStocK")
MATCH (ls)-[:IS_LOW_STOCK_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(i), (p)-[:HAS_REORDER_LEVEL]->(r), (p)<-[:SUPPLIES]-(s:Supplier)
RETURN p.ProductName AS product, s.CompanyName AS supplier, i.UnitsInStock AS inStock, r.StockThreshold AS threshold
ORDER BY supplier, product
CYPHER

run "PO creation: one PO per supplier for its products in LowStock" <<'CYPHER'
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
WITH e, n, s, collect({p: p, qty: r.StockThreshold - (i.UnitsInStock + AlreadyPendingQty - OpenOrderQty) + (r.StockThreshold * 2) + 1}) AS orderItems
CREATE (po:PurchaseOrder {PODate: datetime()})
SET po.PONumber = "PO-" + left(strId(po), 5) + right(strId(po), 5)
CREATE (po)-[:PO_FOR_SUPPLIER]->(s), (po)-[:PO_CREATED_BY]->(e)
WITH n, po, s, orderItems
UNWIND orderItems AS item
WITH n, po, s, item.p AS p, item.qty AS qty
CREATE (po)-[:HAS_PO_ITEM]->(:POItem {POqt: qty, POPriceDiscount: 0.7})-[:PO_ITEM_PRODUCT]->(p)
WITH n, po, s, count(p) AS items
CREATE (n)-[:IS_NEW_PO_STATE]->(po)
RETURN count(po) AS POsCreated, sum(items) AS POItems
CYPHER

evaluate_low_stock "after PO creation: covered products leave"

check "new POs and their estimated cost (30% supplier discount)" <<'CYPHER'
MATCH (n) WHERE id(n) = idFrom("NewPoS")
MATCH (n)-[:IS_NEW_PO_STATE]->(p:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
RETURN p.PONumber AS PO, s.CompanyName AS supplier, count(id) AS items, round(sum(id.POqt * (i.UnitPrice * id.POPriceDiscount)), 2) AS estimatedCost
ORDER BY estimatedCost
CYPHER

# The vetting steps below follow v2.4 exactly, with one addition taken from your
# MemGraph v2.31: each level skips POs it has already vetted, so the commands are
# safe to repeat in a loop (otherwise L1 could reject a PO it already passed up to L2).

run "L1 vetting: reject 2 POs (demo)" <<'CYPHER'
MATCH (ro), (a), (np0)
WHERE id(ro) = idFrom("RolE", "Level1Approver") AND id(a) = idFrom("RejectedPoS") AND id(np0) = idFrom("NewPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l1:Employee)
WITH a, ro, np0, l1 ORDER BY rand() LIMIT 1
MATCH (np0)-[np:IS_NEW_PO_STATE]->(p:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WHERE NOT (p)-[:HAS_L1_PO_APPROVAL|HAS_L1_PO_REJECTION]->()
WITH a, ro, l1, np, p, sum(id.POqt * (i.UnitPrice * id.POPriceDiscount)) AS POCost ORDER BY p LIMIT 2
WHERE POCost > ro.ApprovalBase
CREATE (p)-[:HAS_L1_PO_REJECTION]->(:VettingDecision {Date: datetime(), Comment: "This PO is rejected by L1 due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(l1),
       (a)-[:IS_REJECTED_PO_STATE]->(p)
DELETE np
RETURN count(p) AS rejected
CYPHER

run "L1 vetting: approve POs within the L1 limit (up to 20)" <<'CYPHER'
MATCH (ro), (a), (np0)
WHERE id(ro) = idFrom("RolE", "Level1Approver") AND id(a) = idFrom("ApprovedPoS") AND id(np0) = idFrom("NewPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l1:Employee)
WITH a, ro, np0, l1 ORDER BY rand() LIMIT 1
MATCH (np0)-[np:IS_NEW_PO_STATE]->(p:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WHERE NOT (p)-[:HAS_L1_PO_APPROVAL|HAS_L1_PO_REJECTION]->()
WITH a, ro, l1, np, p, sum(id.POqt * (i.UnitPrice * id.POPriceDiscount)) AS POCost ORDER BY p LIMIT 20
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L1_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "This PO is approved by L1 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(l1),
       (a)-[:IS_APPROVED_PO_STATE]->(p)
DELETE np
RETURN count(p) AS approved
CYPHER

run "L1 vetting: vet POs above the L1 limit (stay in NewPoS for L2)" <<'CYPHER'
MATCH (ro), (np0) WHERE id(ro) = idFrom("RolE", "Level1Approver") AND id(np0) = idFrom("NewPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l1:Employee)
WITH ro, np0, l1 ORDER BY rand() LIMIT 1
MATCH (np0)-[np:IS_NEW_PO_STATE]->(p:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WHERE NOT (p)-[:HAS_L1_PO_APPROVAL|HAS_L1_PO_REJECTION]->()
WITH ro, l1, np, p, sum(id.POqt * (i.UnitPrice * id.POPriceDiscount)) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L1_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "This PO is approved by L1 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(l1)
RETURN count(p) AS passedToL2
CYPHER

run "L2 vetting: approve L1-vetted POs within the L2 limit" <<'CYPHER'
MATCH (ro), (a), (np0)
WHERE id(ro) = idFrom("RolE", "Level2Approver") AND id(a) = idFrom("ApprovedPoS") AND id(np0) = idFrom("NewPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l2:Employee)
WITH a, ro, np0, l2 ORDER BY rand() LIMIT 1
MATCH (np0)-[np:IS_NEW_PO_STATE]->(p:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WHERE (p)-[:HAS_L1_PO_APPROVAL]->() AND NOT (p)-[:HAS_L2_PO_APPROVAL|HAS_L2_PO_REJECTION]->()
WITH a, ro, l2, np, p, sum(id.POqt * (i.UnitPrice * id.POPriceDiscount)) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "This PO is approved by L2 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(l2),
       (a)-[:IS_APPROVED_PO_STATE]->(p)
DELETE np
RETURN count(p) AS approved
CYPHER

run "L2 vetting: reject 1 PO above the L2 limit (demo)" <<'CYPHER'
MATCH (ro), (a), (np0)
WHERE id(ro) = idFrom("RolE", "Level2Approver") AND id(a) = idFrom("RejectedPoS") AND id(np0) = idFrom("NewPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l2:Employee)
WITH a, ro, np0, l2 ORDER BY rand() LIMIT 1
MATCH (np0)-[np:IS_NEW_PO_STATE]->(p:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WHERE (p)-[:HAS_L1_PO_APPROVAL]->() AND NOT (p)-[:HAS_L2_PO_APPROVAL|HAS_L2_PO_REJECTION]->()
WITH a, ro, l2, np, p, sum(id.POqt * (i.UnitPrice * id.POPriceDiscount)) AS POCost ORDER BY p LIMIT 1
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_REJECTION]->(:VettingDecision {Date: datetime(), Comment: "This PO is rejected by L2 due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(l2),
       (a)-[:IS_REJECTED_PO_STATE]->(p)
DELETE np
RETURN count(p) AS rejected
CYPHER

run "L2 vetting: vet POs above the L2 limit (stay in NewPoS for L3)" <<'CYPHER'
MATCH (ro), (np0) WHERE id(ro) = idFrom("RolE", "Level2Approver") AND id(np0) = idFrom("NewPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l2:Employee)
WITH ro, np0, l2 ORDER BY rand() LIMIT 1
MATCH (np0)-[np:IS_NEW_PO_STATE]->(p:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WHERE (p)-[:HAS_L1_PO_APPROVAL]->() AND NOT (p)-[:HAS_L2_PO_APPROVAL|HAS_L2_PO_REJECTION]->()
WITH ro, l2, np, p, sum(id.POqt * (i.UnitPrice * id.POPriceDiscount)) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "This PO is approved by L2 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(l2)
RETURN count(p) AS passedToL3
CYPHER

run "L3 vetting: reject 1 L2-vetted PO (demo)" <<'CYPHER'
MATCH (ro), (a), (np0)
WHERE id(ro) = idFrom("RolE", "Level3Approver") AND id(a) = idFrom("RejectedPoS") AND id(np0) = idFrom("NewPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l3:Employee)
WITH a, ro, np0, l3 ORDER BY rand() LIMIT 1
MATCH (np0)-[np:IS_NEW_PO_STATE]->(p:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WHERE (p)-[:HAS_L2_PO_APPROVAL]->()
WITH a, ro, l3, np, p, sum(id.POqt * (i.UnitPrice * id.POPriceDiscount)) AS POCost ORDER BY p LIMIT 1
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L3_PO_REJECTION]->(:VettingDecision {Date: datetime(), Comment: "This PO is rejected by L3 due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(l3),
       (a)-[:IS_REJECTED_PO_STATE]->(p)
DELETE np
RETURN count(p) AS rejected
CYPHER

run "L3 vetting: approve up to 2 L2-vetted POs" <<'CYPHER'
MATCH (ro), (a), (np0)
WHERE id(ro) = idFrom("RolE", "Level3Approver") AND id(a) = idFrom("ApprovedPoS") AND id(np0) = idFrom("NewPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(l3:Employee)
WITH a, ro, np0, l3 ORDER BY rand() LIMIT 1
MATCH (np0)-[np:IS_NEW_PO_STATE]->(p:PurchaseOrder)-[:HAS_PO_ITEM]->(id:POItem)-[:PO_ITEM_PRODUCT]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WHERE (p)-[:HAS_L2_PO_APPROVAL]->()
WITH a, ro, l3, np, p, sum(id.POqt * (i.UnitPrice * id.POPriceDiscount)) AS POCost ORDER BY p LIMIT 2
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L3_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "This PO is approved by L3 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(l3),
       (a)-[:IS_APPROVED_PO_STATE]->(p)
DELETE np
RETURN count(p) AS approved
CYPHER

run "PO resubmission: a Procurement Assistant resubmits one rejected PO (lineage kept)" <<'CYPHER'
MATCH (re), (n), (av)
WHERE id(re) = idFrom("RejectedPoS") AND id(n) = idFrom("NewPoS") AND id(av) = idFrom("ProductStatusAvailablE")
MATCH (re)-[:IS_REJECTED_PO_STATE]->(rpo:PurchaseOrder)-[:PO_CREATED_BY]->(e:Employee), (rpo)-[:PO_FOR_SUPPLIER]->(s:Supplier)
WHERE NOT ()-[:HAS_PREVIOUS_PO]->(rpo)
WITH n, av, rpo, e, s ORDER BY rand() LIMIT 1
MATCH (rpo)-[:HAS_PO_ITEM]->(:POItem)-[:PO_ITEM_PRODUCT]->(p:Product)<-[:SUPPLIES]-(s),
      (av)-[:IS_AVAILABLE_PRODUCT]->(p),
      (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[:HAS_PO_ITEM]->(poi2:POItem)-[:PO_ITEM_PRODUCT]->(p)
WHERE NOT (activePO)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH rpo, e, n, s, p, r, i, sum(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty
OPTIONAL MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(op:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
WITH rpo, e, n, s, p, r, i, AlreadyPendingQty, sum(coalesce(op.Quantity, 0)) AS OpenOrderQty
WHERE i.UnitsInStock + AlreadyPendingQty - OpenOrderQty - (r.StockThreshold * 0.5) <= r.StockThreshold
WITH rpo, e, n, s, collect({p: p, qty: r.StockThreshold - (i.UnitsInStock + AlreadyPendingQty - OpenOrderQty) + (r.StockThreshold / 2)}) AS orderItems
WHERE size(orderItems) > 0
CREATE (po:PurchaseOrder {PODate: datetime()})
SET po.PONumber = "PO-" + left(strId(po), 5) + right(strId(po), 5)
CREATE (po)-[:PO_FOR_SUPPLIER]->(s), (po)-[:PO_CREATED_BY]->(e),
       (po)-[:HAS_PREVIOUS_PO]->(rpo),
       (po)-[:HAS_RESUBMISSION_NOTE]->(:ResubmissionNote {Justification: "Reason for resubmission. What changed. What was missing or not accurate in the previous one. Comments, etc. ", Date: datetime()})
WITH n, po, rpo, orderItems
UNWIND orderItems AS item
WITH n, po, rpo, item.p AS p, item.qty AS qty
CREATE (po)-[:HAS_PO_ITEM]->(:POItem {POqt: qty, POPriceDiscount: 0.7})-[:PO_ITEM_PRODUCT]->(p)
WITH n, po, rpo, count(p) AS items
CREATE (n)-[:IS_NEW_PO_STATE]->(po)
RETURN po.PONumber AS resubmittedPO, rpo.PONumber AS resubmittedFrom, items
CYPHER

evaluate_low_stock "after vetting rejections and the resubmission"

check "POs per state after vetting" <<'CYPHER'
MATCH (t) WHERE id(t) = idFrom("PoS")
MATCH (t)-[]->(st)
OPTIONAL MATCH (st)-[]->(po:PurchaseOrder)
RETURN labels(st)[0] AS state, count(po) AS POs
ORDER BY state
CYPHER

# =============================================================================
section "LOOP: Buyer submission, supplier RFQs, RFQ vetting"
# =============================================================================

run "Buyer approves and submits approved POs to their suppliers (up to 10)" <<'CYPHER'
MATCH (ro), (su), (a)
WHERE id(ro) = idFrom("RolE", "Buyer") AND id(su) = idFrom("SubmittedPoS") AND id(a) = idFrom("ApprovedPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(bu:Employee)
WITH su, a, bu ORDER BY rand() LIMIT 1
MATCH (a)-[ap:IS_APPROVED_PO_STATE]->(po:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(s:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp)
WITH ap, s, bu, su, po, snp ORDER BY po LIMIT 10
CREATE (po)-[:HAS_BUYER_PO_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "This PO is approved by Buyer due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(bu),
       (su)-[:IS_SUBMITTED_PO_STATE]->(po),
       (snp)-[:IS_SUPPLIER_NEW_PO_STATE]->(po),
       (po)-[:HAS_SUPPLIER_NEW_RFQ]->(:PoNewRFQ {Name: "PoNewRFQ"}),
       (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(:PoRejectedRFQ {Name: "PoRejectedRFQ"})
DELETE ap
RETURN count(po) AS submitted
CYPHER

run "Suppliers answer their new POs with an RFQ (30% discount)" <<'CYPHER'
MATCH (su:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp)-[r:IS_SUPPLIER_NEW_PO_STATE]->(po:PurchaseOrder)-[:HAS_PO_ITEM]->(pq:POItem)-[:PO_ITEM_PRODUCT]->(p:Product),
      (po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr), (su)-[:HAS_SUPPLIER_OPEN_POS]->(sop)
WITH su, r, po, snr, sop, collect({p: p, qty: pq.POqt, cost: p.UnitPrice * 0.7}) AS rfqItems
CREATE (rfq:RFQ {RFQDate: datetime(), RFQComments: "Thanks for your order, we are able to supply the full PO product request at the discounted price negotiated on our master agreement"})
SET rfq.RFQNumber = "RFQ-" + left(strId(rfq), 5) + right(strId(rfq), 5)
CREATE (rfq)-[:IS_RFQ_FOR_PO]->(po), (rfq)-[:RFQ_FROM_SUPPLIER]->(su), (sop)-[:IS_SUPPLIER_OPEN_PO_STATE]->(po)
DELETE r
WITH rfq, snr, rfqItems
UNWIND rfqItems AS item
WITH rfq, snr, item.p AS p, item.qty AS qty, item.cost AS cost
CREATE (rfq)-[:HAS_RFQ_ITEM]->(:RFQItem {RFQqt: qty, RFQcost: cost})-[:RFQ_ITEM_PRODUCT]->(p)
WITH rfq, snr, count(p) AS items
CREATE (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq)
RETURN count(rfq) AS RFQs, sum(items) AS RFQItems
CYPHER

# v2.4 created one rejection per RFQ *line* (an RFQ with 3 lines got 3 decisions
# and LIMIT 2 counted lines). Here the lines are grouped first, so 2 RFQs are
# rejected with one decision each.
run "Buyer rejects 2 RFQs (demo)" <<'CYPHER'
MATCH (ro), (su) WHERE id(ro) = idFrom("RolE", "Buyer") AND id(su) = idFrom("SubmittedPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(bu:Employee)
WITH su, bu ORDER BY rand() LIMIT 1
MATCH (su)-[:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)-[:HAS_RFQ_ITEM]->(rfi:RFQItem)-[:RFQ_ITEM_PRODUCT]->(p)<-[:PO_ITEM_PRODUCT]-(poi:POItem)<-[:HAS_PO_ITEM]-(po),
      (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(prr)
WHERE poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost
WITH DISTINCT bu, prr, po, r, rfq
ORDER BY po.PONumber DESC LIMIT 2
CREATE (rfq)-[:HAS_BUYER_RFQ_REJECTION]->(:VettingDecision {Date: datetime(), Comment: "This RFQ is rejected by Buyer due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(bu),
       (prr)-[:IS_SUPPLIER_REJECTED_RFQ_STATE]->(rfq)
DELETE r
RETURN count(rfq) AS rejected
CYPHER

run "Suppliers answer any POs still waiting for an RFQ (same command, second pass)" <<'CYPHER'
MATCH (su:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp)-[r:IS_SUPPLIER_NEW_PO_STATE]->(po:PurchaseOrder)-[:HAS_PO_ITEM]->(pq:POItem)-[:PO_ITEM_PRODUCT]->(p:Product),
      (po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr), (su)-[:HAS_SUPPLIER_OPEN_POS]->(sop)
WITH su, r, po, snr, sop, collect({p: p, qty: pq.POqt, cost: p.UnitPrice * 0.7}) AS rfqItems
CREATE (rfq:RFQ {RFQDate: datetime(), RFQComments: "Thanks for your order, we are able to supply the full PO product request at the discounted price negotiated on our master agreement"})
SET rfq.RFQNumber = "RFQ-" + left(strId(rfq), 5) + right(strId(rfq), 5)
CREATE (rfq)-[:IS_RFQ_FOR_PO]->(po), (rfq)-[:RFQ_FROM_SUPPLIER]->(su), (sop)-[:IS_SUPPLIER_OPEN_PO_STATE]->(po)
DELETE r
WITH rfq, snr, rfqItems
UNWIND rfqItems AS item
WITH rfq, snr, item.p AS p, item.qty AS qty, item.cost AS cost
CREATE (rfq)-[:HAS_RFQ_ITEM]->(:RFQItem {RFQqt: qty, RFQcost: cost})-[:RFQ_ITEM_PRODUCT]->(p)
WITH rfq, snr, count(p) AS items
CREATE (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq)
RETURN count(rfq) AS RFQs
CYPHER

run "Buyer approves up to 8 RFQs within the PO budget (UnitsOnOrder += RFQ qty)" <<'CYPHER'
MATCH (ro), (su) WHERE id(ro) = idFrom("RolE", "Buyer") AND id(su) = idFrom("SubmittedPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(bu:Employee)
WITH su, bu ORDER BY rand() LIMIT 1
MATCH (su)-[:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)-[:HAS_RFQ_ITEM]->(rfi:RFQItem)-[:RFQ_ITEM_PRODUCT]->(p)<-[:PO_ITEM_PRODUCT]-(poi:POItem)<-[:HAS_PO_ITEM]-(po)
WHERE poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost
WITH bu, po, rfq, r, collect({p: p, qty: rfi.RFQqt}) AS items
ORDER BY po.PONumber LIMIT 8
CREATE (rfq)-[:HAS_BUYER_RFQ_APPROVAL]->(:VettingDecision {Date: datetime(), Comment: "This RFQ is approved by Buyer due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."})-[:VETTED_BY]->(bu),
       (po)-[:HAS_APPROVED_RFQ]->(rfq)
DELETE r
SET rfq.OnOrderPosted = datetime()
WITH rfq, items
UNWIND items AS item
WITH rfq, item.p AS p, item.qty AS qty
MATCH (p)-[:HAS_SUPPLY_ORDER]->(suo)
CALL int.add(suo, "UnitsOnOrder", toInteger(qty)) YIELD result
RETURN count(DISTINCT rfq) AS approved, count(result) AS linesOnOrder
CYPHER

run "A supplier resubmits one rejected RFQ with a better price (35% discount)" <<'CYPHER'
MATCH (su:Supplier)<-[:RFQ_FROM_SUPPLIER]-(rrfq:RFQ)<-[:IS_SUPPLIER_REJECTED_RFQ_STATE]-(), (rrfq)-[:IS_RFQ_FOR_PO]->(po:PurchaseOrder)
WHERE NOT ()-[:HAS_PREVIOUS_RFQ]->(rrfq)
WITH su, rrfq, po ORDER BY rand() LIMIT 1
MATCH (p:Product)<-[:PO_ITEM_PRODUCT]-(pq:POItem)<-[:HAS_PO_ITEM]-(po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr)
WITH rrfq, su, po, snr, collect({p: p, qty: pq.POqt, cost: p.UnitPrice * 0.65}) AS rfqItems
CREATE (rfq:RFQ {RFQDate: datetime(), RFQComments: "Thanks for your order, we resubmitting our RFQ and hope weare able to supply the full PO product request at the discounted price negotiated on our master agreement"})
SET rfq.RFQNumber = "RFQ-" + left(strId(rfq), 5) + right(strId(rfq), 5)
CREATE (rfq)-[:IS_RFQ_FOR_PO]->(po), (rfq)-[:RFQ_FROM_SUPPLIER]->(su),
       (rfq)-[:HAS_PREVIOUS_RFQ]->(rrfq),
       (rfq)-[:HAS_RESUBMISSION_NOTE]->(:ResubmissionNote {Justification: "This RFQ is a resubmission of the previous rejected RFQ. The Supplier has provided additional justification and/or updated pricing and/or updated product availability.", Date: datetime()})
WITH rfq, po, snr, rfqItems
UNWIND rfqItems AS item
WITH rfq, po, snr, item.p AS p, item.qty AS qty, item.cost AS cost
CREATE (rfq)-[:HAS_RFQ_ITEM]->(:RFQItem {RFQqt: qty, RFQcost: cost})-[:RFQ_ITEM_PRODUCT]->(p)
WITH rfq, po, snr, count(p) AS items
CREATE (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq)
RETURN rfq.RFQNumber AS newRFQ, po.PONumber AS forPO, items
CYPHER

check "RFQs per state" <<'CYPHER'
MATCH (su) WHERE id(su) = idFrom("SubmittedPoS")
MATCH (su)-[:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)<-[:IS_RFQ_FOR_PO]-(rfq:RFQ)
RETURN CASE WHEN (po)-[:HAS_APPROVED_RFQ]->(rfq) THEN "approved"
            WHEN ()-[:IS_SUPPLIER_REJECTED_RFQ_STATE]->(rfq) THEN "rejected"
            ELSE "new (awaiting vetting)" END AS rfqState,
       count(rfq) AS RFQs
CYPHER

# =============================================================================
section "LOOP: stock threshold, warehouse, finance, fulfillment"
# =============================================================================

run "Update stock thresholds: 150% of average monthly ordered quantity" <<'CYPHER'
MATCH (av) WHERE id(av) = idFrom("ProductStatusAvailablE")
MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_REORDER_LEVEL]->(re)
MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(oi:OrderItem)<-[:HAS_ORDER_ITEM]-(o:Order)
WITH p, re, sum(oi.Quantity) AS TotalQuantityOrdered,
     count(DISTINCT (toString(o.OrderDate.year) + "-" + toString(o.OrderDate.month))) AS MonthsWithOrders
SET re.StockThreshold = toInteger(round((toFloat(TotalQuantityOrdered) / MonthsWithOrders) * 1.5)), re.LastUpdate = datetime()
RETURN count(re) AS thresholdsUpdated
CYPHER

evaluate_low_stock "after the threshold update"

run "PO creation with the new thresholds (from LowStock again)" <<'CYPHER'
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
WITH e, n, s, collect({p: p, qty: r.StockThreshold - (i.UnitsInStock + AlreadyPendingQty - OpenOrderQty) + (r.StockThreshold * 2) + 1}) AS orderItems
CREATE (po:PurchaseOrder {PODate: datetime()})
SET po.PONumber = "PO-" + left(strId(po), 5) + right(strId(po), 5)
CREATE (po)-[:PO_FOR_SUPPLIER]->(s), (po)-[:PO_CREATED_BY]->(e)
WITH n, po, s, orderItems
UNWIND orderItems AS item
WITH n, po, s, item.p AS p, item.qty AS qty
CREATE (po)-[:HAS_PO_ITEM]->(:POItem {POqt: qty, POPriceDiscount: 0.7})-[:PO_ITEM_PRODUCT]->(p)
WITH n, po, s, count(p) AS items
CREATE (n)-[:IS_NEW_PO_STATE]->(po)
RETURN count(po) AS POsCreated, sum(items) AS POItems
CYPHER

evaluate_low_stock "after the second PO creation"

run "Warehouse receives up to 5 POs with an approved RFQ (stock up, on-order down)" <<'CYPHER'
MATCH (ro), (sub) WHERE id(ro) = idFrom("RolE", "WarehouseClerk") AND id(sub) = idFrom("SubmittedPoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(wc:Employee)
WITH sub, wc ORDER BY rand() LIMIT 1
MATCH (sub)-[:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(rfq:RFQ)
WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH wc, po, rfq ORDER BY po.PONumber LIMIT 5
MATCH (po)-[:HAS_PO_ITEM]->(poi:POItem)-[:PO_ITEM_PRODUCT]->(p:Product)<-[:RFQ_ITEM_PRODUCT]-(rfi:RFQItem)<-[:HAS_RFQ_ITEM]-(rfq)
WHERE poi.POqt = rfi.RFQqt
WITH wc, po, collect({p: p, qty: rfi.RFQqt}) AS lines
CREATE (po)-[:HAS_WAREHOUSE_DELIVERY]->(:WarehouseDelivery {Date: datetime(), Comment: "The products have been received as per PO at the Warehouse and the Inventory Levels have been updated accordingly."})-[:RECEIVED_BY]->(wc)
WITH po, lines
UNWIND lines AS line
WITH po, line.p AS p, toInteger(line.qty) AS qty
MATCH (p)-[:HAS_INVENTORY_LEVEL]->(inv), (p)-[:HAS_SUPPLY_ORDER]->(suo)
CALL int.add(inv, "UnitsInStock", qty) YIELD result AS stock
CALL int.add(suo, "UnitsOnOrder", -qty) YIELD result AS onOrder
SET inv.LastUpdate = datetime()
RETURN count(DISTINCT po) AS POsReceived, count(*) AS linesReceived
CYPHER

evaluate_low_stock "after warehouse receiving"

run "Finance pays and closes up to 4 delivered POs (procurement + supplier view)" <<'CYPHER'
MATCH (ro), (t) WHERE id(ro) = idFrom("RolE", "Finance") AND id(t) = idFrom("PoS")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(f:Employee)
WITH t, f ORDER BY rand() LIMIT 1
MATCH (cpo)<-[:HAS_CLOSED_PO_STATE]-(t)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS)-[r1:IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[:HAS_WAREHOUSE_DELIVERY]->(:WarehouseDelivery),
      (po)<-[r2:IS_SUPPLIER_OPEN_PO_STATE]-(:SupplierOpenPoS)<-[:HAS_SUPPLIER_OPEN_POS]-(su:Supplier)-[:HAS_SUPPLIER_CLOSED_POS]->(scp)
WHERE NOT (po)-[:HAS_FINANCE_PAYMENT]->()
WITH r1, r2, cpo, scp, f, po ORDER BY po.PONumber LIMIT 4
CREATE (po)-[:HAS_FINANCE_PAYMENT]->(:FinancePayment {Date: datetime(), Comment: "The PO has been paid by Finance and the PO is now closed."})-[:PAID_BY]->(f),
       (cpo)-[:IS_CLOSED_PO_STATE]->(po),
       (scp)-[:HAS_SUPPLIER_CLOSED_PO_STATE]->(po)
DELETE r1, r2
RETURN count(po) AS closed
CYPHER

repeat 5 "Fulfill the oldest open order that is fully in stock (ship it, stock down)" <<'CYPHER'
MATCH (ro), (ss), (op), (f)
WHERE id(ro) = idFrom("RolE", "WarehouseClerk") AND id(ss) = idFrom("ShipperS")
  AND id(op) = idFrom("OrderStatusOpeN") AND id(f) = idFrom("OrderStatusFulfilleD")
MATCH (ro)-[:IS_ACTIVE_ROLE]->(wc:Employee), (ss)-[:IS_SHIPPER]->(s:Shipper)<-[:HAS_SHIPPER]-(si:ShipInfo)
WITH op, f, wc, si, s ORDER BY rand() LIMIT 1
MATCH (op)-[r:IS_OPEN_ORDER_STATE]->(o:Order)-[:HAS_ORDER_ITEM]->(details:OrderItem)-[:ORDER_ITEM_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
WITH f, wc, si, s, o, r,
     count(details) AS TotalLines,
     sum(CASE WHEN inv.UnitsInStock > details.Quantity THEN 1 ELSE 0 END) AS LinesWithStock
WHERE TotalLines = LinesWithStock
WITH f, wc, si, s, o, r ORDER BY o.OrderDate LIMIT 1
MATCH (o)-[:HAS_ORDER_ITEM]->(details:OrderItem)-[:ORDER_ITEM_PRODUCT]->(:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
WITH f, wc, si, s, o, r, collect({qty: details.Quantity, inv: inv}) AS lines
MATCH (o)-[:HAS_ORDER_CUSTOMER]->(:Customer)-[:HAS_CUSTOMER_ADDRESS]->(a)
CREATE (i:ShipInfo {ShippedDate: datetime(), ShipName: si.ShipName, Freight: round(rand() * 100, 2)})
SET i.ShippmentID = "SH-" + strId(i)
CREATE (o)-[:HAS_SHIPMENT_INFO]->(i), (i)-[:HAS_SHIPPER]->(s), (i)-[:HAS_SHIPMENT_ADDRESS]->(a),
       (f)-[:IS_FULFILLED_ORDER_STATE]->(o),
       (o)-[:HAS_WAREHOUSE_FULFILLMENT]->(:WarehouseFulfillment {Date: datetime(), Comment: "Order picked, packed, and shipped by the Warehouse Clerk."})-[:FULFILLED_BY]->(wc)
DELETE r
WITH o, lines
UNWIND lines AS x
WITH o, x.inv AS inv, toInteger(x.qty) AS qty
CALL int.add(inv, "UnitsInStock", -qty) YIELD result
SET inv.LastUpdate = datetime()
RETURN o.OrderID AS fulfilled
CYPHER

evaluate_low_stock "after order fulfillment"

check "POs per state at the end of the workflow pass" <<'CYPHER'
MATCH (t) WHERE id(t) = idFrom("PoS")
MATCH (t)-[]->(st)
OPTIONAL MATCH (st)-[]->(po:PurchaseOrder)
RETURN labels(st)[0] AS state, count(po) AS POs
ORDER BY state
CYPHER

check "inventory dashboard (10 lowest stock)" <<'CYPHER'
MATCH (av) WHERE id(av) = idFrom("ProductStatusAvailablE")
MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv), (p)-[:HAS_REORDER_LEVEL]->(r), (p)-[:HAS_SUPPLY_ORDER]->(suo)
RETURN p.ProductName AS product, inv.UnitsInStock AS inStock, r.StockThreshold AS threshold, suo.UnitsOnOrder AS onOrder
ORDER BY inStock ASC LIMIT 10
CYPHER

else
section "Initial LowStock (the simulation starts from here)"
evaluate_low_stock "initial: open-order demand against stock and thresholds"
check "products in LowStock" <<'CYPHER'
MATCH (ls) WHERE id(ls) = idFrom("LowStocK")
OPTIONAL MATCH (ls)-[:IS_LOW_STOCK_PRODUCT]->(p:Product)
RETURN count(p) AS lowStockProducts
CYPHER
fi

# =============================================================================
section "Invariants (the data-quality checks from the script's last section)"
# =============================================================================

must_be_zero "no product with negative stock" <<'CYPHER'
MATCH (i:InventoryLevel) WHERE i.UnitsInStock < 0 RETURN count(i) AS n
CYPHER

must_be_zero "no product with negative units on order" <<'CYPHER'
MATCH (s:OrderLevel) WHERE s.UnitsOnOrder < 0 RETURN count(s) AS n
CYPHER

must_be_zero "every PO is in exactly one procurement state" <<'CYPHER'
MATCH (po:PurchaseOrder)
WITH po, size([(po)<-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE|IS_REJECTED_PO_STATE|IS_CLOSED_PO_STATE]-(c) | c]) AS states
WHERE states <> 1
RETURN count(po) AS n
CYPHER

must_be_zero "no order both open and fulfilled" <<'CYPHER'
MATCH (o:Order)<-[:IS_OPEN_ORDER_STATE]-(), (o)<-[:IS_FULFILLED_ORDER_STATE]-()
RETURN count(o) AS n
CYPHER

must_be_zero "no PO paid before it was delivered" <<'CYPHER'
MATCH (po:PurchaseOrder)-[:HAS_FINANCE_PAYMENT]->()
WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
RETURN count(po) AS n
CYPHER

must_be_zero "no PO delivered or paid twice" <<'CYPHER'
MATCH (po:PurchaseOrder)
WITH po, size([(po)-[:HAS_WAREHOUSE_DELIVERY]->(d) | d]) AS deliveries, size([(po)-[:HAS_FINANCE_PAYMENT]->(f) | f]) AS payments
WHERE deliveries > 1 OR payments > 1
RETURN count(po) AS n
CYPHER

must_be_zero "UnitsOnOrder matches approved RFQs not yet delivered" <<'CYPHER'
MATCH (av) WHERE id(av) = idFrom("ProductStatusAvailablE")
MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_SUPPLY_ORDER]->(suo)
OPTIONAL MATCH (po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(:RFQ)-[:HAS_RFQ_ITEM]->(rfi:RFQItem)-[:RFQ_ITEM_PRODUCT]->(p)
WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH p, suo, coalesce(sum(rfi.RFQqt), 0) AS pending
WHERE suo.UnitsOnOrder <> pending
RETURN count(p) AS n
CYPHER

must_be_zero "LowStock membership matches the reorder rule for every product" <<'CYPHER'
MATCH (av), (ls) WHERE id(av) = idFrom("ProductStatusAvailablE") AND id(ls) = idFrom("LowStocK")
MATCH (av)-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
OPTIONAL MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[:HAS_PO_ITEM]->(poi:POItem)-[:PO_ITEM_PRODUCT]->(p)
WHERE NOT (activePO)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH ls, p, r, i, sum(coalesce(poi.POqt, 0)) AS pending
OPTIONAL MATCH (p)<-[:ORDER_ITEM_PRODUCT]-(oi:OrderItem)<-[:HAS_ORDER_ITEM]-(:Order)<-[:IS_OPEN_ORDER_STATE]-()
WITH ls, p, r, i, pending, sum(coalesce(oi.Quantity, 0)) AS openQty
WITH ls, p, i.UnitsInStock + pending - openQty - (r.StockThreshold * 0.5) <= r.StockThreshold AS low
OPTIONAL MATCH (ls)-[e:IS_LOW_STOCK_PRODUCT]->(p)
WITH low, e WHERE (low AND e IS NULL) OR (NOT low AND e IS NOT NULL)
RETURN count(*) AS n
CYPHER

check "graph size" <<'CYPHER'
MATCH (n) WITH count(n) AS nodes
MATCH ()-[r]->() RETURN nodes, count(r) AS edges
CYPHER

echo
if [ "$INVARIANT_FAILURES" -gt 0 ]; then
  echo "DONE with $INVARIANT_FAILURES invariant violation(s) -- see above."
  [ "$IMPORT_ONLY" = 1 ] && echo "The simulation was NOT switched on."
  exit 1
fi
if [ "$IMPORT_ONLY" = 1 ]; then
  run "GO LIVE: Simulation.Ready = true (the recipe's streams start acting)" <<'CYPHER'
MATCH (sim) WHERE id(sim) = idFrom("Simulation")
SET sim:Simulation, sim.Name = "Simulation", sim.Ready = true, sim.LiveSince = datetime()
RETURN sim.Ready AS ready
CYPHER
  echo
  echo "DONE: NorthWind PLUS v2.4 is loaded and the simulation is live. Explore it at ${QUINE}"
  [ -z "$SQS" ] && echo "      NOTE: no nw-* standing queries found -- was Quine started with the simulation recipe?"
  exit 0
fi
echo "DONE: NorthWind PLUS v2.4 is loaded in Quine and every workflow command ran once. Explore it at ${QUINE}"
echo "      (optional recommendation layer: ./northwind-plus-quine-recommendations.sh)"
