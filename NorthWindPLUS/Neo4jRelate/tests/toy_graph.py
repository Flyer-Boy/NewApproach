"""Tiny NorthWind PLUS graph shared by the offline tests."""

TOY = """
CREATE (rs:RoleS {Name:"RoleS"}), (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}),
  (l1:RolE {Title:"Level1Approver", ApprovalBase:0.00, ApprovalLimit:5000.00, Rules:"old"}),
  (l2:RolE {Title:"Level2Approver", ApprovalBase:5000.01, ApprovalLimit:12500.00, Rules:"old"}),
  (l3:RolE {Title:"Level3Approver", ApprovalBase:12500.01, ApprovalLimit:500000.00, Rules:"old"}),
  (pp:RolE {Title:"ProcurementPolicyAdmin"}),
  (pp)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(olivia:Employee {EmployeeID:"25", Email:"Olivia.Bennett@northwind.com"})-[:HAS_PERSON]->(:Person {FirstName:"Olivia", LastName:"Bennett"}),
  (l1)-[:IS_ACTIVE_ROLE {StartDate:datetime()}]->(gloria:Employee {EmployeeID:"12", Email:"Gloria.Gaynor@northwind.com"})-[:HAS_PERSON]->(:Person {FirstName:"Gloria", LastName:"Gaynor"}),
  (n:NewPoS {Name:"NewPoS"}), (p:Product {ProductID:"1", ProductName:"Chai", UnitPrice:10.0}),
  (n)-[:IS_NEW_PO_STATE]->(:PurchaseOrder {PONumber:"PO-A"})-[:HAS_PO_ITEM {POqt:1000, POPriceDiscount:0.7}]->(p),
  (n)-[:IS_NEW_PO_STATE]->(:PurchaseOrder {PONumber:"PO-B"})-[:HAS_PO_ITEM {POqt:2000, POPriceDiscount:0.7}]->(p),
  (s1:Supplier {SupplierID:"1", CompanyName:"Exotic Liquids"}), (s2:Supplier {SupplierID:"2", CompanyName:"Tokyo Traders"}),
  (rej:PoRejectedRFQ {Name:"PoRejectedRFQ"}),
  (:RFQ {RFQNumber:"R1"})-[:RFQ_FROM_SUPPLIER]->(s1), (r2:RFQ {RFQNumber:"R2"})-[:RFQ_FROM_SUPPLIER]->(s1),
  (:RFQ {RFQNumber:"R3"})-[:RFQ_FROM_SUPPLIER]->(s2), (rej)-[:IS_SUPPLIER_REJECTED_RFQ_STATE {Date:datetime()}]->(r2)
"""
