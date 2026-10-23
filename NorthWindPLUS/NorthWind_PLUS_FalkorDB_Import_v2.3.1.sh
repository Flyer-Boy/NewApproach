#!/usr/bin/env bash
# ------------------------------------------------------------------------------------------------------------------ #
#  NorthWind PLUS Graph Data Model Import v2.3.1 -- FalkorDB port
#  Ported from NorthWind_PLUS_Graph_Data_Model_Import_v2.3.1.cypher (Neo4j Aura). Model unchanged.
#
#  Usage:
#     ./NorthWind_PLUS_FalkorDB_Import_v2.3.1.sh [import|recommend|report|checks|all]   (default: import)
#        import     wipe the graph and run the full 360-degree initialization (Neo4j script lines 73-1129)
#        recommend  run the optional Recommendation Engine layer (RATED / SIMILARITY)
#        report     print the Inventory Level Report
#        checks     run the data-quality / inconsistency checks
#        all        import + recommend + report + checks
#
#  Connection (environment variables):
#     FALKOR_HOST (localhost)  FALKOR_PORT (6379)  FALKOR_USER ()  FALKOR_PASSWORD ()  FALKOR_TLS (0|1)
#     GRAPH (northwind)        REDIS_CLI (redis-cli)  QUERY_TIMEOUT_MS (0 = server default)
#     CSV_BASE  -- where the CSVs live. Default: the GitHub raw folder (FalkorDB LOAD CSV accepts HTTPS URLs).
#                  For local files put them in FalkorDB's IMPORT_FOLDER and set CSV_BASE=file:/
#                  (queries use  CSV_BASE + "/categories.csv").
#
#  -- What changed vs. the Neo4j script (FalkorDB 4.22 Cypher subset) --
#   * datetime()  -> localdatetime()   FalkorDB has no ZONED DATETIME; localdatetime() returns server-clock time
#                                      (UTC on a default server) with no zone attached.
#   * One "now" value per query        WITH localdatetime() AS now ... MERGE (..)-[:X {Date: now}]->(..) so a MERGE
#                                      repeated across rows matches the same edge instead of creating near-duplicates.
#   * CALL (i) { ... }  -> CALL { WITH i ... }   (scoped-variable syntax not supported)
#   * LIMIT <expression> not supported -> random Customer Order lines use a shuffled collect() + list slice.
#   * round(x, 2)       -> round(x * 100) / 100.0
#   * SET x.inv.Prop    -> UNWIND .. WITH x.inv AS inv .. SET inv.Prop   (SET only on a plain alias)
#   * EXISTS(pattern)   -> pattern predicate  (exists() only checks properties in FalkorDB)
#   * OPTIONAL MATCH with 2+ hops ending on an already-bound node -> CALL { WITH p MATCH ... RETURN sum(..) }
#        FalkorDB 4.22.1 BUG (reproduced): e.g. OPTIONAL MATCH (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(o)-[d]->(p)
#        with p bound ignores the status hop and returns *every* Order of p. That silently inflated open demand and
#        pending-PO quantities in PO Creation and the Inventory Report. The CALL form returns the correct rows.
#   * apoc.lock.nodes   -> removed. FalkorDB runs write queries one at a time per graph, so the lock is redundant.
#   * MATCH (n) DETACH DELETE n -> GRAPH.DELETE (drops indexes too; they are recreated below)
#   * ORDER BY <node>   -> ORDER BY id(<node>)  (FalkorDB doesn't define node ordering; id() = creation order)
#   * WITH .. ORDER BY .. LIMIT n WHERE ..  -> split into  WITH .. ORDER BY .. LIMIT n  WITH .. WHERE ..
#        FalkorDB applies that WHERE *before* the LIMIT; the split keeps the LIMIT-first order (as I believe Neo4j
#        behaves -- verify against your Neo4j runs; swapping the two WITH lines gives filter-first).
#   * Order-detail import matches Product/Order by property map (index-friendly) instead of a WHERE cartesian.
#   * Single-property indexes added (the Neo4j script had none) -- performance only, no model change.
#   * Pure read queries from the Neo4j script (inspection RETURNs) are not executed during import.
#   * BUG FIX (flagged): RFQ rejection took "LIMIT 2" over RFQ *lines*, so one RFQ could be rejected twice
#        (duplicate HAS_BUYER_RFQ_REJECTION / IS_SUPPLIER_REJECTED_RFQ_STATE edges). Now LIMIT counts whole RFQs.
#   * Recommendation Engine: MERGE (c1)-[:SIMILARITY]-(c2) is undirected; FalkorDB creates one edge per direction
#        for each pair. Written here explicitly as -> so both directions exist deterministically.
# ------------------------------------------------------------------------------------------------------------------ #
set -euo pipefail

FALKOR_HOST="${FALKOR_HOST:-localhost}"
FALKOR_PORT="${FALKOR_PORT:-6379}"
FALKOR_USER="${FALKOR_USER:-}"
FALKOR_PASSWORD="${FALKOR_PASSWORD:-}"
FALKOR_TLS="${FALKOR_TLS:-0}"
GRAPH="${GRAPH:-northwind}"
REDIS_CLI="${REDIS_CLI:-redis-cli}"
QUERY_TIMEOUT_MS="${QUERY_TIMEOUT_MS:-0}"
CSV_BASE="${CSV_BASE:-https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWindPLUS/Import}"

CLI=("$REDIS_CLI" -h "$FALKOR_HOST" -p "$FALKOR_PORT" --no-raw)
[[ -n "$FALKOR_USER" ]] && CLI+=(--user "$FALKOR_USER")
[[ "$FALKOR_TLS" == "1" ]] && CLI+=(--tls)
[[ -n "$FALKOR_PASSWORD" ]] && export REDISCLI_AUTH="$FALKOR_PASSWORD"

STEP=0
# run "<label>"  <<'CYPHER' ... CYPHER    -- executes one write/read query, stops the script on any error
run() {
  local label="$1" query out stats
  query="$(cat)"
  query="${query//@CSV@/$CSV_BASE}"
  STEP=$((STEP + 1))
  local args=(GRAPH.QUERY "$GRAPH" "$query")
  [[ "$QUERY_TIMEOUT_MS" != "0" ]] && args+=(TIMEOUT "$QUERY_TIMEOUT_MS")
  if ! out="$("${CLI[@]}" "${args[@]}" 2>&1)" || grep -q '^(error)' <<<"$out"; then
    echo "[$STEP] $label -- FAILED"; echo "$out"; exit 1
  fi
  stats="$(grep -oE '(Labels added|Nodes created|Nodes deleted|Relationships created|Relationships deleted|Properties set|Properties removed|Indices created): [0-9]+' <<<"$out" | paste -sd ',' - | sed 's/,/, /g' || true)"
  printf '[%02d] %-62s %s\n' "$STEP" "$label" "${stats:-ok}"
}

# show "<label>" <<'CYPHER' -- read-only query, prints the result as a | separated table
FMT_AWK='
function val(s) { sub(/^\(integer\) |^\(double\) /, "", s); if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2); return s }
/^\(error\)/ { print; next }
/^[0-9]+\) / { sec = $1 + 0 }
{ line = $0; if ($0 ~ /^[0-9]+\) /) sub(/^[0-9]+\) +/, "", line); else sub(/^ +/, "", line) }
sec == 1 { sub(/^ *[0-9]+\) +/, "", line); hdr = hdr (hdr == "" ? "" : " | ") val(line); next }
sec == 2 && !printed { print hdr; u = hdr; gsub(/[^|]/, "-", u); print u; printed = 1 }
sec == 2 && line == "(empty array)" { print "(no rows)"; next }
sec == 2 && line ~ /^ *[0-9]+\) +[0-9]+\) / { if (row != "") print row; sub(/^ *[0-9]+\) +[0-9]+\) +/, "", line); row = val(line); next }
sec == 2 { sub(/^ *[0-9]+\) +/, "", line); row = row " | " val(line) }
END { if (row != "") print row }'
show() {
  local label="$1" query
  query="$(cat)"
  echo; echo "=== $label ==="
  "${CLI[@]}" GRAPH.RO_QUERY "$GRAPH" "$query" 2>&1 | awk "$FMT_AWK" | while IFS= read -r l; do printf '%b\n' "$l"; done
}

# ================================================================================================================== #
do_import() {
  echo "Importing NorthWind PLUS into FalkorDB graph '$GRAPH' at $FALKOR_HOST:$FALKOR_PORT"
  echo "CSV source: $CSV_BASE"

  # -- Clear the graph (equivalent of MATCH (n) DETACH DELETE n) --
  "${CLI[@]}" GRAPH.DELETE "$GRAPH" >/dev/null 2>&1 || true
  echo "[00] Graph '$GRAPH' deleted (if it existed)"

  # -- Indexes (added for FalkorDB; MERGE/MATCH by these keys would otherwise scan) --
  for spec in "ProductCategorY:CategoryID" "Supplier:SupplierID" "Product:ProductID" "Customer:CustomerID" \
              "Employee:EmployeeID" "RolE:Title" "Territory:TerritoryID" "Regions:RegionID" "Shipper:ShipperID" \
              "OrderTmp:OrderID" "Order:OrderID" "Address:Address" "PurchaseOrder:PONumber" "RFQ:RFQNumber"; do
    run "Index :${spec%%:*}(${spec#*:})" <<CYPHER
CREATE INDEX FOR (n:${spec%%:*}) ON (n.${spec#*:})
CYPHER
  done

  #-- Loading Data from CSV files --#
  run "Load Product Categories" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/categories.csv" AS row
MERGE (n:ProductCategorY {CategoryID:row.CategoryID, CategoryName:row.CategoryName, Description:row.Description})
CYPHER

  run "Create CategorieS superset" <<'CYPHER'
CREATE (:CategorieS {Name: "CategorieS"})
CYPHER
  run "Create ProductStatusDiscontinueD collection" <<'CYPHER'
CREATE (:ProductStatusDiscontinueD {Status: "Discontinued"})
CYPHER
  run "Create ProductStatusAvailablE collection" <<'CYPHER'
CREATE (:ProductStatusAvailablE {Status: "Available"})
CYPHER

  run "Load Suppliers" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/suppliers.csv" AS row
MERGE (n:Supplier {SupplierID:row.SupplierID, CompanyName:row.CompanyName, ContactName:row.ContactName, ContactTitle:row.ContactTitle, Address:row.Address, City:row.City, Region:row.Region, PostalCode:row.PostalCode, Country:row.Country, Phone:row.Phone, Fax:row.Fax, HomePage:"https://www." + replace(replace(replace(row.CompanyName," ",""),"'",""),".","") + ".com"})
CYPHER

  run "Normalize Supplier Address / Contact" <<'CYPHER'
MATCH (n:Supplier)
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Contact {ContactName:n.ContactName, ContactTitle:n.ContactTitle, Phone:n.Phone, Fax:n.Fax, Email: replace(n.ContactName, " ", ".") +"@" + replace(replace(replace(n.CompanyName," ",""),"'",""),".","") + ".com"})
CREATE (n)-[:HAS_SUPPLIER_ADDRESS]->(a)
CREATE (n)-[:HAS_SUPPLIER_CONTACT]->(c)
CYPHER

  # Isotope Nodes: InventoryLevel.UnitsInStock, OrderLevel.UnitsOnOrder, ReorderLevel.StockThreshold
  run "Load Products + Inventory/Reorder/Order levels" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/products.csv" AS row
WITH row, localdatetime() AS now
MERGE (n:Product {ProductID:row.ProductID, ProductName:row.ProductName, UnitPrice:toFloat(row.UnitPrice), ReorderLevel:toInteger(row.ReorderLevel), QuantityPerUnit:row.QuantityPerUnit, Discontinued:toInteger(row.Discontinued), SupplierID:row.SupplierID})
CREATE (i:InventoryLevel {UnitsInStock:toInteger(row.UnitsInStock), LastUpdate: now})
CREATE (reorder:ReorderLevel {StockThreshold:toInteger(row.UnitsInStock) + 10, LastUpdate: now})
CREATE (n)-[:HAS_REORDER_LEVEL]->(reorder)
CREATE (n)-[:HAS_SUPPLY_ORDER]->(onorder:OrderLevel {UnitsOnOrder: 0, LastUpdate: now})
CREATE (n)-[:HAS_INVENTORY_LEVEL]->(i)
WITH n, row
MATCH (c:ProductCategorY) WHERE c.CategoryID = row.CategoryID
MERGE (c)-[:IS_PRODUCT_CATEGORY_OF]->(n)
CYPHER

  run "Connect Discontinued products" <<'CYPHER'
MATCH (d:ProductStatusDiscontinueD {Status: "Discontinued"}), (n:Product)
WHERE n.Discontinued = 1
MERGE (d)-[:IS_DISCONTINUED_PRODUCT]->(n)
CYPHER
  run "Connect Available products" <<'CYPHER'
MATCH (a:ProductStatusAvailablE {Status: "Available"}), (n:Product)
WHERE n.Discontinued = 0
MERGE (a)-[:IS_AVAILABLE_PRODUCT]->(n)
CYPHER
  run "Remove normalized Product properties" <<'CYPHER'
MATCH (n:Product) REMOVE n.Discontinued, n.ReorderLevel
CYPHER
  run "Connect Product <-> Supplier" <<'CYPHER'
MATCH (s:Supplier), (p:Product)
WHERE s.SupplierID = p.SupplierID
MERGE (p)-[:HAS_PRODUCT_SUPPLIER]->(s)
MERGE (s)-[:SUPPLIES]->(p)
CYPHER
  run "Remove Product.SupplierID" <<'CYPHER'
MATCH (n:Product) REMOVE n.SupplierID
CYPHER
  run "Remove normalized Supplier properties" <<'CYPHER'
MATCH (s:Supplier)
REMOVE s.ContactName, s.ContactTitle, s.Address, s.City, s.Region, s.PostalCode, s.Country, s.Phone, s.Fax
CYPHER
  run "Connect CategorieS -> ProductCategorY" <<'CYPHER'
MATCH (k:CategorieS {Name: "CategorieS"}), (c:ProductCategorY)
MERGE (k)-[:HAS_CATEGORY]->(c)
CYPHER

  run "Load Customers" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/customers.csv" AS row
MERGE (n:Customer {CustomerID:row.CustomerID})
SET n += row
CYPHER
  run "Create CustomerS superset" <<'CYPHER'
CREATE (c:CustomerS {Name:"CustomerS"})
CYPHER
  run "Connect CustomerS -> Customer" <<'CYPHER'
MATCH (c:CustomerS {Name:"CustomerS"}), (o:Customer)
CREATE (c)-[:IS_CUSTOMER]->(o)
CYPHER
  run "Normalize Customer Address / Contact" <<'CYPHER'
MATCH (n:Customer)
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Contact {ContactName:n.ContactName, ContactTitle:n.ContactTitle, Phone:n.Phone, Fax:n.Fax, Email: replace(n.ContactName, " ", ".") +"@" + replace(replace(replace(n.CompanyName," ",""),"'",""),".","") + ".com"})
CREATE (n)-[:HAS_CUSTOMER_ADDRESS]->(a)
CREATE (n)-[:HAS_CUSTOMER_CONTACT]->(c)
CYPHER
  run "Remove normalized Customer properties" <<'CYPHER'
MATCH (n:Customer)
REMOVE n.Address, n.City, n.Region, n.PostalCode, n.Country, n.ContactName, n.ContactTitle, n.Phone, n.Fax
CYPHER

  run "Create RoleS superset" <<'CYPHER'
CREATE (:RoleS {Name: "RoleS"})
CYPHER
  run "Load Employee Roles" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/employees.csv" AS row
MERGE (l:RolE {Title:row.Title})
WITH l
MATCH (r:RoleS)
MERGE (r)-[:HAS_ROLE_TITLE]->(l)
CYPHER
  run "Load Employees + Person / Address / Notes" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/employees.csv" AS row
WITH row, localdatetime() AS now
MERGE (n:Employee {EmployeeID:row.EmployeeID, Email: row.FirstName + "." + row.LastName + "@northwind.com"})
SET n += row
WITH n, row, now
MATCH (l:RolE {Title: n.Title})
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Person {FirstName:row.FirstName, LastName: row.LastName, TitleOfCourtesy: row.TitleOfCourtesy, BirthDate: row.BirthDate, PersonalPhone:n.HomePhone, PersonalEmail: row.FirstName + "." + row.LastName + "@outlook.com"})
CREATE (o:Notes {Notes:n.Notes})
MERGE (l)-[:IS_ACTIVE_ROLE {StartDate: now}]->(n)
CREATE (n)-[:HAS_PERSON]->(c)
CREATE (c)-[:HAS_HOME_ADDRESS]->(a)
CREATE (n)-[:HAS_EMPLOYEE_NOTES]->(o)
CYPHER
  run "Employee REPORTS_TO" <<'CYPHER'
MATCH (n:Employee)
WHERE n.ReportsTo IS NOT NULL
MATCH (m:Employee)
WHERE n.ReportsTo = m.EmployeeID
MERGE (n)-[:REPORTS_TO]->(m)
CYPHER
  run "Remove normalized Employee properties" <<'CYPHER'
MATCH (n:Employee)
REMOVE n.FirstName, n.LastName, n.TitleOfCourtesy, n.BirthDate, n.Address, n.City, n.Region, n.PostalCode, n.Country, n.HomePhone, n.Fax, n.Notes, n.Photo, n.ReportsTo, n.Title
CYPHER

  run "Load Territories" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/territories.csv" AS row
MERGE (n:Territory {TerritoryID:row.TerritoryID})
SET n += row
CYPHER
  run "Load Regions" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/regions.csv" AS row
MERGE (n:Regions {RegionID:row.RegionID})
SET n += row
CYPHER
  run "Load Employee Territories" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/employee-territories.csv" AS row
MATCH (e:Employee {EmployeeID: row.EmployeeID}), (t:Territory {TerritoryID: row.TerritoryID})
MERGE (t)-[:HAS_EMPLOYEE]->(e)
CYPHER
  run "Connect Regions -> Territory" <<'CYPHER'
MATCH (t:Territory), (r:Regions)
WHERE t.RegionID = r.RegionID
MERGE (r)-[:HAS_TERRITORY]->(t)
CYPHER
  run "Remove Territory.RegionID" <<'CYPHER'
MATCH (t:Territory) REMOVE t.RegionID
CYPHER

  run "Load Shippers" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/shippers.csv" AS row
MERGE (n:Shipper {ShipperID:row.ShipperID, CompanyName:row.CompanyName, Phone:row.Phone})
CYPHER
  run "Create ShipperS superset" <<'CYPHER'
CREATE (c:ShipperS {Name:"ShipperS"})
CYPHER
  run "Connect ShipperS -> Shipper" <<'CYPHER'
MATCH (c:ShipperS {Name:"ShipperS"}), (o:Shipper)
CREATE (c)-[:IS_SHIPPER]->(o)
CYPHER

  run "Load Orders into OrderTmp" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/orders.csv" AS row
MERGE (n:OrderTmp {OrderID:row.OrderID})
SET n += row
CYPHER
  # ShippedDate = 9999-12-31 in the fixed CSV marks Orders not yet shipped (Open).
  run "Normalize Order dates to localdatetime" <<'CYPHER'
MATCH (o:OrderTmp)
SET o.OrderDate    = localdatetime(left(o.OrderDate, 10)+"T"+right(o.OrderDate, 12)),
    o.RequiredDate = localdatetime(left(o.RequiredDate, 10)+"T"+right(o.RequiredDate, 12)),
    o.ShippedDate  = localdatetime(left(o.ShippedDate, 10)+"T"+right(o.ShippedDate, 12)),
    o.Freight      = toFloat(o.Freight)
CYPHER
  run "Copy OrderTmp -> Order" <<'CYPHER'
MATCH (n:OrderTmp)
CREATE (m:Order)
SET m = properties(n)
CYPHER
  run "Delete OrderTmp" <<'CYPHER'
MATCH (n:OrderTmp) DETACH DELETE n
CYPHER
  run "Connect Order -> Customer" <<'CYPHER'
MATCH (c:Customer),(o:Order)
WHERE c.CustomerID = o.CustomerID
MERGE (o)-[:HAS_ORDER_CUSTOMER]->(c)
CYPHER
  # Faithful port. NOTE: as in the Neo4j original, the second (NOT EXISTS -> CREATE Address) branch can never fire:
  # rows without a matching Address are dropped by the mandatory MATCH, and rows that matched were just MERGEd.
  run "Create ShipInfo + Shipper + shipment Address" <<'CYPHER'
MATCH (n:Order), (s:Shipper)
WHERE n.ShipVia = s.ShipperID
CREATE (n)-[:HAS_SHIPMENT_INFO]->(i:ShipInfo {ShippmentID:"SH-"+randomUUID(), ShipName:n.ShipName, ShippedDate:n.ShippedDate, Freight:n.Freight })
CREATE (i)-[:HAS_SHIPPER]->(s)
WITH n, i
MATCH (a:Address) WHERE a.Address = n.ShipAddress AND a.City = n.ShipCity AND a.Region = n.ShipRegion AND a.PostalCode = n.ShipPostalCode AND a.Country = n.ShipCountry
MERGE (i)-[:HAS_SHIPMENT_ADDRESS]->(a)
WITH n, i
WHERE NOT (i)-[:HAS_SHIPMENT_ADDRESS]->(:Address {Address:n.ShipAddress, City:n.ShipCity, Region:n.ShipRegion, PostalCode:n.ShipPostalCode, Country:n.ShipCountry})
CREATE (a:Address {Address:n.ShipAddress, City:n.ShipCity, Region:n.ShipRegion, PostalCode:n.ShipPostalCode, Country:n.ShipCountry})
CREATE (i)-[:HAS_SHIPMENT_ADDRESS]->(a)
CYPHER
  run "Connect Order -> Employee (SOLD_BY)" <<'CYPHER'
MATCH (e:Employee), (o:Order)
WHERE e.EmployeeID = o.EmployeeID
MERGE (o)-[:SOLD_BY]->(e)
CYPHER
  run "Remove normalized Order properties" <<'CYPHER'
MATCH (n:Order)
REMOVE n.CustomerID, n.ShipVia, n.ShipName, n.ShipAddress, n.ShipCity, n.ShipRegion, n.ShipPostalCode, n.ShipCountry, n.Freight, n.ShippedDate, n.EmployeeID
CYPHER
  run "Load Order Details (HAS_ORDER_PRODUCT)" <<'CYPHER'
LOAD CSV WITH HEADERS FROM "@CSV@/order-details.csv" AS row
MATCH (p:Product {ProductID: row.ProductID}), (o:Order {OrderID: row.OrderID})
MERGE (o)-[details:HAS_ORDER_PRODUCT]->(p)
SET details.Quantity = toInteger(row.Quantity), details.UnitPrice = toFloat(row.UnitPrice), details.Discount = toFloat(row.Discount)
CYPHER
  run "Create OrderS superset + Order status collections" <<'CYPHER'
CREATE (o:OrderS {Name: "OrderS"})-[:HAS_OPEN_ORDER_STATUS]->(:OrderStatusOpeN {Status: "Open"}),
       (o)-[:HAS_FULFILLED_ORDER_STATUS]->(:OrderStatusFulfilleD {Status: "Fulfilled"}),
       (o)-[:HAS_CANCELED_ORDER_STATUS]->(:OrderStatusCanceleD {Status: "Canceled"})
CYPHER
  run "Connect Fulfilled Orders" <<'CYPHER'
MATCH (f:OrderStatusFulfilleD {Status: "Fulfilled"}), (n:Order)-[:HAS_SHIPMENT_INFO]->(s:ShipInfo)
WHERE s.ShippedDate <> localdatetime("9999-12-31T00:00:00")
CREATE (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: localdatetime()}]->(n)
CYPHER
  run "Connect Open Orders" <<'CYPHER'
MATCH (o:OrderStatusOpeN {Status: "Open"}), (n:Order)-[:HAS_SHIPMENT_INFO]->(s:ShipInfo)
WHERE s.ShippedDate = localdatetime("9999-12-31T00:00:00")
CREATE (o)-[:IS_OPEN_ORDER_STATE]->(n)
CYPHER
  run "Restock +150 units (pre-simulation)" <<'CYPHER'
MATCH (p:Product)-[:HAS_INVENTORY_LEVEL]->(i) SET i.UnitsInStock = i.UnitsInStock+150
CYPHER

  #------------------------------------------- PLUS -------------------------------------------#
  run "Create EmployeeDirectorY" <<'CYPHER'
CREATE (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"})
CYPHER
  run "Connect EmployeeDirectorY -> Employee" <<'CYPHER'
MATCH (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (e:Employee)
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:localdatetime()}]->(e)
CYPHER
  run "Create Procurement Roles" <<'CYPHER'
MATCH (r:RoleS {Name:"RoleS"})
CREATE (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Procurement Assistant", Description:"Procurement Assistant / Coordinator", Rules:"Submits purchase orders based on inventory level and demand, tracks deliveries, and coordinates day-to-day tactical tasks"}),
       (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"SupplierApprover", Description:"Supplier Approver", Rules:"Approves Suppliers in the System"}),
       (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Level1Approver", ApprovalBase:0.00, ApprovalLimit:5000.00, Description:"Level 1 Approver", Rules:"Approves PO with a Budget < 5000.00"}),
       (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Level2Approver", ApprovalBase:5000.01, ApprovalLimit:12500.00, Description:"Level 2 Approver", Rules:"Approves PO with a Budget > 5000.01 and < 12500.00"}),
       (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Level3Approver", ApprovalBase:12500.01,ApprovalLimit:500000.00, Description:"Level 3 Approver", Rules:"Approves PO with a Budget > 12500.01 and < 500000.00"}),
       (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Buyer" , Description:"Buyer / Purchasing Officer", Rules:"Manages specific product categories, handles routine vendor discovery, and executes purchase transactions."}),
       (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"WarehouseClerk", Description:"Warehouse Clerk", Rules:"Receives and inspects incoming shipments, updates inventory records, and ensures proper storage of goods."} ),
       (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Finance", Description:"Finance Officer", Rules:"Manages financial transactions, processes payments, and maintains financial records."} )
CYPHER
  run "Create Supplier States" <<'CYPHER'
CREATE (v:SupplierS {Name:"SupplierS"})-[:HAS_SUPPLIER_PENDING_STATE]->(:PendingSupplierS {Name:"PendingSupplierS"}),
       (v)-[:HAS_SUPPLIER_APPROVED_STATE]->(:ApprovedSupplierS {Name:"ApprovedSupplierS"}),
       (v)-[:HAS_SUPPLIER_REJECTED_STATE]->(:RejectedSupplierS {Name:"RejectedSupplierS"})
CYPHER
  run "Existing Suppliers -> ApprovedSupplierS" <<'CYPHER'
MATCH (a:ApprovedSupplierS {Name:"ApprovedSupplierS"}), (s:Supplier)
CREATE (a)-[:IS_SUPPLIER_APPROVED_STATE]->(s)
CYPHER

  run "Employees: Supplier Approvers (2)" <<'CYPHER'
MATCH (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (va:RolE {Title:"SupplierApprover"})
WITH ed, va, localdatetime() AS now
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:now}]->(e1:Employee {Email:"Adam.Smith@northwind.com", EmployeeID: "10", Extension: "1234" } )-[:HAS_PERSON]->(:Person {FirstName:"Adam", LastName:"Smith", BirthDate:"1989-07-02 00:00:00.000", PersonalPhone:"9551062551", PersonalEmail:"Adam@email.com"}), (e1)<-[:IS_ACTIVE_ROLE {StartDate:now}]-(va),
        (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:now}]->(e2:Employee {Email:"Mary.Jane@northwind.com", EmployeeID: "11", Extension: "1235" } )-[:HAS_PERSON]->(:Person {FirstName:"Mary", LastName: "Jane", BirthDate:"1995-09-10 00:00:00.000",  PersonalPhone:"909870092", PersonalEmail:"Mary@email.com" }), (e2)<-[:IS_ACTIVE_ROLE {StartDate:now}]-(va)
CYPHER
  # One CREATE per employee. Args: Role EmployeeID Email Extension FirstName LastName BirthDate PersonalPhone PersonalEmail
  add_employee() {
    run "Employee $2 $5 $6 ($1)" <<CYPHER
MATCH (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (ro:RolE {Title:"$1"})
WITH ed, ro, localdatetime() AS now
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:now}]->(e:Employee {Email:"$3", EmployeeID: "$2", Extension: "$4" })-[:HAS_PERSON]->(:Person {FirstName:"$5", LastName: "$6", BirthDate:"$7", PersonalPhone:"$8", PersonalEmail:"$9"}), (e)<-[:IS_ACTIVE_ROLE {StartDate:now}]-(ro)
CYPHER
  }
  add_employee Level1Approver        12 Gloria.Gaynor@northwind.com   1236 Gloria    Gaynor   "1983-09-7 00:00:00.000"  559831373  Gloria@email.com
  add_employee Level1Approver        21 Gabriel.Garcia@northwind.com  1246 Gabriel   Garcia   "1997-03-6 00:00:00.000"  559931373  Gabriel@email.com
  add_employee Level2Approver        13 Sara.Vaughan@northwind.com    127  Sara      Vaughan  "1984-03-27 00:00:00.000" 4849810343 Sara@email.com
  add_employee Level2Approver        22 Steve.Martin@northwind.com    1247 Steve     Martin   "1984-03-27 00:00:00.000" 4849910343 Steve.Martin@email.com
  add_employee Level3Approver        14 Christine.McVie@northwind.com 1238 Christine McVie    "1973-07-12 00:00:00.000" 9998344731 Christine@email.com
  add_employee Level3Approver        23 Carmen.Miranda@northwind.com  1248 Carmen    Miranda  "1979-02-09 00:00:00.000" 8898344731 Carmen.Miranda@email.com
  add_employee Buyer                 15 Cloe.Bailey@northwind.com     1239 Cloe      Bailey   "1998-07-01 00:00:00.000" 998195044  Cloe@email.com
  add_employee "Procurement Assistant" 16 Albert.Camus@northwind.com  1240 Albert    Camus    "1993-11-07 00:00:00.000" 983435644  Albert@email.com
  add_employee "Procurement Assistant" 17 Bernard.Shaw@northwind.com  1241 Bernard   Shaw     "1983-07-26 00:00:00.000" 978535644  Bernard@email.com
  add_employee "Procurement Assistant" 18 Carlos.Santana@northwind.com 1242 Carlos   Santana  "1987-07-20 00:00:00.000" 97853474   Carlos@email.com
  add_employee WarehouseClerk        19 John.Doe@northwind.com        1243 John      Doe      "1990-07-20 00:00:00.000" 95644474   John@email.com
  add_employee WarehouseClerk        24 James.Ingram@northwind.com    1253 James     Ingram   "1980-07-20 00:00:00.000" 95656774   James.Ingram@email.com
  add_employee Finance               20 Jane.Doe@northwind.com        1244 Jane      Doe      "1985-03-15 00:00:00.000" 96755574   Jane@email.com
  run "SYSTEM user" <<'CYPHER'
MATCH (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"})
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:localdatetime()}]->(:Employee {Email:"system@northwind.com", EmployeeID: "00", Extension: "0000" })
CYPHER

  # 50 random Customer Orders with 1 to 11 products. LIMIT can't take an expression in FalkorDB, so the
  # products are shuffled, collected and sliced to a random length instead.
  run "50 random Customer Orders" <<'CYPHER'
UNWIND range(1, 50) AS i
CALL {
  WITH i
  MATCH (e:Employee)-[]-(:RolE {Title: "Sales Representative"}), (op:OrderStatusOpeN {Status: "Open"})
  WITH e, op ORDER BY rand() LIMIT 1
  MATCH (c:Customer)
  WITH e, c, op ORDER BY rand() LIMIT 1
  CREATE (o:Order {OrderID: "CO-"+left(randomUUID(),5)+right(randomUUID(),5), OrderDate:localdatetime(), RequiredDate:localdatetime()+duration("P7D")})<-[:IS_OPEN_ORDER_STATE]-(op)
  CREATE (o)-[:HAS_ORDER_CUSTOMER]->(c)
  CREATE (o)-[:SOLD_BY]->(e)
  WITH o
  MATCH (p:Product)-[]-(:ProductStatusAvailablE {Status: "Available"})
  WITH o, p ORDER BY rand()
  WITH o, collect(p) AS shuffled
  WITH o, shuffled[0..toInteger(round(rand()*10 + 1))] AS picked
  UNWIND picked AS p
  CREATE (o)-[:HAS_ORDER_PRODUCT {Quantity: toInteger(round(rand()*19)+1), UnitPrice:p.UnitPrice, Discount: rand()*0.07}]->(p)
}
CYPHER

  run "Create PO state collections (PoS)" <<'CYPHER'
CREATE (t:PoS {Name:"PoS"})-[:HAS_NEW_PO_STATE]->(:NewPoS {Name:"NewPoS"}),
       (t)-[:HAS_APPROVED_PO_STATE]->(:ApprovedPoS {Name:"ApprovedPoS"}),
       (t)-[:HAS_REJECTED_PO_STATE]->(:RejectedPoS {Name:"RejectedPoS"}),
       (t)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS {Name:"SubmittedPoS"}),
       (t)-[:HAS_CLOSED_PO_STATE]->(:ClosedPoS {Name:"ClosedPoS"})
CYPHER
  run "Create Supplier PO collections" <<'CYPHER'
MATCH (s:Supplier)
CREATE (s)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(:SupplierNewPoS {Name:"SupplierNewPoS"}),
       (s)-[:HAS_SUPPLIER_OPEN_POS]->(:SupplierOpenPoS {Name:"SupplierOpenPoS"}),
       (s)-[:HAS_SUPPLIER_CLOSED_POS]->(:SupplierClosedPoS {Name:"SupplierClosedPoS"})
CYPHER

  #-------------------------------- PO Creation --------------------------------#
  run "PO Creation (low stock, incl. open Customer Orders)" <<'CYPHER'
MATCH (pa:RolE {Title: "Procurement Assistant"})-[:IS_ACTIVE_ROLE]->(e:Employee), (n:NewPoS {Name:"NewPoS"})
WITH n, e ORDER BY rand() LIMIT 1
MATCH (s:Supplier)-[:SUPPLIES]->(p:Product)<-[:IS_AVAILABLE_PRODUCT]-(a:ProductStatusAvailablE),
  (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
CALL { WITH p MATCH ()-[:IS_NEW_PO_STATE | IS_APPROVED_PO_STATE | IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p) RETURN SUM(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty }
CALL { WITH p MATCH (p)<-[op:HAS_ORDER_PRODUCT]-(:Order)<-[:IS_OPEN_ORDER_STATE]-() RETURN SUM(coalesce(op.Quantity, 0)) AS OpenOrderQty }
WITH e, n, s, p, r, i, AlreadyPendingQty, OpenOrderQty
WHERE i.UnitsInStock + AlreadyPendingQty - OpenOrderQty - (r.StockThreshold * 0.5) <= r.StockThreshold
WITH e, n, s, COLLECT({
    Product: p,
    qty: (r.StockThreshold) - (i.UnitsInStock + AlreadyPendingQty - OpenOrderQty) + (r.StockThreshold * 2) + 1
}) AS orderItems
CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {PONumber: "PO-" + left(randomUUID(), 5) + right(randomUUID(), 5), PODate: localdatetime()})
CREATE (s)<-[:PO_FOR_SUPPLIER]-(po)
CREATE (po)-[:PO_CREATED_BY]->(e)
WITH po, orderItems, s
UNWIND orderItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7}]->(p)
RETURN DISTINCT po.PONumber AS PONumber, s.SupplierID AS SupplierID, size(orderItems) AS ItemCount
CYPHER

  #-------------------------------- PO Vetting --------------------------------#
  # Each "ORDER BY .. LIMIT n WHERE .." from the Neo4j script is split into LIMIT-then-WHERE (see header).
  run "L1 rejects 2 POs" <<'CYPHER'
MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level1Approver"}), (a:RejectedPoS {Name:"RejectedPoS"})
WITH a, ro, l1 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WITH a, ro, l1, np, p, SUM((poi.POqt * (i.UnitPrice*poi.POPriceDiscount))) AS POCost ORDER BY id(p) LIMIT 2
WITH a, ro, l1, np, p, POCost WHERE POCost > ro.ApprovalBase
CREATE (p)-[:HAS_L1_PO_REJECTION {Date:localdatetime(), Comment:"This PO is rejected by L1 due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1),
       (a)-[:IS_REJECTED_PO_STATE {Date:localdatetime()}]->(p)
DELETE np
CYPHER
  run "L1 approves POs within limit (up to 20)" <<'CYPHER'
MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level1Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
WITH a, ro, l1 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WITH a, ro, l1, np, p, SUM((poi.POqt * (i.UnitPrice*poi.POPriceDiscount))) AS POCost ORDER BY id(p) LIMIT 20
WITH a, ro, l1, np, p, POCost WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L1_PO_APPROVAL {Date:localdatetime(), Comment:"This PO is approved by L1 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1),
       (a)-[:IS_APPROVED_PO_STATE {Date:localdatetime()}]->(p)
DELETE np
CYPHER
  run "L1 vets POs above its limit" <<'CYPHER'
MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level1Approver"})
WITH ro, l1 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WITH ro, l1, np, p, SUM((poi.POqt * (i.UnitPrice*poi.POPriceDiscount))) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L1_PO_APPROVAL {Date:localdatetime(), Comment:"This PO is approved by L1 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1)
CYPHER
  run "L2 approves POs within limit" <<'CYPHER'
MATCH (l2:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level2Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
WITH a, ro, l2 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier), (p)-[:HAS_L1_PO_APPROVAL]-()
WITH a, ro, l2, np, p, SUM((poi.POqt * (i.UnitPrice*poi.POPriceDiscount))) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_APPROVAL {Date:localdatetime(), Comment:"This PO is approved by L2 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l2),
       (a)-[:IS_APPROVED_PO_STATE {Date:localdatetime()}]->(p)
DELETE np
CYPHER
  run "L2 rejects 1 PO above its limit" <<'CYPHER'
MATCH (l2:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level2Approver"}), (a:RejectedPoS {Name:"RejectedPoS"})
WITH a, ro, l2 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier), (p)-[:HAS_L1_PO_APPROVAL]-()
WITH a, ro, l2, np, p, SUM((poi.POqt * (i.UnitPrice*poi.POPriceDiscount))) AS POCost ORDER BY id(p) LIMIT 1
WITH a, ro, l2, np, p, POCost WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_REJECTION {Date:localdatetime(), Comment:"This PO is rejected by L2 due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l2),
       (a)-[:IS_REJECTED_PO_STATE {Date:localdatetime()}]->(p)
DELETE np
CYPHER
  run "L2 vets POs above its limit" <<'CYPHER'
MATCH (l2:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level2Approver"})
WITH ro, l2 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier), (p)-[:HAS_L1_PO_APPROVAL]-()
WITH ro, l2, np, p, SUM((poi.POqt * (i.UnitPrice*poi.POPriceDiscount))) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_APPROVAL {Date:localdatetime(), Comment:"This PO is approved by L2 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l2)
CYPHER
  run "L3 rejects 1 PO" <<'CYPHER'
MATCH (l3:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level3Approver"}), (a:RejectedPoS {Name:"RejectedPoS"})
WITH a, ro, l3 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier), (p)-[:HAS_L2_PO_APPROVAL]-()
WITH a, ro, l3, np, p, SUM((poi.POqt * (i.UnitPrice*poi.POPriceDiscount))) AS POCost ORDER BY id(p) LIMIT 1
WITH a, ro, l3, np, p, POCost WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L3_PO_REJECTION {Date:localdatetime(), Comment:"This PO is rejected by L3 due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l3),
       (a)-[:IS_REJECTED_PO_STATE {Date:localdatetime()}]->(p)
DELETE np
CYPHER
  run "L3 approves 2 POs" <<'CYPHER'
MATCH (l3:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level3Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
WITH a, ro, l3 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[poi:HAS_PO_ITEM]->(i:Product)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier), (p)-[:HAS_L2_PO_APPROVAL]-()
WITH a, ro, l3, np, p, SUM((poi.POqt * (i.UnitPrice*poi.POPriceDiscount))) AS POCost ORDER BY id(p) LIMIT 2
WITH a, ro, l3, np, p, POCost WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L3_PO_APPROVAL {Date:localdatetime(), Comment:"This PO is approved by L3 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l3),
       (a)-[:IS_APPROVED_PO_STATE {Date:localdatetime()}]->(p)
DELETE np
CYPHER

  #-------------------------------- PO Resubmission --------------------------------#
  run "PO Resubmission (1 rejected PO)" <<'CYPHER'
MATCH (re:RejectedPoS)-[:IS_REJECTED_PO_STATE]->(rpo:PurchaseOrder)-[:PO_CREATED_BY]->(e:Employee),
      (rpo)-[:PO_FOR_SUPPLIER]->(s:Supplier),
      (n:NewPoS {Name:"NewPoS"})
WHERE NOT ()-[:HAS_PREVIOUS_PO]->(rpo)
WITH n, rpo, e, s ORDER BY rand() LIMIT 1
MATCH (rpo)-[:HAS_PO_ITEM]->(p)<-[:SUPPLIES]-(s),
      (p)<-[:IS_AVAILABLE_PRODUCT]-(:ProductStatusAvailablE),
      (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
CALL { WITH p MATCH ()-[:IS_NEW_PO_STATE | IS_APPROVED_PO_STATE | IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p) RETURN SUM(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty }
CALL { WITH p MATCH (p)<-[op:HAS_ORDER_PRODUCT]-(:Order)<-[:IS_OPEN_ORDER_STATE]-() RETURN SUM(coalesce(op.Quantity, 0)) AS OpenOrderQty }
WITH rpo, e, n, s, p, r, i, AlreadyPendingQty, OpenOrderQty
WHERE i.UnitsInStock + AlreadyPendingQty - OpenOrderQty - (r.StockThreshold * 0.5) <= r.StockThreshold
WITH rpo, e, n, s, COLLECT({
     Product: p,
     qty: (r.StockThreshold) - (i.UnitsInStock + AlreadyPendingQty - OpenOrderQty) + (r.StockThreshold / 2)
}) AS orderItems
WHERE size(orderItems) > 0
CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {PONumber: "PO-" + left(randomUUID(), 5) + right(randomUUID(), 5), PODate: localdatetime()})
CREATE (s)<-[:PO_FOR_SUPPLIER]-(po)
CREATE (po)-[:PO_CREATED_BY]->(e)
CREATE (po)-[:HAS_PREVIOUS_PO {Resubmission_Justification: "Reason for resubmission. What changed. What was missing or not accurate in the previous one. Comments, etc. "}]->(rpo)
WITH po, orderItems, rpo
UNWIND orderItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7}]->(p)
RETURN DISTINCT po.PONumber AS PONumber, rpo.PONumber AS ResubmittedFrom
CYPHER

  #-------------------------------- PO Submission (Buyer) --------------------------------#
  run "Buyer submits up to 10 Approved POs to Suppliers" <<'CYPHER'
MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Buyer"}), (su:SubmittedPoS {Name:"SubmittedPoS"})
WITH su, bu ORDER BY rand() LIMIT 1
MATCH (a:ApprovedPoS {Name:"ApprovedPoS"})-[ap]->(po:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(s:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp)
WITH ap, s, bu, su, po, snp ORDER BY id(po) LIMIT 10
CREATE (po)-[:HAS_BUYER_PO_APPROVAL {Date:localdatetime(), Comment:"This PO is approved by Buyer due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(bu),
       (su)-[:IS_SUBMITTED_PO_STATE {Date:localdatetime()}]->(po),
       (snp)-[:IS_SUPPLIER_NEW_PO_STATE {Date:localdatetime()}]->(po),
       (po)-[:HAS_SUPPLIER_NEW_RFQ]->(:PoNewRFQ {Name:"PoNewRFQ"}),
       (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(:PoRejectedRFQ {Name:"PoRejectedRFQ"})
DELETE ap
CYPHER

  #-------------------------------- Supplier RFQ --------------------------------#
  SUPPLIER_RFQ=$(cat <<'CYPHER'
MATCH (su:Supplier)-[np:HAS_SUPPLIER_NEW_PENDING_POS]->()-[r]->(po)-[pq:HAS_PO_ITEM]-(p), (po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr), (su)-[:HAS_SUPPLIER_OPEN_POS]->(sop)
WITH su, r, po, snr, sop, COLLECT({
    Product: p,
    qty: pq.POqt,
    cost: p.UnitPrice * 0.7
}) AS rfqItems
CREATE (rfq:RFQ {
    RFQNumber: "RFQ-" + left(randomUUID(), 5) + right(randomUUID(), 5),
    RFQDate: localdatetime(),
    RFQComments: "Thanks for your order, we are able to supply the full PO product request at the discounted price negotiated on our master agreement"})-[:IS_RFQ_FOR_PO]->(po),
(rfq)-[:RFQ_FROM_SUPPLIER]->(su),
(snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq),
(sop)-[:IS_SUPPLIER_OPEN_PO_STATE {Date:localdatetime()}]->(po)
DELETE r
WITH rfq, rfqItems
UNWIND rfqItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (rfq)-[:HAS_RFQ_ITEM {RFQqt: item.qty, RFQcost: item.cost}]->(p)
CYPHER
)
  run "Suppliers submit RFQs for new POs" <<<"$SUPPLIER_RFQ"

  #-------------------------------- RFQ Vetting --------------------------------#
  # BUG FIX (flagged): the Neo4j query limited RFQ *lines* to 2, so the same RFQ could be rejected twice.
  # WITH DISTINCT .. LIMIT 2 now picks 2 whole RFQs that have at least one line within the PO budget.
  run "Buyer rejects 2 RFQs" <<'CYPHER'
MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Buyer"})
WITH bu ORDER BY rand() LIMIT 1
MATCH (su:SubmittedPoS)-[]->(po)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq)-[rfi:HAS_RFQ_ITEM]->(p)<-[poi:HAS_PO_ITEM]-(po), (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(prr)
WHERE poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost
WITH DISTINCT bu, prr, po, r, rfq
ORDER BY po.PONumber DESC LIMIT 2
CREATE (rfq)-[:HAS_BUYER_RFQ_REJECTION {Date:localdatetime(), Comment:"This RFQ is rejected by Buyer due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(bu),
       (prr)-[:IS_SUPPLIER_REJECTED_RFQ_STATE {Date:localdatetime()}]->(rfq)
DELETE r
CYPHER
  # Same statement as "Suppliers submit RFQs" (the Neo4j script repeats it; it only finds POs still in SupplierNewPoS).
  run "Suppliers submit RFQs (second pass)" <<<"$SUPPLIER_RFQ"

  run "Buyer approves 8 RFQs within PO budget (+UnitsOnOrder)" <<'CYPHER'
MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Buyer"})
WITH bu ORDER BY rand() LIMIT 1
MATCH (su:SubmittedPoS)-[]->(po)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po)
WHERE poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost
WITH bu, po, rfq, r, collect({poi: poi, rfi: rfi, p: p}) AS items
ORDER BY po.PONumber
LIMIT 8
WITH bu, po, rfq, r, items, localdatetime() AS now
UNWIND items AS item
WITH bu, po, rfq, r, now, item.poi AS poi, item.rfi AS rfi, item.p AS p
MATCH (inv)<-[:HAS_INVENTORY_LEVEL]-(p)-[:HAS_SUPPLY_ORDER]-(suo)
MERGE (rfq)-[:HAS_BUYER_RFQ_APPROVAL {Date:now, Comment:"This RFQ is approved by Buyer due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(bu)
MERGE (po)-[:HAS_APPROVED_RFQ {Date:now}]->(rfq)
SET   suo.UnitsOnOrder = suo.UnitsOnOrder + rfi.RFQqt
DELETE r
CYPHER

  #-------------------------------- RFQ Resubmission --------------------------------#
  # apoc.lock.nodes removed: FalkorDB executes write queries one at a time per graph.
  run "Supplier resubmits 1 rejected RFQ" <<'CYPHER'
MATCH (su:Supplier)<-[:RFQ_FROM_SUPPLIER]-(rrfq:RFQ)<-[:IS_SUPPLIER_REJECTED_RFQ_STATE]-(), (rrfq)-[:IS_RFQ_FOR_PO]-(po:PurchaseOrder)
WHERE NOT ()-[:HAS_PREVIOUS_RFQ]->(rrfq)
WITH su, rrfq, po ORDER BY rand() LIMIT 1
MATCH (p)<-[pq:HAS_PO_ITEM]-(po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr)
WITH rrfq, su, po, snr, COLLECT({
    Product: p,
    qty: pq.POqt,
    cost: p.UnitPrice * 0.65
}) AS rfqItems
CREATE (rfq:RFQ {
    RFQNumber: "RFQ-" + left(randomUUID(), 5) + right(randomUUID(), 5),
    RFQDate: localdatetime(),
    RFQComments: "Thanks for your order, we resubmitting our RFQ and hope weare able to supply the full PO product request at the discounted price negotiated on our master agreement"
})-[:IS_RFQ_FOR_PO]->(po),
(rfq)-[:RFQ_FROM_SUPPLIER]->(su),
(snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq),
(rfq)-[:HAS_PREVIOUS_RFQ {Justification: "This RFQ is a resubmission of the previous rejected RFQ. The Supplier has provided additional justification and/or updated pricing and/or updated product availability."}]->(rrfq)
WITH rfq, rfqItems, po
UNWIND rfqItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (rfq)-[:HAS_RFQ_ITEM {RFQqt: item.qty, RFQcost: item.cost}]->(p)
RETURN DISTINCT rfq.RFQNumber AS RFQNumber, po.PONumber AS PONumber
CYPHER

  #-------------------------------- Update the Stock Threshold --------------------------------#
  run "Recalculate StockThreshold (150% of avg monthly volume)" <<'CYPHER'
MATCH ()-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_REORDER_LEVEL]->(re)
MATCH (p)<-[oi:HAS_ORDER_PRODUCT]-(o:Order)
WITH p, re,
     sum(oi.Quantity) AS TotalQuantityOrdered,
     count(DISTINCT (toString(o.OrderDate.year) + "-" + toString(o.OrderDate.month))) AS MonthsWithOrders
SET re.StockThreshold = toInteger(round((toFloat(TotalQuantityOrdered) / MonthsWithOrders) * 1.5))
CYPHER

  run "PO Creation (after threshold update)" <<'CYPHER'
MATCH (pa:RolE {Title: "Procurement Assistant"})-[:IS_ACTIVE_ROLE]->(e:Employee), (n:NewPoS {Name:"NewPoS"})
WITH n, e ORDER BY rand() LIMIT 1
MATCH (s:Supplier)-[:SUPPLIES]->(p:Product)<-[:IS_AVAILABLE_PRODUCT]-(a:ProductStatusAvailablE),
  (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
CALL { WITH p MATCH ()-[:IS_NEW_PO_STATE | IS_APPROVED_PO_STATE | IS_SUBMITTED_PO_STATE]->(activePO:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p) RETURN SUM(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty }
WITH e, n, s, p, r, i, AlreadyPendingQty
WHERE i.UnitsInStock + AlreadyPendingQty - (r.StockThreshold * 0.5) <= r.StockThreshold
WITH e, n, s, COLLECT({
    Product: p,
    qty: (r.StockThreshold) - (i.UnitsInStock + AlreadyPendingQty) + (r.StockThreshold * 2)
}) AS orderItems
CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {PONumber: "PO-" + left(randomUUID(), 5) + right(randomUUID(), 5), PODate: localdatetime()})
CREATE (s)<-[:PO_FOR_SUPPLIER]-(po)
CREATE (po)-[:PO_CREATED_BY]->(e)
WITH po, orderItems, s
UNWIND orderItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7}]->(p)
RETURN DISTINCT po.PONumber AS PONumber, s.SupplierID AS SupplierID, size(orderItems) AS ItemCount
CYPHER

  #-------------------------------- Warehouse delivery & Inventory update --------------------------------#
  run "Warehouse receives 5 POs (+Stock, -OnOrder)" <<'CYPHER'
MATCH (wc:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"WarehouseClerk"})
WITH wc ORDER BY rand() LIMIT 1
MATCH (po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(rfq:RFQ)
WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
WITH wc, po, rfq ORDER BY po.PONumber LIMIT 5
WITH wc, po, rfq, localdatetime() AS now
MATCH (p)<-[poi:HAS_PO_ITEM]-(po)-[:HAS_APPROVED_RFQ]->(rfq)-[rfi:HAS_RFQ_ITEM]->(p)-[:HAS_INVENTORY_LEVEL]->(inv), (p)-[:HAS_SUPPLY_ORDER]->(suo)
WHERE poi.POqt = rfi.RFQqt
MERGE (po)-[:HAS_WAREHOUSE_DELIVERY {Date:now, Comment:"The products have been received as per PO at the Warehouse and the Inventory Levels have been updated accordingly."}]->(wc)
SET  inv.UnitsInStock = inv.UnitsInStock + rfi.RFQqt,
     suo.UnitsOnOrder = suo.UnitsOnOrder - rfi.RFQqt
CYPHER

  #-------------------------------- PO Payment & Closure --------------------------------#
  run "Finance pays & closes 4 POs" <<'CYPHER'
MATCH (f:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Finance"}),
(cpo)<-[:HAS_CLOSED_PO_STATE]-(:PoS)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS)-[r1]->(po:PurchaseOrder)-[:HAS_WAREHOUSE_DELIVERY]->(wc:Employee),
(po)<-[r2:IS_SUPPLIER_OPEN_PO_STATE]-()<-[]-(su:Supplier)-[:HAS_SUPPLIER_CLOSED_POS]->(scp)
WITH r1, r2, cpo, scp, f, po ORDER BY po.PONumber LIMIT 4
WITH r1, r2, cpo, scp, f, po, localdatetime() AS now
MERGE (po)-[:HAS_FINANCE_PAYMENT {Date:now, Comment:"The PO has been paid by Finance and the PO is now closed."}]->(f)
MERGE (cpo)-[:IS_CLOSED_PO_STATE {Date:now, Comment:"The PO has been paid by Finance and the PO is now closed."}]->(po)
MERGE (scp)-[:HAS_SUPPLIER_CLOSED_PO_STATE {Date:now, Comment:"The PO has been paid by Finance and the PO is now closed."}]->(po)
DELETE r1, r2
CYPHER

  #-------------------------------- Customer Order Fulfillment --------------------------------#
  run "Fulfill oldest fully-stocked Open Order" <<'CYPHER'
MATCH (wc:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title:"WarehouseClerk"}), (s:Shipper)<-[:HAS_SHIPPER]-(si:ShipInfo)
WITH wc, si, s ORDER BY rand() LIMIT 1
MATCH (op:OrderStatusOpeN {Status:"Open"})-[r:IS_OPEN_ORDER_STATE]->(o:Order)-[details:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
WITH wc, si, s, op, o, r,
     count(details)                                                        AS TotalLines,
     sum(CASE WHEN inv.UnitsInStock > details.Quantity THEN 1 ELSE 0 END) AS LinesWithStock
WHERE TotalLines = LinesWithStock
WITH wc, si, s, op, o, r
ORDER BY o.OrderDate
LIMIT 1
MATCH (o)-[details:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
WITH wc, si, s, op, o, r, collect({details: details, inv: inv}) AS lines
MATCH (a)<-[:HAS_CUSTOMER_ADDRESS]-(:Customer)<-[:HAS_ORDER_CUSTOMER]-(o)
MATCH (f:OrderStatusFulfilleD {Status:"Fulfilled"})
CREATE (i:ShipInfo {ShippmentID:"SH-"+randomUUID(), ShippedDate:localdatetime(), ShipName:si.ShipName, Freight:round(rand()*10000)/100.0}),
       (o)-[:HAS_SHIPMENT_INFO]->(i),
       (i)-[:HAS_SHIPPER]->(s),
       (i)-[:HAS_SHIPMENT_ADDRESS]->(a),
       (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: localdatetime()}]->(o),
       (o)-[:HAS_WAREHOUSE_FULFILLMENT {Date:localdatetime(), Comment:"Order picked, packed, and shipped by the Warehouse Clerk."}]->(wc)
DELETE r
WITH o, lines
UNWIND lines AS x
WITH o, x.inv AS inv, x.details AS d
SET inv.UnitsInStock = inv.UnitsInStock - d.Quantity,
    inv.LastUpdate = localdatetime()
RETURN DISTINCT o.OrderID AS OrderID
CYPHER

  echo "Import complete."
  show "Graph size" <<'CYPHER'
MATCH (n) WITH count(n) AS totalNodes
MATCH ()-[r]->() WITH totalNodes, count(r) AS totalEdges
RETURN totalNodes, totalEdges, "1:" + toString(round(100.0 * totalEdges / totalNodes) / 100.0) AS NodesToEdgesRatio
CYPHER
}

# ================================================================================================================== #
do_recommend() {
  run "Recommendation: RATED (purchase-frequency rating)" <<'CYPHER'
MATCH (c:Customer)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_PRODUCT]->(p:Product)
WITH c, count(p) AS Total
MATCH (c)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_PRODUCT]->(p:Product)
WITH c, Total, p, count(o)*1.0 AS Orders
MERGE (c)-[rated:RATED]->(p)
ON CREATE SET rated.Rating = Orders/Total
ON MATCH SET rated.Rating = Orders/Total
CYPHER
  # Cosine similarity. Aggregates are collected first (FalkorDB rejects COLLECT nested inside REDUCE/SQRT).
  # Written as a directed MERGE: FalkorDB creates an edge in each direction per pair either way.
  run "Recommendation: SIMILARITY (cosine)" <<'CYPHER'
MATCH (c1:Customer)-[r1:RATED]->(p:Product)<-[r2:RATED]-(c2:Customer)
WITH c1, c2, SUM(r1.Rating*r2.Rating) AS dot_product, COLLECT(r1.Rating) AS r1s, COLLECT(r2.Rating) AS r2s
WITH c1, c2, dot_product,
  SQRT( REDUCE(x=0.0, a IN r1s | x + a^2) ) as r1_length,
  SQRT( REDUCE(y=0.0, b IN r2s | y + b^2) ) as r2_length
MERGE (c1)-[s:SIMILARITY]->(c2)
SET s.Similarity = dot_product / (r1_length * r2_length)
CYPHER
  show "Top recommendations for ANTON" <<'CYPHER'
MATCH (me:Customer)-[:SIMILARITY]->(c:Customer)-[r:RATED]->(p:Product)
WHERE me.CustomerID = 'ANTON' AND NOT (me)-[:RATED*1..2]->(p)
WITH p, COLLECT(r.Rating)[0..1] as Ratings, collect(c.CompanyName)[0..1] as Customers
WITH p, Customers, round(100000 * REDUCE(s=0, i in Ratings | s+i) / size(Ratings)) / 100000.0 as Recommendation
ORDER BY Recommendation DESC
RETURN p.ProductName, Customers, Recommendation LIMIT 10
CYPHER
}

# ================================================================================================================== #
do_report() {
  show "Inventory Level Report" <<'CYPHER'
MATCH ()-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel),
      (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel),
      (p)-[:HAS_SUPPLY_ORDER]->(suo:OrderLevel)
CALL { WITH p MATCH (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(o:Order)-[details:HAS_ORDER_PRODUCT]->(p)
        RETURN count(DISTINCT o) AS OpenCustomerOrders, coalesce(sum(details.Quantity), 0) AS QtyDemanded }
CALL { WITH p MATCH (po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(:RFQ)-[rfi:HAS_RFQ_ITEM]->(p)
        WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
        RETURN coalesce(sum(rfi.RFQqt), 0) AS QtyApprovedRFQPendingDelivery }
CALL { WITH p MATCH (po2:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p)
        WHERE ((po2)<-[:IS_NEW_PO_STATE]-(:NewPoS) OR (po2)<-[:IS_APPROVED_PO_STATE]-(:ApprovedPoS) OR (po2)<-[:IS_SUBMITTED_PO_STATE]-(:SubmittedPoS))
          AND NOT (po2)-[:HAS_APPROVED_RFQ]->(:RFQ)
        RETURN coalesce(sum(poi2.POqt), 0) AS QtyOpenPOsNotYetConfirmed }
RETURN p.ProductName AS ProductName, inv.UnitsInStock AS UnitsInStock, r.StockThreshold AS StockThreshold,
       suo.UnitsOnOrder AS UnitsOnOrder_Tracked, QtyApprovedRFQPendingDelivery, QtyOpenPOsNotYetConfirmed,
       (QtyApprovedRFQPendingDelivery + QtyOpenPOsNotYetConfirmed) AS TotalIncomingQty, OpenCustomerOrders, QtyDemanded
ORDER BY ProductName
CYPHER
}

# ================================================================================================================== #
# Data-quality checks (count{} subqueries rewritten as size([pattern comprehension])). Every result should be empty/0.
do_checks() {
  show "Duplicate relationships (same type, same two nodes)" <<'CYPHER'
MATCH (a)-[r]->(b)
WITH a, b, type(r) AS relType, count(r) AS cnt
WHERE cnt > 1
RETURN id(a) AS from, id(b) AS to, relType, cnt ORDER BY cnt DESC LIMIT 25
CYPHER
  show "POs with <> 1 active Procurement state" <<'CYPHER'
MATCH (po:PurchaseOrder)
WITH po,
     size([(po)<-[:IS_NEW_PO_STATE]-() | 1])       AS isNew,
     size([(po)<-[:IS_APPROVED_PO_STATE]-() | 1])  AS isApproved,
     size([(po)<-[:IS_SUBMITTED_PO_STATE]-() | 1]) AS isSubmitted,
     size([(po)<-[:IS_REJECTED_PO_STATE]-() | 1])  AS isRejected,
     size([(po)<-[:IS_CLOSED_PO_STATE]-() | 1])    AS isClosed
WITH po, isNew, isApproved, isSubmitted, isRejected, isClosed,
     (CASE WHEN isNew>0 THEN 1 ELSE 0 END + CASE WHEN isApproved>0 THEN 1 ELSE 0 END
    + CASE WHEN isSubmitted>0 THEN 1 ELSE 0 END + CASE WHEN isRejected>0 THEN 1 ELSE 0 END
    + CASE WHEN isClosed>0 THEN 1 ELSE 0 END) AS activeStates
WHERE activeStates <> 1
RETURN po.PONumber, isNew, isApproved, isSubmitted, isRejected, isClosed, activeStates
CYPHER
  show "Orders both Open and Fulfilled (or fulfilled twice)" <<'CYPHER'
MATCH (o:Order)
WITH o, size([(o)<-[:IS_OPEN_ORDER_STATE]-() | 1]) AS isOpen, size([(o)<-[:IS_FULFILLED_ORDER_STATE]-() | 1]) AS isFulfilled
WHERE (isOpen > 0 AND isFulfilled > 0) OR isFulfilled > 1
RETURN o.OrderID, isOpen, isFulfilled
CYPHER
  show "Negative UnitsInStock / UnitsOnOrder, paid-but-undelivered POs" <<'CYPHER'
CALL { MATCH (i:InventoryLevel) WHERE i.UnitsInStock < 0 RETURN count(i) AS NegativeStock }
CALL { MATCH (s:OrderLevel) WHERE s.UnitsOnOrder < 0 RETURN count(s) AS NegativeOnOrder }
CALL { MATCH (po:PurchaseOrder)-[:HAS_FINANCE_PAYMENT]->() WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->() RETURN count(po) AS PaidNotDelivered }
RETURN NegativeStock, NegativeOnOrder, PaidNotDelivered
CYPHER
}

case "${1:-import}" in
  import)    do_import ;;
  recommend) do_recommend ;;
  report)    do_report ;;
  checks)    do_checks ;;
  all)       do_import; do_recommend; do_report; do_checks ;;
  *) echo "usage: $0 [import|recommend|report|checks|all]"; exit 2 ;;
esac
