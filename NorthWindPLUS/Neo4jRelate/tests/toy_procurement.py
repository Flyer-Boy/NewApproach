"""A small procurement graph for the Procurement Assistant tests (v2.3.3 model).

Expected recommendations (harness formulas):
  - Supplier 1, Chai (stock 5, threshold 20, nothing pending or promised): new PO 20 - 5 + 40 = 55; resubmission 20 - 5 + 10 = 25
  - Supplier 1, Chang (stock 100, threshold 10): not needed
  - Supplier 2, Aniseed Syrup (stock 0, threshold 10, 15 promised to an open order): new PO 10 + 15 + 20 = 45
  - Supplier 2, Discontinued Spice (not available): never recommended
  - PO-R1 (Supplier 1, Chai 30, rejected by L1) can be resubmitted or cancelled; PO-R2 (Supplier 2, discontinued spice) has nothing still needed.
Unit prices 10.00 (cost 7.00 after the 0.7 discount).
Recent demand (7-day window): Chai 900 units in fulfilled orders over the last 2 days = 450/day (a 1000-unit order 10 days ago is
outside the window); 55 covers 60/450 = 0.1 days, 7 days needs 3150 - 5 = 3145 (cost 22,015: L3). Aniseed Syrup: 15 units over
12 hours = 30/day; effective stock -15; 45 covers 1.0 day, 7 days needs 210 + 15 = 225.
"""

TOY_PROCUREMENT = """
CREATE (pos:PoS {Name:"PoS"}),
  (pos)-[:HAS_NEW_PO_STATE]->(n:NewPoS {Name:"NewPoS"}), (pos)-[:HAS_APPROVED_PO_STATE]->(:ApprovedPoS {Name:"ApprovedPoS"}),
  (pos)-[:HAS_REJECTED_PO_STATE]->(rj:RejectedPoS {Name:"RejectedPoS"}), (pos)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS {Name:"SubmittedPoS"}),
  (pos)-[:HAS_CANCELLED_PO_STATE]->(:CancelledPoS {Name:"CancelledPoS"}),
  (av:ProductStatusAvailablE {Status:"Available"}), (:ProductStatusDiscontinueD {Status:"Discontinued"}),
  (l1:RolE {Title:"Level1Approver", ApprovalBase:0.00, ApprovalLimit:5000.00}),
  (l2:RolE {Title:"Level2Approver", ApprovalBase:5000.00, ApprovalLimit:12500.00}),
  (l3:RolE {Title:"Level3Approver", ApprovalBase:12500.00, ApprovalLimit:500000.00}),
  (pa:RolE {Title:"Procurement Assistant"}),
  (pa)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(albert:Employee {EmployeeID:"16", Email:"Albert.Camus@northwind.com"})-[:HAS_PERSON]->(:Person {FirstName:"Albert", LastName:"Camus"}),
  (pa)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(bernard:Employee {EmployeeID:"17", Email:"Bernard.Shaw@northwind.com"})-[:HAS_PERSON]->(:Person {FirstName:"Bernard", LastName:"Shaw"}),
  (l1)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(gloria:Employee {EmployeeID:"12", Email:"Gloria.Gaynor@northwind.com"})-[:HAS_PERSON]->(:Person {FirstName:"Gloria", LastName:"Gaynor"}),
  (s1:Supplier {SupplierID:"1", CompanyName:"Exotic Liquids"}), (s2:Supplier {SupplierID:"2", CompanyName:"New Orleans Cajun Delights"}),
  (chai:Product {ProductID:"1", ProductName:"Chai", UnitPrice:10.0}), (chang:Product {ProductID:"2", ProductName:"Chang", UnitPrice:10.0}),
  (syrup:Product {ProductID:"3", ProductName:"Aniseed Syrup", UnitPrice:10.0}), (spice:Product {ProductID:"4", ProductName:"Discontinued Spice", UnitPrice:10.0}),
  (s1)-[:SUPPLIES]->(chai), (s1)-[:SUPPLIES]->(chang), (s2)-[:SUPPLIES]->(syrup), (s2)-[:SUPPLIES]->(spice),
  (av)-[:IS_AVAILABLE_PRODUCT]->(chai), (av)-[:IS_AVAILABLE_PRODUCT]->(chang), (av)-[:IS_AVAILABLE_PRODUCT]->(syrup),
  (chai)-[:HAS_INVENTORY_LEVEL]->(:InventoryLevel {UnitsInStock:5}), (chai)-[:HAS_REORDER_LEVEL]->(:ReorderLevel {StockThreshold:20}),
  (chang)-[:HAS_INVENTORY_LEVEL]->(:InventoryLevel {UnitsInStock:100}), (chang)-[:HAS_REORDER_LEVEL]->(:ReorderLevel {StockThreshold:10}),
  (syrup)-[:HAS_INVENTORY_LEVEL]->(:InventoryLevel {UnitsInStock:0}), (syrup)-[:HAS_REORDER_LEVEL]->(:ReorderLevel {StockThreshold:10}),
  (spice)-[:HAS_INVENTORY_LEVEL]->(:InventoryLevel {UnitsInStock:0}), (spice)-[:HAS_REORDER_LEVEL]->(:ReorderLevel {StockThreshold:10}),
  (:OrderStatusOpeN {Status:"Open"})-[:IS_OPEN_ORDER_STATE]->(o:Order {OrderID:"90001", OrderDate:datetime() - duration({hours: 12})})-[:HAS_ORDER_PRODUCT {Quantity:15, UnitPrice:10.0, Discount:0.0}]->(syrup),
  (rj)-[:IS_REJECTED_PO_STATE {Date:datetime()}]->(r1:PurchaseOrder {PONumber:"PO-R1", PODate:datetime()}),
  (r1)-[:PO_FOR_SUPPLIER]->(s1), (r1)-[:PO_CREATED_BY]->(bernard), (r1)-[:HAS_PO_ITEM {POqt:30, POPriceDiscount:0.7}]->(chai),
  (r1)-[:HAS_L1_PO_REJECTION {Date:datetime(), Source:"simulation", Comment:"Quantity too high for current demand."}]->(gloria),
  (rj)-[:IS_REJECTED_PO_STATE {Date:datetime()}]->(r2:PurchaseOrder {PONumber:"PO-R2", PODate:datetime()}),
  (r2)-[:PO_FOR_SUPPLIER]->(s2), (r2)-[:PO_CREATED_BY]->(bernard), (r2)-[:HAS_PO_ITEM {POqt:40, POPriceDiscount:0.7}]->(spice),
  (r2)-[:HAS_L1_PO_REJECTION {Date:datetime(), Source:"simulation", Comment:"Product discontinued."}]->(gloria),
  (ful:OrderStatusFulfilleD {Status:"Fulfilled"}),
  (ful)-[:IS_FULFILLED_ORDER_STATE {FulfillDate:datetime()}]->(:Order {OrderID:"80001", OrderDate:datetime() - duration({days: 2})})-[:HAS_ORDER_PRODUCT {Quantity:300, UnitPrice:10.0, Discount:0.0}]->(chai),
  (ful)-[:IS_FULFILLED_ORDER_STATE {FulfillDate:datetime()}]->(:Order {OrderID:"80002", OrderDate:datetime() - duration({days: 1})})-[:HAS_ORDER_PRODUCT {Quantity:300, UnitPrice:10.0, Discount:0.0}]->(chai),
  (ful)-[:IS_FULFILLED_ORDER_STATE {FulfillDate:datetime()}]->(:Order {OrderID:"80003", OrderDate:datetime() - duration({hours: 1})})-[:HAS_ORDER_PRODUCT {Quantity:300, UnitPrice:10.0, Discount:0.0}]->(chai),
  (ful)-[:IS_FULFILLED_ORDER_STATE {FulfillDate:datetime()}]->(:Order {OrderID:"70001", OrderDate:datetime() - duration({days: 10})})-[:HAS_ORDER_PRODUCT {Quantity:1000, UnitPrice:10.0, Discount:0.0}]->(chai)
"""
