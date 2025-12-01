// -- NorthWind Graph Data Model Import --//

// This script will create the NorthWind Graph Data Model in Neo4j
// It will load data from CSV files and create Nodes, Relationships, Indexes and Constraints    
// Use the csv provied in the import folder as they have been fixed. 

// Lets Clear all Nodes and Relationships before we start 
MATCH (n) DETACH DELETE n;

DROP CONSTRAINT Product_ProductID IF EXISTS;
DROP CONSTRAINT Category_CategoryID IF EXISTS;
DROP CONSTRAINT Supplier_SupplierID IF EXISTS;
DROP CONSTRAINT Customer_CustomerID IF EXISTS;
DROP CONSTRAINT Order_OrderID IF EXISTS;
DROP CONSTRAINT Employee_EmployeeID IF EXISTS;
DROP CONSTRAINT Territories_TerritoryID IF EXISTS;
DROP CONSTRAINT Regions_RegionID IF EXISTS;
DROP CONSTRAINT Shipper_ShipperID IF EXISTS;



//---- Indexes and Constraints --//
CREATE CONSTRAINT Product_ProductID IF NOT EXISTS FOR (p:Product) REQUIRE (p.ProductID) IS UNIQUE;
CREATE CONSTRAINT Category_CategoryID IF NOT EXISTS FOR (c:Category) REQUIRE (c.CategoryID) IS UNIQUE;
CREATE CONSTRAINT Supplier_SupplierID IF NOT EXISTS FOR (s:Supplier) REQUIRE (s.SupplierID) IS UNIQUE;
CREATE CONSTRAINT Customer_CustomerID IF NOT EXISTS FOR (c:Customer) REQUIRE (c.CustomerID) IS UNIQUE;
CREATE CONSTRAINT Order_OrderID IF NOT EXISTS FOR (o:Order) REQUIRE (o.OrderID) IS UNIQUE;
CREATE CONSTRAINT Employee_EmployeeID IF NOT EXISTS FOR (e:Employee) REQUIRE (e.EmployeeID) IS UNIQUE;
CREATE CONSTRAINT Territories_TerritoryID IF NOT EXISTS FOR (t:Territories) REQUIRE (t.TerritoryID) IS UNIQUE;
CREATE CONSTRAINT Regions_RegionID IF NOT EXISTS FOR (r:Regions) REQUIRE (r.RegionID) IS UNIQUE;
CREATE CONSTRAINT Shipper_ShipperID IF NOT EXISTS FOR (s:Shipper) REQUIRE (s.ShipperID) IS UNIQUE;


LOAD CSV WITH HEADERS FROM "file:///categories.csv" AS row
MERGE (n:CategorY {CategoryID:row.CategoryID, CategoryName:row.CategoryName, Description:row.Description}); 

LOAD CSV WITH HEADERS FROM "file:///suppliers.csv" AS row
MERGE (n:Supplier {SupplierID:row.SupplierID, CompanyName:row.CompanyName, ContactName:row.ContactName, ContactTitle:row.ContactTitle, Address:row.Address, City:row.City, Region:row.Region, PostalCode:row.PostalCode, Country:row.Country, Phone:row.Phone, Fax:row.Fax, HomePage:"https://www." + replace(replace(replace(row.CompanyName," ",""),"'",""),".","") + ".com"});

MATCH (n:Supplier)
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Contact {ContactName:n.ContactName, ContactTitle:n.ContactTitle, Phone:n.Phone, Fax:n.Fax, Email: replace(n.ContactName, " ", ".") +"@" + replace(replace(replace(n.CompanyName," ",""),"'",""),".","") + ".com"})
CREATE (n)-[:HAS_ADDRESS]->(a)
CREATE (n)-[:HAS_CONTACT]->(c);

CREATE (:CategorieS {Name: "CategorieS"});
CREATE (:ProductStatus_DiscontinueD {Status: "Discontinued"}); 
CREATE (:ProductStatus_AvailablE {Status: "Available"}); 

LOAD CSV WITH HEADERS FROM "file:///products.csv" AS row
MERGE (n:Product {ProductID:row.ProductID, ProductName:row.ProductName, UnitPrice:toFloat(row.UnitPrice), ReorderLevel:toInteger(row.ReorderLevel), QuantityPerUnit:row.QuantityPerUnit, Discontinued:toInteger(row.Discontinued), SupplierID:row.SupplierID})
CREATE (i:InventoryLevel {UnitsInStock:toInteger(row.UnitsInStock)})
CREATE (n)-[:CURRENT_STOCK]->(i)
WITH n, row
MATCH (c:CategorY) WHERE c.CategoryID = row.CategoryID
MERGE (c)-[:HAS {RelType: "HAS_PRODUCT"}]->(n);

MATCH (d:ProductStatus_DiscontinueD {Status: "Discontinued"}), (n:Product)
WHERE n.Discontinued = 1
MERGE (d)-[:HAS {RelType: "IS_DISCONTINUED"}]->(n);

MATCH (a:ProductStatus_AvailablE {Status: "Available"}), (n:Product)
WHERE n.Discontinued = 0 
MERGE (a)-[:HAS {RelType: "IS_AVAILABLE"}]->(n);

MATCH (n:Product)
REMOVE n.Discontinued;

MATCH (s:Supplier), (p:Product)
WHERE s.SupplierID = p.SupplierID 
MERGE (p)-[:HAS_SUPPLIER]->(s)
MERGE (s)-[:SUPPLIES]->(p);

MATCH (s:Supplier)
REMOVE s.ContactName, s.ContactTitle, s.Address, s.City, s.Region, s.PostalCode, s.Country, s.Phone, s.Fax;

MATCH (k:CategorieS {Name: "CategorieS"}), (c:CategorY)
MERGE (k)-[:HAS {RelType: "HAS_CATEGORY"}]->(c);

LOAD CSV WITH HEADERS FROM "file:///customers.csv" AS row
MERGE (n:Customer {CustomerID:row.CustomerID})
SET n += row;

MATCH (n:Customer)
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Contact {ContactName:n.ContactName, ContactTitle:n.ContactTitle, Phone:n.Phone, Fax:n.Fax, Email:" "})
CREATE (n)-[:HAS_ADDRESS]->(a) 
CREATE (n)-[:HAS_CONTACT]->(c);

MATCH (n:Customer)
REMOVE n.Address, n.City, n.Region, n.PostalCode, n.Country, n.ContactName, n.ContactTitle, n.Phone, n.Fax; 

CREATE (:RoleS {Name: "RoleS"});

LOAD CSV WITH HEADERS FROM "file:///employees.csv" AS row
MERGE (l:RolE {Title:row.Title}) 
WITH l
MATCH (r:RoleS)
MERGE (r)-[:HAS {RelType: "HAS_ROLE"}]->(l);

LOAD CSV WITH HEADERS FROM "file:///employees.csv" AS row
MERGE (n:Employee {EmployeeID:row.EmployeeID, Email: row.FirstName + "." + row.LastName + "@northwind.com"}) 
SET n += row
WITH n, row 
MATCH (l:RolE {Title: n.Title})
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Person {FirstName:row.FirstName, LastName: row.LastName, TitleOfCourtesy: row.TitleOfCourtesy, BirthDate: row.BirthDate, PersonalPhone:n.HomePhone, PersonalEmail: row.FirstName + "." + row.LastName + "@outlook.com"})
CREATE (o:Notes {Notes:n.Notes})
MERGE (l)-[:HAS {RelType: "IS_ROLE"}]->(n)
CREATE (n)-[:HAS_ADDRESS]->(a)
CREATE (n)-[:HAS_PERSON]->(c)
CREATE (n)-[:HAS_NOTES]->(o);

MATCH (n:Employee)
WHERE n.ReportsTo IS NOT NULL
MATCH (m:Employee)
WHERE n.ReportsTo = m.EmployeeID 
MERGE (n)-[:REPORTS_TO]->(m);

MATCH (n:Employee)
REMOVE n.FirstName, n.LastName, n.TitleOfCourtesy,n.BithdDate, n.Address, n.City, n.Region, n.PostalCode, n.Country, n.HomePhone, n.Fax, n.Notes, n.Photo, n.ReportsTo, n.Title; 

LOAD CSV WITH HEADERS FROM "file:///territories.csv" AS row
MERGE (n:Territories {TerritoryID:row.TerritoryID})
SET n += row;

LOAD CSV WITH HEADERS FROM "file:///regions.csv" AS row
MERGE (n:Regions {RegionID:row.RegionID})
SET n += row;

LOAD CSV WITH HEADERS FROM "file:///employee-territories.csv" AS row
MATCH (e:Employee), (t:Territories)
WHERE e.EmployeeID = row.EmployeeID AND t.TerritoryID = row.TerritoryID
MERGE (t)-[:HAS {RelType: "HAS_EMPLOYEE"}]->(e);

MATCH (t:Territories), (r:Regions)
WHERE t.RegionID = r.RegionID
MERGE (r)-[:HAS {RelType: "HAS_TERRITORY"}]->(t);

MATCH (t:Territories) REMOVE t.RegionID;

LOAD CSV WITH HEADERS FROM "file:///shippers.csv" AS row
MERGE (n:Shipper {ShipperID:row.ShipperID, CompanyName:row.CompanyName, Phone:row.Phone});


LOAD CSV WITH HEADERS FROM "file:///orders.csv" AS row
MERGE (n:Order {OrderID:row.OrderID})
SET n += row;

MATCH (c:Customer),(o:Order)
WHERE c.CustomerID = o.CustomerID
MERGE (o)-[:HAS_CUSTOMER]->(c);

MATCH (n:Order), (s:Shipper)
WHERE n.ShipVia = s.ShipperID 
CREATE (n)-[:HAS_SHIPMENT]->(i:ShipInfo {ShipName:n.ShipName, ShippedDate:n.ShippedDate, Freight:n.Freight })
CREATE (i)-[:HAS_SHIPPER]->(s)
WITH n, i
MATCH (a:Address) WHERE a.Address = n.ShipAddress AND a.City = n.ShipCity AND a.Region = n.ShipRegion AND a.PostalCode = n.ShipPostalCode AND a.Country = n.ShipCountry
MERGE (i)-[:HAS_ADDRESS]->(a)
WITH n, i
WHERE NOT EXISTS( (i)-[:HAS_ADDRESS]->(:Address {Address:n.ShipAddress, City:n.ShipCity, Region:n.ShipRegion, PostalCode:n.ShipPostalCode, Country:n.ShipCountry}) ) 
CREATE (a:Address {Address:n.ShipAddress, City:n.ShipCity, Region:n.ShipRegion, PostalCode:n.ShipPostalCode, Country:n.ShipCountry})
CREATE (i)-[:HAS_ADDRESS]->(a);

MATCH (e:Employee), (o:Order)
WHERE e.EmployeeID = o.EmployeeID 
MERGE (o)-[:SOLD_BY]->(e);

MATCH (n:Order)
REMOVE n.CustomerID, n.ShipVia, n.ShipName, n.ShipAddress, n.ShipCity, n.ShipRegion, n.ShipPostalCode, n.ShipCountry, n.Freight, n.ShippedDate, n.EmployeeID;

//-- Includong Order Details on the Relationship --//

LOAD CSV WITH HEADERS FROM "file:///order-details.csv" AS row
MATCH (p:Product), (o:Order)
WHERE p.ProductID = row.ProductID AND o.OrderID = row.OrderID 
MERGE (o)-[details:HAS_PRODUCT]->(p)
SET details.Quantity = toInteger(row.Quantity), details.UnitPrice = toFloat(row.UnitPrice), details.Discount = toFloat(row.Discount); 


CREATE (:OrderStatus_OpeN {Status: "Open"});
CREATE (:OrderStatus_FulfilleD {Status: "Fulfilled"});

MATCH (f:OrderStatus_FulfilleD {Status: "Fulfilled"}), (n:Order)-[:HAS_SHIPMENT]->(s:ShipInfo)
WHERE s.ShippedDate IS NOT NULL
CREATE (f)-[:HAS {RelType: "IS_FULFILLED"}]->(n); 

MATCH (o:OrderStatus_OpeN {Status: "Open"}), (n:Order)-[:HAS_SHIPMENT]->(s:ShipInfo)
WHERE s.ShippedDate IS NULL 
CREATE (o)-[:HAS {RelType: "IS_OPEN"}]->(n);



//-- End of NorthWind Graph Data Model Import --//


//  -------------------------------------------------------------------   //


// Queries Examples


// Total Amount of OrderID 10461
MATCH (o:Order {OrderID:"10461"})-[r:HAS_PRODUCT]->(p:Product)
RETURN o.OrderID, SUM(r.Quantity * r.UnitPrice) AS TotalAmmountOrder;

// Total Amount of OrderID 10461 broken down by Product
MATCH (o:Order {OrderID:"10461"})-[r:HAS_PRODUCT]->(p:Product)
RETURN o.OrderID, p.ProductName, r.Quantity , r.UnitPrice, r.Quantity * r.UnitPrice AS AmmountByProduct
ORDER BY AmmountByProduct DESC;

// Top 25 Orders by Total Amount
MATCH (o:Order)-[r:HAS_PRODUCT]->(p:Product)
RETURN o.OrderID, SUM(r.Quantity * r.UnitPrice) AS TotalAmmountOrder 
ORDER BY TotalAmmountOrder DESC
LIMIT 25;

// Top 5 Customers by Number of Orders
MATCH (c:Customer)<-[:HAS_CUSTOMER]-(o:Order)
RETURN c.CustomerID, COUNT(o) AS NumberOfOrders
ORDER BY NumberOfOrders DESC
LIMIT 10;

// Top 5 Employees by Number of Orders Sold
MATCH (e:Employee)<-[:SOLD_BY]-(o:Order)
RETURN e.EmployeeID, e.FirstName, e.LastName, COUNT(o) AS NumberOfOrdersSold
ORDER BY NumberOfOrdersSold DESC
LIMIT 10;

// Total Sales by Region
MATCH (r:Regions)-[:HAS]->(t:Territories)-[:HAS]->(e:Employee)<-[:SOLD_BY]-(o:Order)-[details:HAS_PRODUCT]->(p:Product)
RETURN r.RegionID, r.RegionDescription, SUM( (details.Quantity * details.UnitPrice) ) AS TotalSales
ORDER BY TotalSales DESC;

// Total Sales by Region and Territory
MATCH (r:Regions)-[:HAS]->(t:Territories)-[:HAS]->(e:Employee)<-[:SOLD_BY]-(o:Order)-[details:HAS_PRODUCT]->(p:Product)
RETURN r.RegionID, r.RegionDescription, t.TerritoryDescription, SUM( (details.Quantity * details.UnitPrice) ) AS TotalSales
ORDER BY TotalSales DESC;


// Total Sales by Category
MATCH (cat:CategorY)-[:HAS {RelType: "HAS_PRODUCT"}]->(p:Product)<- [details:HAS_PRODUCT]-(o:Order)
RETURN cat.CategoryName, SUM( (details.Quantity * details.UnitPrice) ) AS TotalSales
ORDER BY TotalSales DESC;

// Total Sales by Employee
MATCH (e:Employee)<-[:SOLD_BY]-(o:Order)-[details:HAS_PRODUCT]->(p:Product)
RETURN e.EmployeeID, e.FirstName, e.LastName, SUM( (details.Quantity * details.UnitPrice) ) AS TotalSales
ORDER BY TotalSales DESC;

// Total Product Orders and Stock available
MATCH (p:Product)-[:CURRENT_STOCK]->(s:InventoryLevel), (o:Order)-[details:HAS_PRODUCT]->(p)
RETURN p.ProductID, p.ProductName, SUM(details.Quantity) AS TotalOrdered, s.UnitsInStock AS StockAvailable
ORDER BY TotalOrdered DESC;

//  End of Query Examples  //



