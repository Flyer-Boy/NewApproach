// GRAPH TYPE schema for the NorthWind PLUS Graph Data Model (v2.2).
// Built directly from NorthWind_PLUS_Graph_Data_Model_Import_v2_2.cypher --
// every node/relationship below was traced to an actual CREATE/MERGE in
// that script (plus the confirmed additions from the stress-test harness:
// HAS_WAREHOUSE_FULFILLMENT on Order, which order-fulfillment creates but
// the base script's original demo query didn't).
//
// -----------------------------------------------------------------------
// KNOWN ISSUES -- read before using
// -----------------------------------------------------------------------
// 1. RESOLVED: HAS_CLOSED_PO_STATE was previously used for two different
//    edges -- (PoS)->(ClosedPoS) collection membership, and
//    (ClosedPoS)->(PurchaseOrder) instance state -- confirmed as a naming
//    collision and resolved: HAS_CLOSED_PO_STATE stays as the
//    collection-membership edge; the instance-level edge is now declared
//    below as IS_CLOSED_PO_STATE, matching the source model's own
//    ontology comment (which already documented this as the intended
//    name). The main script's PO Payment and Closure section and the
//    Python stress-test harness's finance_closure action both still need
//    this same rename applied -- this schema reflects the target state,
//    not (yet) what those two files currently create.
//
// 2. Order.OrderDate/RequiredDate have two shapes depending on creation
//    path: CSV-imported Orders get explicitly normalized to real
//    TIMESTAMP WITH TIME ZONE values; Orders created by the "random
//    Customer order" loop use OrderDate::DATE and a *differently spelled*
//    RequireDate::DATE (not RequiredDate) -- a leftover typo flagged
//    earlier and not yet fixed. Both property names are declared below as
//    optional rather than assuming one is authoritative.
//
// 3. ShipInfo has two shapes (bulk import: ShipName/ShippedDate/Freight,
//    all String, Freight never converted from CSV; "Fulfilling an Order"
//    example: ShippmentID/ShippedDate). Nothing here is NOT NULL, to
//    accommodate both.
//
// 4. SupplierNewPoS, SupplierOpenPoS, SupplierClosedPoS, PoNewRFQ, and
//    PoRejectedRFQ are NOT singletons like the other Collection nodes --
//    one instance is created PER Supplier (the first three) or PER
//    PurchaseOrder (the last two). They now carry a Name property (added
//    later, matching their label as a type descriptor), but that value is
//    IDENTICAL across every instance -- every Supplier's own SupplierNewPoS
//    node has Name:"SupplierNewPoS", the same as every other Supplier's.
//    That's not a unique identifier, so no REQUIRE/KEY is declared on it --
//    doing so would require uniqueness that doesn't exist. If a genuine
//    per-instance key is ever wanted, it would need to be generated at
//    creation time (e.g. Name: s.SupplierID + "-SupplierNewPoS"), which
//    would also require a matching change in the main import script.
//
// 5. RolE.ApprovalBase/ApprovalLimit only exist on Level1/2/3Approver;
//    every other RolE (including all CSV-imported Northwind titles like
//    "Sales Representative") has only Title/Description/Rules. Declared
//    as optional below.
//
// 6. PendingSupplierS/RejectedSupplierS (and their IS_SUPPLIER_PENDING_
//    STATE/IS_SUPPLIER_REJECTED_STATE instance edges) and
//    OrderStatusCanceleD are declared for completeness -- none are
//    currently exercised by the script (no Supplier vetting workflow or
//    Order cancellation path exists yet), matching the same "declared but
//    unused" pattern as the original Northwind model's OrderStatusCanceleD.
// -----------------------------------------------------------------------

ALTER CURRENT GRAPH TYPE SET {};

ALTER CURRENT GRAPH TYPE SET {

// *******   Entity (Proper Noun Node) Definitions   *******

(c:ProductCategorY => {
    CategoryID :: STRING NOT NULL,
    CategoryName :: STRING NOT NULL,
    Description :: STRING
     }) REQUIRE (c.CategoryID) IS KEY,

(s:Supplier => {
    SupplierID :: STRING NOT NULL,
    CompanyName :: STRING NOT NULL,
    HomePage :: STRING
     }) REQUIRE (s.SupplierID) IS KEY,

(p:Product => {
    ProductID :: STRING NOT NULL,
    ProductName :: STRING NOT NULL,
    UnitPrice :: FLOAT,
    QuantityPerUnit :: STRING
     }) REQUIRE (p.ProductID) IS KEY,

// ContactName/ContactTitle optional -- see the main script's own
// "Add a new Customer" example, which sets them directly on Customer
// alongside a separate Contact node (a known ontology-purity gap flagged
// earlier, not fixed here).
(cu:Customer => {
    CustomerID :: STRING NOT NULL,
    CompanyName :: STRING NOT NULL,
    ContactName :: STRING,
    ContactTitle :: STRING
     }) REQUIRE (cu.CustomerID) IS KEY,

// HireDate/PhotoPath only exist on CSV-imported Employees; Extension
// exists on both CSV-imported and demo-added Employees (Adam Smith, etc.).
(e:Employee => {
    EmployeeID :: STRING NOT NULL,
    Email :: STRING NOT NULL,
    Extension :: STRING,
    HireDate :: STRING,
    PhotoPath :: STRING
     }) REQUIRE (e.EmployeeID) IS KEY,

// No identifying property. TitleOfCourtesy only exists on CSV-imported
// Employees' Person nodes, not the demo-added ones.
(:Person => {
    FirstName :: STRING NOT NULL,
    LastName :: STRING NOT NULL,
    TitleOfCourtesy :: STRING,
    BirthDate :: STRING,
    PersonalPhone :: STRING,
    PersonalEmail :: STRING
     }),

(t:Territory => {
    TerritoryID :: STRING NOT NULL,
    TerritoryDescription :: STRING
     }) REQUIRE (t.TerritoryID) IS KEY,

(rg:Regions => {
    RegionID :: STRING NOT NULL,
    RegionDescription :: STRING
     }) REQUIRE (rg.RegionID) IS KEY,

(sh:Shipper => {
    ShipperID :: STRING NOT NULL,
    CompanyName :: STRING NOT NULL,
    Phone :: STRING
     }) REQUIRE (sh.ShipperID) IS KEY,

// See caveat 2: two creation paths produce different date property names
// and types. Both declared, both optional.
(o:Order => {
    OrderID :: STRING NOT NULL,
    OrderDate :: ZONED DATETIME,
    RequiredDate :: ZONED DATETIME
     }) REQUIRE (o.OrderID) IS KEY,

(po:PurchaseOrder => {
    PONumber :: STRING NOT NULL,
    PODate :: ZONED DATETIME,
     }) REQUIRE (po.PONumber) IS KEY,

(rfq:RFQ => {
    RFQNumber :: STRING NOT NULL,
    RFQDate :: ZONED DATETIME,
    RFQComments :: STRING
     }) REQUIRE (rfq.RFQNumber) IS KEY,

// No identifying property -- shared shape for Supplier, Customer,
// Employee (via Person), and Order shipment addresses.
(:Address => {
    Address :: STRING,
    City :: STRING,
    Region :: STRING,
    PostalCode :: STRING,
    Country :: STRING
     }),

// No identifying property. Fax optional -- Supplier-derived Contacts
// have it (from CSV), Customer-derived ones don't.
(:Contact => {
    ContactName :: STRING,
    ContactTitle :: STRING,
    Phone :: STRING,
    Fax :: STRING,
    Email :: STRING
     }),

(:Notes => {
    Notes :: STRING
     }),

// No identifying property. See caveat 3 -- two shapes, all optional.
(:ShipInfo => {
    ShipName :: STRING,
    ShippedDate :: STRING,
    Freight :: STRING,
    ShippmentID :: STRING
     }),

// Isotope nodes -- see the "Read-Only Nodes" exceptions in the main
// script. No identifying property; UnitsInStock/UnitsOnOrder/
// StockThreshold are the three properties in this model updated in
// place via SET rather than superseded by a relationship.
(:InventoryLevel => {
    UnitsInStock :: INTEGER NOT NULL,
    LastUpdate :: TIMESTAMP WITH TIME ZONE
     }),

(:OrderLevel => {
    UnitsOnOrder :: INTEGER NOT NULL,
    LastUpdate :: TIMESTAMP WITH TIME ZONE NOT NULL
     }),

(:ReorderLevel => {
    StockThreshold :: INTEGER NOT NULL,
    LastUpdate :: TIMESTAMP WITH TIME ZONE NOT NULL
     }),

// Title is the identifying property for every RolE, from the original
// CSV-imported Northwind titles through the new procurement roles.
// ApprovalBase/ApprovalLimit only exist on Level1/2/3Approver.
(r:RolE => {
    Title :: STRING NOT NULL,
    Description :: STRING,
    Rules :: STRING,
    ApprovalBase :: FLOAT,
    ApprovalLimit :: FLOAT
     }) REQUIRE (r.Title) IS KEY,


// *******   Collection (Hub) Node Definitions   *******
// All singleton collections below are keyed on Name (or Status for the
// Product/Order state hubs, matching the original Northwind convention).


(c1:CategorieS => { Name :: STRING NOT NULL }) REQUIRE (c1.Name) IS KEY,
(r1:RoleS => { Name :: STRING NOT NULL }) REQUIRE (r1.Name) IS KEY,
(e1:EmployeeDirectorY => { Name :: STRING NOT NULL }) REQUIRE (e1.Name) IS KEY,

(p1:ProductStatusDiscontinueD => { Status :: STRING NOT NULL }) REQUIRE (p1.Status) IS KEY,
(p2:ProductStatusAvailablE => { Status :: STRING NOT NULL }) REQUIRE (p2.Status) IS KEY,

(o1:OrderStatusOpeN => { Status :: STRING NOT NULL }) REQUIRE (o1.Status) IS KEY,
(o2:OrderStatusFulfilleD => { Status :: STRING NOT NULL }) REQUIRE (o2.Status) IS KEY,
(o3:OrderStatusCanceleD => { Status :: STRING NOT NULL }) REQUIRE (o3.Status) IS KEY,
(o4:OrderS => { Name :: STRING NOT NULL }) REQUIRE (o4.Name) IS KEY,

(s1:SupplierS => { Name :: STRING NOT NULL }) REQUIRE (s1.Name) IS KEY,
(p3:PendingSupplierS => { Name :: STRING NOT NULL }) REQUIRE (p3.Name) IS KEY,
(a1:ApprovedSupplierS => { Name :: STRING NOT NULL }) REQUIRE (a1.Name) IS KEY,
(r2:RejectedSupplierS => { Name :: STRING NOT NULL }) REQUIRE (r2.Name) IS KEY,

(p4:PoS => { Name :: STRING NOT NULL }) REQUIRE (p4.Name) IS KEY,
(n1:NewPoS => { Name :: STRING NOT NULL }) REQUIRE (n1.Name) IS KEY,
(a2:ApprovedPoS => { Name :: STRING NOT NULL }) REQUIRE (a2.Name) IS KEY,
(r3:RejectedPoS => { Name :: STRING NOT NULL }) REQUIRE (r3.Name) IS KEY,
(s2:SubmittedPoS => { Name :: STRING NOT NULL }) REQUIRE (s2.Name) IS KEY,
(c2:ClosedPoS => { Name :: STRING NOT NULL }) REQUIRE (c2.Name) IS KEY,

// Name property not Key/Unique -- these are not singletons, one instance per Supplier or PurchaseOrder.
(:SupplierNewPoS => { Name :: STRING NOT NULL }),
(:SupplierOpenPoS => { Name :: STRING NOT NULL }),
(:SupplierClosedPoS => { Name :: STRING NOT NULL }),
(:PoNewRFQ => { Name :: STRING NOT NULL }),
(:PoRejectedRFQ => { Name :: STRING NOT NULL }),


// *******   Relationship Definitions   *******

// Product / Category / Supplier
  (:ProductCategorY)-[:IS_PRODUCT_CATEGORY_OF => {}]->(:Product),
  (:CategorieS)-[:HAS_CATEGORY => {}]->(:ProductCategorY),
  (:Product)-[:HAS_REORDER_LEVEL => {}]->(:ReorderLevel),
  (:Product)-[:HAS_SUPPLY_ORDER => {}]->(:OrderLevel),
  (:Product)-[:HAS_INVENTORY_LEVEL => {}]->(:InventoryLevel),
  (:ProductStatusDiscontinueD)-[:IS_DISCONTINUED_PRODUCT => {}]->(:Product),
  (:ProductStatusAvailablE)-[:IS_AVAILABLE_PRODUCT => {}]->(:Product),
  (:Product)-[:HAS_PRODUCT_SUPPLIER => {}]->(:Supplier),
  (:Supplier)-[:SUPPLIES => {}]->(:Product),
  (:Supplier)-[:HAS_SUPPLIER_ADDRESS => {}]->(:Address),
  (:Supplier)-[:HAS_SUPPLIER_CONTACT => {}]->(:Contact),

// Customer
  (:Customer)-[:HAS_CUSTOMER_ADDRESS => {}]->(:Address),
  (:Customer)-[:HAS_CUSTOMER_CONTACT => {}]->(:Contact),

// Roles / Employees
  (:RoleS)-[:HAS_ROLE_TITLE => {}]->(:RolE),
  (:RolE)-[:IS_ACTIVE_ROLE => {StartDate :: TIMESTAMP WITH TIME ZONE NOT NULL, EndDate :: TIMESTAMP WITH TIME ZONE}]->(:Employee),
  (:Employee)-[:HAS_PERSON => {}]->(:Person),
  (:Person)-[:HAS_HOME_ADDRESS => {}]->(:Address),
  (:Employee)-[:HAS_EMPLOYEE_NOTES => {}]->(:Notes),
  (:Employee)-[:REPORTS_TO => {}]->(:Employee),
  (:Territory)-[:HAS_EMPLOYEE => {}]->(:Employee),
  (:Regions)-[:HAS_TERRITORY => {}]->(:Territory),
  (:EmployeeDirectorY)-[:HAS_ACTIVE_EMPLOYEE => {StartDate :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Employee),

// Supplier state
  (:SupplierS)-[:HAS_SUPPLIER_PENDING_STATE => {}]->(:PendingSupplierS),
  (:SupplierS)-[:HAS_SUPPLIER_APPROVED_STATE => {}]->(:ApprovedSupplierS),
  (:SupplierS)-[:HAS_SUPPLIER_REJECTED_STATE => {}]->(:RejectedSupplierS),
  (:PendingSupplierS)-[:IS_SUPPLIER_PENDING_STATE => {}]->(:Supplier),
  (:ApprovedSupplierS)-[:IS_SUPPLIER_APPROVED_STATE => {}]->(:Supplier),
  (:RejectedSupplierS)-[:IS_SUPPLIER_REJECTED_STATE => {}]->(:Supplier),

// Order
  (:Order)-[:HAS_ORDER_CUSTOMER => {}]->(:Customer),
  (:Order)-[:HAS_SHIPMENT_INFO => {}]->(:ShipInfo),
  (:ShipInfo)-[:HAS_SHIPPER => {}]->(:Shipper),
  (:ShipInfo)-[:HAS_SHIPMENT_ADDRESS => {}]->(:Address),
  (:Order)-[:SOLD_BY => {}]->(:Employee),
  (:Order)-[:HAS_ORDER_PRODUCT => {Quantity :: INTEGER NOT NULL, UnitPrice :: FLOAT NOT NULL, Discount :: FLOAT NOT NULL}]->(:Product),
  (:OrderStatusFulfilleD)-[:IS_FULFILLED_ORDER_STATE => {FulfillDate :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Order),
  (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE => {}]->(:Order),
  (:Order)-[:HAS_WAREHOUSE_FULFILLMENT => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  // Three distinct relationship types, one per subset, matching the
  // PoS/SupplierS convention -- sidesteps the untested question of
  // whether GRAPH TYPE permits multiple declarations of one relationship
  // type with different targets.
  (:OrderS)-[:HAS_OPEN_ORDER_STATUS => {}]->(:OrderStatusOpeN),
  (:OrderS)-[:HAS_FULFILLED_ORDER_STATUS => {}]->(:OrderStatusFulfilleD),
  (:OrderS)-[:HAS_CANCELED_ORDER_STATUS => {}]->(:OrderStatusCanceleD),

// PurchaseOrder / PO state
  (:PoS)-[:HAS_NEW_PO_STATE => {}]->(:NewPoS),
  (:PoS)-[:HAS_APPROVED_PO_STATE => {}]->(:ApprovedPoS),
  (:PoS)-[:HAS_REJECTED_PO_STATE => {}]->(:RejectedPoS),
  (:PoS)-[:HAS_SUBMITTED_PO_STATE => {}]->(:SubmittedPoS),
  (:PoS)-[:HAS_CLOSED_PO_STATE => {}]->(:ClosedPoS),
  (:ClosedPoS)-[:IS_CLOSED_PO_STATE => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:PurchaseOrder),
  (:NewPoS)-[:IS_NEW_PO_STATE => {}]->(:PurchaseOrder),
  (:ApprovedPoS)-[:IS_APPROVED_PO_STATE => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:PurchaseOrder),
  (:RejectedPoS)-[:IS_REJECTED_PO_STATE => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:PurchaseOrder),
  (:SubmittedPoS)-[:IS_SUBMITTED_PO_STATE => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:PurchaseOrder),
  (:PurchaseOrder)-[:PO_FOR_SUPPLIER => {}]->(:Supplier),
  (:PurchaseOrder)-[:PO_CREATED_BY => {}]->(:Employee),
  (:PurchaseOrder)-[:HAS_PO_ITEM => {POqt :: INTEGER NOT NULL, POPriceDiscount :: FLOAT NOT NULL}]->(:Product),
  (:PurchaseOrder)-[:HAS_PREVIOUS_PO => {Resubmission_Justification :: STRING}]->(:PurchaseOrder),
  (:PurchaseOrder)-[:HAS_BUYER_PO_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:PurchaseOrder)-[:HAS_L1_PO_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:PurchaseOrder)-[:HAS_L1_PO_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:PurchaseOrder)-[:HAS_L2_PO_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:PurchaseOrder)-[:HAS_L2_PO_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:PurchaseOrder)-[:HAS_L3_PO_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:PurchaseOrder)-[:HAS_L3_PO_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:PurchaseOrder)-[:HAS_WAREHOUSE_DELIVERY => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:PurchaseOrder)-[:HAS_FINANCE_PAYMENT => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),

// Supplier-side PO state
  (:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS => {}]->(:SupplierNewPoS),
  (:Supplier)-[:HAS_SUPPLIER_OPEN_POS => {}]->(:SupplierOpenPoS),
  (:Supplier)-[:HAS_SUPPLIER_CLOSED_POS => {}]->(:SupplierClosedPoS),
  (:SupplierNewPoS)-[:IS_SUPPLIER_NEW_PO_STATE => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:PurchaseOrder),
  (:SupplierOpenPoS)-[:IS_SUPPLIER_OPEN_PO_STATE => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:PurchaseOrder),
  (:SupplierClosedPoS)-[:HAS_SUPPLIER_CLOSED_PO_STATE => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:PurchaseOrder),

// RFQ
  (:PurchaseOrder)-[:HAS_SUPPLIER_NEW_RFQ => {}]->(:PoNewRFQ),
  (:PurchaseOrder)-[:HAS_SUPPLIER_REJECTED_RFQ => {}]->(:PoRejectedRFQ),
  (:PoNewRFQ)-[:IS_SUPPLIER_NEW_RFQ => {}]->(:RFQ),
  (:PoRejectedRFQ)-[:IS_SUPPLIER_REJECTED_RFQ_STATE => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:RFQ),
  (:RFQ)-[:IS_RFQ_FOR_PO => {}]->(:PurchaseOrder),
  (:RFQ)-[:RFQ_FROM_SUPPLIER => {}]->(:Supplier),
  (:RFQ)-[:HAS_RFQ_ITEM => {RFQqt :: FLOAT NOT NULL, RFQcost :: FLOAT NOT NULL}]->(:Product),
  (:RFQ)-[:HAS_PREVIOUS_RFQ => {Justification :: STRING}]->(:RFQ),
  (:RFQ)-[:HAS_BUYER_RFQ_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:RFQ)-[:HAS_BUYER_RFQ_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING}]->(:Employee),
  (:PurchaseOrder)-[:HAS_APPROVED_RFQ => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:RFQ),

// Recommendation Engine -- an optional add-on context layer per the main
// script's own framing ("does not affect the core model... can be added
// as a new layer of context/semantics/knowledge"). RATED and SIMILARITY
// introduce no new node types, only relationships between existing
// Customer/Product entities.
  (:Customer)-[:RATED => {Rating :: FLOAT NOT NULL}]->(:Product),
  (:Customer)-[:SIMILARITY => {Similarity :: FLOAT NOT NULL}]->(:Customer)

}
