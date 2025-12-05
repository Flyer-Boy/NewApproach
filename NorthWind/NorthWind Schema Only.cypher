// -------------------------------------------------------------------   //

//     Schema craeted by Arrows app  - SCHEMA ONLY - NO DATA             //

// -------------------------------------------------------------------   //

MATCH (n) DETACH DELETE n;

CREATE (:Notes {Notes: ""})<-[:HAS_NOTES]-(n0:Employee {EmployeeID: "", HireDate: "", PhotoPath: "", Email: "", Extension: ""})-[: HAS_OFFICE_ADDRESS]->(Address {Address: "", City: "", Region: "", PostalCode: "", Country: ""})<-[:HAS_SUPPLIER_ADDRESS]-(n6:Supplier {SupplierID: "", CompanyName: "", HomePage: ""})<-[:HAS_SUPPLIER]-(n7:Product {ProductID: "", ProductName: "", QuantityPerUnit: "", UnitPrice: "", ReorderLevel: ""})<-[:HAS {RelType: "IS_DISCONTINUED"}]-(:ProductStatus_DiscontinueD {Status: "Discontinued"}),
(n18:Territory {TerritoryID: "", TerritoryDescription: ""})-[:HAS {RelType: "HAS_EMPLYEE"}]->(n0)-[:REPORTS_TO]->(n0)-[:HAS_PERSON]->(:Person {FirstName: "", LastName: "", TitleOfCourtesy: "", BirthDate: "", PersonalPhone: "", PersonalEmail: ""})-[:HAS_HOME_ADDRESS]->(Address),
(:CategorY {CategoryID: "", CategoryName: "", Description: ""})-[:HAS {RelType: "HAS_PRODUCT"}]->(n7)<-[:HAS {RelType: "IS_AVAILABLE"}]-(:ProductStatus_AvailablE {Status: "Available"}),
(:InventoryLevel {UnitsInStock: "", LastUpdate: ""})<-[:CURRENT_STOCK]-(n7)<-[:SUPPLIES]-(n6)-[:HAS_SUPPLIER_CONTACT]->(n8:Contact {ContactName: "", ContactTitle: "", Email: "", Fax: "", Phone: ""})<-[:HAS_CUSTOMER_CONTACT]-(n10:Customer {CustomerID: "", CompanyName: ""})<-[:HAS_CUSTOMER]-(n11:Order {OrderID: "", OrderDate: "", RequireDate: ""})-[:HAS_SHIPMENT]->(n13:ShipInfo {ShippmentID: "", ShippedDate: ""})-[:HAS_SHIPPER]->(:Shipper {ShipperID: "", CompanyName: ""})-[:HAS_SUPPLIER_CONTACT]->(n8),
(n13)-[:HAS_SHIPPMENT_ADDRESS]->(Address)<-[:HAS_CUSTOMER_ADDRESS]-(n10),
(:OrderStatus_OpeN {Status: "Open"})-[:HAS {RelType: "IS_OPEN"}]->(n11)-[:HAS_PRODUCT {Quantity: "", UnitPrice: "", Discount: ""}]->(n7)-[:HAS_SUPPLY_ORDER]->(:OrderLevel {UnitsOnOrder: "", LastUpdate: ""}),
(:Regions {RegionID: "", RegionDescription: ""})-[:HAS {RelType: "HAS_TERRITORY"}]->(n18),
(:OrderStatus_FulfilleD {Status: "Fulfilled"})-[:HAS {RelType: "IS_FULFILLED", FulfillDate: ""}]->(n11)-[:SOLD_BY]->(n0),
(:RoleS {Name: "RoleS"})-[:HAS {RelType: "HAS_ROLES"}]->(:RolE {Title: ""})-[:HAS {RelType: "IS_ROLE"}]->(n0),
(:OrderStatus_CanceleD {Status: "Canceled"})-[:HAS {RelType: "IS_CANCELED", CancelDate: ""}]->(n11);

MATCH n=()-[]-()-[]-() RETURN n;

