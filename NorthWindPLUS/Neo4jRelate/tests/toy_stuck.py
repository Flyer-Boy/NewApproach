"""
A small NorthWind PLUS graph where a large Customer Order is starved by small ones (tests/test_unblock_offline.py).

Products (Supplier 1: Chai, Chang; Supplier 2: Aniseed Syrup), stock 30 / 25 / 50.

Open orders:
  CO-BIG-1   10 hours old: Chai 40, Chang 30. Both lines short (a line is covered only when stock > quantity).
  CO-SMALL-1..4   1 hour old: Chai 5 each. Fully in stock, so the loop ships them first and Chai drops to 10.
  10999   an imported historical order from 1997, still open: Chai 35, Aniseed Syrup 5. Short of Chai today, but the
          oldest order of all: when an extra Chai delivery lands it ships first and takes 35, so the stuck order needs
          more than its own shortfall. Not a "CO-" order, so it's never reported as stuck itself.
  10251..10280   30 imported historical orders from 1997, shipped over the last 6 hours (as on a freshly loaded Aura,
          where the loop works through the old backlog). They count for orders shipped per hour, but not for the
          median time to ship, which would otherwise be decades.

History (last 6 hours): 24 orders shipped 30 minutes after they were placed (median time to ship 30 minutes, so an
order is stuck after 90 minutes), each Chai 5 or Aniseed Syrup 3; 4 POs delivered 60 minutes after creation (PO lead
time 60 minutes). One PO for 10 Chai is on its way, created 30 minutes ago (due in about 30 minutes).

So: about 4 orders shipped per hour and 3 received per hour; the naive shortfall for BIG-1 is 11 Chai and 6 Chang,
but by the time an extra delivery lands (60 minutes) the small orders (20) and new arrivals have taken more Chai than
the PO on its way brings (10), and order 10999 takes 35 Chai first when the extra lands, so the simulated need for Chai
is far higher. Chang has no competition and nothing on order. Reserving stock for BIG-1 instead can't free
it: nothing is coming for Chang.
"""

TOY_STUCK = """
CREATE
  (open:OrderStatusOpeN {Status:"Open"}), (ful:OrderStatusFulfilleD {Status:"Fulfilled"}),
  (newpos:NewPoS {Name:"NewPoS"}), (avail:ProductStatusAvailablE {Status:"Available"}),
  (s1:Supplier {SupplierID:"1", CompanyName:"Exotic Liquids"}), (s2:Supplier {SupplierID:"2", CompanyName:"New Orleans Cajun Delights"}),
  (chai:Product {ProductID:"1", ProductName:"Chai", UnitPrice:10.0}),
  (chang:Product {ProductID:"2", ProductName:"Chang", UnitPrice:20.0}),
  (syrup:Product {ProductID:"3", ProductName:"Aniseed Syrup", UnitPrice:10.0}),
  (s1)-[:SUPPLIES]->(chai), (s1)-[:SUPPLIES]->(chang), (s2)-[:SUPPLIES]->(syrup),
  (avail)-[:IS_AVAILABLE_PRODUCT]->(chai), (avail)-[:IS_AVAILABLE_PRODUCT]->(chang), (avail)-[:IS_AVAILABLE_PRODUCT]->(syrup),
  (chai)-[:HAS_INVENTORY_LEVEL]->(:InventoryLevel {UnitsInStock:30}), (chai)-[:HAS_REORDER_LEVEL]->(:ReorderLevel {StockThreshold:20}),
  (chang)-[:HAS_INVENTORY_LEVEL]->(:InventoryLevel {UnitsInStock:25}), (chang)-[:HAS_REORDER_LEVEL]->(:ReorderLevel {StockThreshold:20}),
  (syrup)-[:HAS_INVENTORY_LEVEL]->(:InventoryLevel {UnitsInStock:50}), (syrup)-[:HAS_REORDER_LEVEL]->(:ReorderLevel {StockThreshold:20}),
  (cust:Customer {CustomerID:"ALFKI", CompanyName:"Alfreds Futterkiste"})-[:HAS_CUSTOMER_ADDRESS]->(:Address {City:"Berlin"}),
  (big:Customer {CustomerID:"ERNSH", CompanyName:"Ernst Handel"})-[:HAS_CUSTOMER_ADDRESS]->(:Address {City:"Graz"}),
  (clerk:Employee {EmployeeID:"30"})-[:HAS_PERSON]->(:Person {FirstName:"Wanda", LastName:"Clerk"}),
  (:RolE {Title:"WarehouseClerk"})-[:IS_ACTIVE_ROLE]->(clerk),
  (albert:Employee {EmployeeID:"16"})-[:HAS_PERSON]->(:Person {FirstName:"Albert", LastName:"Camus"}),
  (gloria:Employee {EmployeeID:"12"})-[:HAS_PERSON]->(:Person {FirstName:"Gloria", LastName:"Gaynor"}),
  (pa:RolE {Title:"Procurement Assistant"})-[:IS_ACTIVE_ROLE]->(albert),
  (:RolE {Title:"Level1Approver", ApprovalBase:0.0, ApprovalLimit:5000.0})-[:IS_ACTIVE_ROLE]->(gloria),
  (:RolE {Title:"Level2Approver", ApprovalBase:5000.0, ApprovalLimit:12500.0}),
  (:RolE {Title:"Level3Approver", ApprovalBase:12500.0, ApprovalLimit:500000.0}),
  (:ShipInfo {ShippmentID:"SH-0", ShipName:"Toy Ship"})-[:HAS_SHIPPER]->(:Shipper {CompanyName:"Speedy Express"}),
  (open)-[:IS_OPEN_ORDER_STATE]->(b:Order {OrderID:"CO-BIG-1", OrderDate:datetime() - duration({hours: 10}), RequiredDate:datetime() - duration({hours: 2})}),
  (b)-[:HAS_ORDER_CUSTOMER]->(big),
  (b)-[:HAS_ORDER_PRODUCT {Quantity:40, UnitPrice:10.0, Discount:0.0}]->(chai),
  (b)-[:HAS_ORDER_PRODUCT {Quantity:30, UnitPrice:20.0, Discount:0.0}]->(chang)
CREATE (open)-[:IS_OPEN_ORDER_STATE]->(lg:Order {OrderID:"10999", OrderDate:datetime("1997-04-23T00:00:00Z"), RequiredDate:datetime("1997-05-21T00:00:00Z")}),
       (lg)-[:HAS_ORDER_CUSTOMER]->(cust),
       (lg)-[:HAS_ORDER_PRODUCT {Quantity:35, UnitPrice:10.0, Discount:0.0}]->(chai),
       (lg)-[:HAS_ORDER_PRODUCT {Quantity:5, UnitPrice:10.0, Discount:0.0}]->(syrup)
WITH open, ful, cust, chai, syrup, newpos, s1, albert, clerk
UNWIND range(1, 30) AS k
CREATE (ful)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: datetime() - duration({minutes: 11 * k})}]->
         (old:Order {OrderID:toString(10250 + k), OrderDate:datetime("1997-07-08T00:00:00Z"), RequiredDate:datetime("1997-08-05T00:00:00Z")}),
       (old)-[:HAS_ORDER_CUSTOMER]->(cust),
       (old)-[:HAS_ORDER_PRODUCT {Quantity:3, UnitPrice:10.0, Discount:0.0}]->(syrup)
WITH DISTINCT open, ful, cust, chai, syrup, newpos, s1, albert, clerk
UNWIND range(1, 4) AS k
CREATE (open)-[:IS_OPEN_ORDER_STATE]->(o:Order {OrderID:"CO-SMALL-" + toString(k), OrderDate:datetime() - duration({minutes: 60 - k}),
                                                RequiredDate:datetime() + duration({days: 3})}),
       (o)-[:HAS_ORDER_CUSTOMER]->(cust),
       (o)-[:HAS_ORDER_PRODUCT {Quantity:5, UnitPrice:10.0, Discount:0.0}]->(chai)
WITH DISTINCT ful, cust, chai, syrup, newpos, s1, albert, clerk
UNWIND range(1, 24) AS k
WITH ful, cust, chai, syrup, newpos, s1, albert, clerk, k, datetime() - duration({minutes: 15 * k}) AS placed
CREATE (ful)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: placed + duration({minutes: 30})}]->
       (h:Order {OrderID:"CO-H-" + toString(k), OrderDate: placed, RequiredDate: placed + duration({days: 3})}),
       (h)-[:HAS_ORDER_CUSTOMER]->(cust)
FOREACH (_ IN CASE WHEN k % 2 = 0 THEN [1] ELSE [] END |
  CREATE (h)-[:HAS_ORDER_PRODUCT {Quantity:5, UnitPrice:10.0, Discount:0.0}]->(chai))
FOREACH (_ IN CASE WHEN k % 2 = 1 THEN [1] ELSE [] END |
  CREATE (h)-[:HAS_ORDER_PRODUCT {Quantity:3, UnitPrice:10.0, Discount:0.0}]->(syrup))
WITH DISTINCT newpos, s1, chai, albert, clerk
UNWIND range(1, 4) AS k
CREATE (d:PurchaseOrder {PONumber:"PO-H" + toString(k), PODate: datetime() - duration({minutes: 60 * k + 60})})-[:HAS_WAREHOUSE_DELIVERY {Date: datetime() - duration({minutes: 60 * k}), Source:"simulation"}]->(clerk)
WITH DISTINCT newpos, s1, chai, albert
CREATE (newpos)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {PONumber:"PO-ONWAY", PODate: datetime() - duration({minutes: 30})}),
       (po)-[:PO_FOR_SUPPLIER]->(s1),
       (po)-[:PO_CREATED_BY {Date: datetime() - duration({minutes: 30}), Source:"simulation"}]->(albert),
       (po)-[:HAS_PO_ITEM {POqt:10, POPriceDiscount:0.7}]->(chai)
"""
