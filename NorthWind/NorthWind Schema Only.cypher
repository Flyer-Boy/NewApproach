// -------------------------------------------------------------------   //

// Schema craeted by Arrows app

MATCH (n) DETACH DELETE n;

CREATE (:Notes {Notes: ""})<-[:HAS_NOTES]-(n0:Emplyee {EmployeeID: "", HireDate: "", PhotoPath: "", Email: "", Extension: ""})-[:HAS_ADDRESS]->(a:Address {Address: "", City: "", Region: "", PostalCode: "", Country: ""})<-[:HAS_ADDRESS]-(n8:Contact {ContactName: "", ContactTitle: "", Email: ""})<-[:HAS_CONTACT]-(n10:Customer {CustomerID: "", CompanyName: ""})<-[:HAS_CUSTOMER]-(n11:Order {OrderID: "", OrderDate: "", RequireDate: ""})-[:HAS_SHIPMENT]->(n13:ShipInfo {ShippmentID: "", ShippedDate: ""})-[:HAS_SHIPPER]->(:Shipper {ShipperID: "", CompanyName: ""})-[:HAS_CONTACT]->(n8),
(n18:Territory {TerritoryID: "", TerritoryDescription: ""})-[:HAS {RelType: "HAS_EMPLYEE"}]->(n0)-[:REPORTS_TO]->(n0)-[:HAS_PERSON]->(:Person {FirstName: "", LastName: "", TitleOfCourtesy: "", BirthDate: "", PersonalPhone: "", PersonalEmail: ""})-[:HAS_ADDRESS]->(a),
(:CategorY {CategoryID: "", CategoryName: "", Description: ""})-[:HAS {RelType: "HAS_PRODUCT"}]->(n7:Product {ProductID: "", ProductName: "", QuantityPerUnit: "", UnitPrice: "", PicturePath: "", ReorderLevel: ""})-[:HAS_SUPPLIER]->(n6:Supplier {SupplierID: "", CompanyName: "", HomePage: ""})-[:SUPPLIES]->(n7)-[:HAS_STOCK]->(:UnitsInStock {UnitesInStock: ""}),
(n13)-[:HAS__SHIPPMENT_ADDRESS]->(a)<-[:HAS_ADDRESS]-(n6)-[:HAS_CONTACT]->(n8),
(:ProductStatus_DiscontinueD {Name: "Discontinued"})-[:HAS {RelType: "IS_DISCONTINUED"}]->(n7)<-[:HAS {RelType: "IS_AVAILABLE"}]-(:ProductStatus_AvailablE {Name: "Available"}),
(:OrderStatus_OpeN {Status: "Open"})-[:HAS {RelType: "IS_OPEN"}]->(n11)-[:HAS_PRODUCT {Quantity: "", UnitPrice: "", Discount: ""}]->(n7)-[:HAS_BACKORDER]->(:SupplyOrder {UnitsOrdered: "", OrderDate: ""}),
(n10)-[:HAS_ADDRESS]->(a),
(:Region {RegionID: "", RegionDescription: ""})-[:HAS {RelType: "HAS_TERRITORY"}]->(n18),
(:OrderStatus_FulfilleD {Status: "Fulfilled"})-[:HAS {RelType: "IS_FULFILLED"}]->(n11)-[:SOLD_BY]->(n0),
(:RoleS {Name: "RoleS"})-[:HAS {RelType: "HAS_ROLES"}]->(:RolE {Title: ""})-[:HAS {RelType: "IS_ROLE"}]->(n0);

MATCH n=()-[]-()-[ ]-( ) RETURN n;