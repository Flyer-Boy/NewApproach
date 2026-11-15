"""A small PO-vetting queue for the what-if tests: three approver levels, the state nodes and five POs.

Costs (qty x UnitPrice 10 x discount 0.7): PO-1 700, PO-2 4,200, PO-3 7,000, PO-4 14,000, PO-5 5,000.00 exactly
(on the L1 limit, so only a rejection can match it under the current limits).
"""

TOY_VETTING = """
CREATE (n:NewPoS {Name:"NewPoS"}), (:ApprovedPoS {Name:"ApprovedPoS"}), (:RejectedPoS {Name:"RejectedPoS"}),
  (l1:RolE {Title:"Level1Approver", ApprovalBase:0.00, ApprovalLimit:5000.00}),
  (l2:RolE {Title:"Level2Approver", ApprovalBase:5000.01, ApprovalLimit:12500.00}),
  (l3:RolE {Title:"Level3Approver", ApprovalBase:12500.01, ApprovalLimit:500000.00}),
  (l1)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(:Employee {EmployeeID:"12"}),
  (l2)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(:Employee {EmployeeID:"13"}),
  (l3)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(:Employee {EmployeeID:"14"}),
  (other:RolE {Title:"Buyer"})-[:IS_ACTIVE_ROLE]->(:Employee {EmployeeID:"20"}),
  (p:Product {ProductID:"1", ProductName:"Chai", UnitPrice:10.0}),
  (n)-[:IS_NEW_PO_STATE {Date:datetime()}]->(:PurchaseOrder {PONumber:"PO-1", PODate:datetime()})-[:HAS_PO_ITEM {POqt:100, POPriceDiscount:0.7}]->(p),
  (n)-[:IS_NEW_PO_STATE {Date:datetime()}]->(:PurchaseOrder {PONumber:"PO-2", PODate:datetime()})-[:HAS_PO_ITEM {POqt:600, POPriceDiscount:0.7}]->(p),
  (n)-[:IS_NEW_PO_STATE {Date:datetime()}]->(:PurchaseOrder {PONumber:"PO-3", PODate:datetime()})-[:HAS_PO_ITEM {POqt:1000, POPriceDiscount:0.7}]->(p),
  (n)-[:IS_NEW_PO_STATE {Date:datetime()}]->(:PurchaseOrder {PONumber:"PO-4", PODate:datetime()})-[:HAS_PO_ITEM {POqt:2000, POPriceDiscount:0.7}]->(p),
  (n)-[:IS_NEW_PO_STATE {Date:datetime()}]->(:PurchaseOrder {PONumber:"PO-5", PODate:datetime()})-[:HAS_PO_ITEM {POqt:500, POPriceDiscount:1.0}]->(p),
  (:Supplier {SupplierID:"1"}), (:Order {OrderID:"9"}),
  (:RolE {Title:"ProcurementPolicyAdmin"})-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(:Employee {EmployeeID:"25", Email:"Olivia.Bennett@northwind.com"})-[:HAS_PERSON]->(:Person {FirstName:"Olivia", LastName:"Bennett"})
"""
