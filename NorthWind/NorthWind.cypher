// -- NorthWind Graph Data Model Import --//

// This script will create the NorthWind Graph Data Model in Neo4j
// It will load data from CSV files and create Nodes, Relationships, Indexes, and Constraints    
// Use the CSV provided in the import folder, as it has been fixed. 
// The original CSV files from NorthWind have some issues with commas in the data fields. Mainly in the Address (for Brazil, France, and Belgium) and some Description fields (Notes).
// This causes problems when importing the data, leading to misplaced fields and compromising data integrity.

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
CREATE CONSTRAINT Territories_TerritoryID IF NOT EXISTS FOR (t:Territory) REQUIRE (t.TerritoryID) IS UNIQUE;
CREATE CONSTRAINT Regions_RegionID IF NOT EXISTS FOR (r:Regions) REQUIRE (r.RegionID) IS UNIQUE;
CREATE CONSTRAINT Shipper_ShipperID IF NOT EXISTS FOR (s:Shipper) REQUIRE (s.ShipperID) IS UNIQUE;

// https://github.com/Flyer-Boy/NewApproach/blob/main/NorthWind/Import/categories.csv

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
MERGE (n:Territory {TerritoryID:row.TerritoryID})
SET n += row;

LOAD CSV WITH HEADERS FROM "file:///regions.csv" AS row
MERGE (n:Regions {RegionID:row.RegionID})
SET n += row;

LOAD CSV WITH HEADERS FROM "file:///employee-territories.csv" AS row
MATCH (e:Employee), (t:Territory)
WHERE e.EmployeeID = row.EmployeeID AND t.TerritoryID = row.TerritoryID
MERGE (t)-[:HAS {RelType: "HAS_EMPLOYEE"}]->(e);

MATCH (t:Territory), (r:Regions)
WHERE t.RegionID = r.RegionID
MERGE (r)-[:HAS {RelType: "HAS_TERRITORY"}]->(t);

MATCH (t:Territory) REMOVE t.RegionID;

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
CREATE (i)-[:HAS_SHIPPMENT_ADDRESS]->(s)
WITH n, i
MATCH (a:Address) WHERE a.Address = n.ShipAddress AND a.City = n.ShipCity AND a.Region = n.ShipRegion AND a.PostalCode = n.ShipPostalCode AND a.Country = n.ShipCountry
MERGE (i)-[:HAS_SHIPPMENT_ADDRESS]->(a)
WITH n, i
WHERE NOT EXISTS( (i)-[:HAS_ADDRESS]->(:Address {Address:n.ShipAddress, City:n.ShipCity, Region:n.ShipRegion, PostalCode:n.ShipPostalCode, Country:n.ShipCountry}) ) 
CREATE (a:Address {Address:n.ShipAddress, City:n.ShipCity, Region:n.ShipRegion, PostalCode:n.ShipPostalCode, Country:n.ShipCountry})
CREATE (i)-[:HAS_SHIPPMENT_ADDRESS]->(a);

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


// Queries Examples to run against the NorthWind Graph Data Model 
// These are examples of queries that could be used to extract insights from the NorthWind Graph Data Model.


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
MATCH (r:Regions)-[:HAS]->(t:Territory)-[:HAS]->(e:Employee)<-[:SOLD_BY]-(o:Order)-[details:HAS_PRODUCT]->(p:Product)
RETURN r.RegionID, r.RegionDescription, SUM( (details.Quantity * details.UnitPrice) ) AS TotalSales
ORDER BY TotalSales DESC;

// Total Sales by Region and Territory
MATCH (r:Regions)-[:HAS]->(t:Territory)-[:HAS]->(e:Employee)<-[:SOLD_BY]-(o:Order)-[details:HAS_PRODUCT]->(p:Product)
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

// Top 5 Products by Number of Orders
MATCH (c:Customer)<-[:HAS_CUSTOMER]-(o:Order)-[:HAS_PRODUCT]->(p:Product)
RETURN c.CompanyName, p.ProductName, count(o) AS orders
ORDER BY orders DESC
LIMIT 5;

// Product recomendaton for Customers based on most ordered Products by another Customers
MATCH (c:Customer)<-[:HAS_CUSTOMER]-(o:Order)-[:HAS_PRODUCT]->(p:Product)
<-[:HAS_PRODUCT]-(o2:Order)-[:HAS_PRODUCT]->(p2:Product)<-[:HAS]-(:CategorY)-[:HAS]->(p)
WHERE c.CustomerID = 'ANTON' and NOT( (c)<-[:HAS_CUSTOMER]-(:Order)-[:HAS_PRODUCT]->(p2) )
RETURN c.CompanyName, p.ProductName AS has_purchased, p2.ProductName AS has_also_purchased, count(DISTINCT o2) AS occurrences
ORDER BY occurrences DESC
LIMIT 5;


//  End of Query Examples  //

//  -------------------------------------------------------------------   //

// Recommendation Engine as per: https://neo4j.com/graphgists/northwind-recommendation-engine/ adaped for NorthWind Application Graph Data Model (and Cypher Version 5)

// Collaborative Filtering - Product Rating by Customers 
// Collaborative Filtering is a technique used by recommendation engines to recommend content based on the feedback from other Customers. 
// To do this, we can use the k-NN (k-nearest neighbors) Algorithm. k-N works by grouping items into classifications based on their similarity to eachother. 
// In our case, this could be ratings between two Customers for a Product. 
// To give a real world example, this is how sites like Netflix make recommendations based on the ratings given to shows you’ve already watched.

// The first thing we need to do to make this model work is create some "ratings relationships". 
// For now, let’s create a score somewhere between 0 and 1 for each product based on the number of times a customer has purchased a product.

MATCH (c:Customer)-[:PURCHASED]->(o:Order)-[:PRODUCT]->(p:Product)
WITH c, count(p) AS total
MATCH (c)-[:PURCHASED]->(o:Order)-[:PRODUCT]->(p:Product)
WITH c, total,p, count(o)*1.0 AS orders
MERGE (c)-[rated:RATED]->(p)
ON CREATE SET rated.rating = orders/total
ON MATCH SET rated.rating = orders/total
WITH c.companyName AS company, p.productName AS product, orders, total, rated.rating AS rating
ORDER BY rating DESC
RETURN company, product, orders, total, rating LIMIT 10; 

// Now that we have ratings between Customers and Products, we can start to find similarities between Customers based on their ratings.

// See Customer's Ratings
MATCH (me:Customer)-[r:RATED]->(p:Product)
WHERE me.CustomerID = 'ANTON'
RETURN p.ProductName, r.Rating limit 10;

// See Customer's Similar Ratings to Others
MATCH (c1:Customer {CustomerID:'ANTON'})-[r1:RATED]->(p:Product)<-[r2:RATED]-(c2:Customer)
RETURN c1.CustomerID, c2.CustomerID, p.ProductName, r1.Rating, r2.Rating,
CASE WHEN r1.Rating-r2.Rating < 0 THEN -(r1.Rating-r2.Rating) ELSE r1.Rating-r2.Rating END as difference
ORDER BY difference ASC
LIMIT 15; 

// Now we can calculate the similarity between Customers based on their ratings using Cosine Similarity.
// We can create a similarity score between two Customers using Cosine Similarity  
MATCH (c1:Customer)-[r1:RATED]->(p:Product)<-[r2:RATED]-(c2:Customer)
WITH
	SUM(r1.rating*r2.rating) as dot_product,
	SQRT( REDUCE(x=0.0, a IN COLLECT(r1.Rating) | x + a^2) ) as r1_length,
	SQRT( REDUCE(y=0.0, b IN COLLECT(r2.Rating) | y + b^2) ) as r2_length,
	c1,c2
MERGE (c1)-[s:SIMILARITY]-(c2)
SET s.Similarity = dot_product / (r1_length * r2_length); 

// Now we can use the similarity scores to recommend Products to Customers based on what similar Customers have rated highly.
MATCH (me:Customer)-[r:SIMILARITY]->(them)
WHERE me.CustomerID='ANTON'
RETURN me.CompanyName, them.CompanyName, r.Similarity
ORDER BY r.Similarity DESC limit 10;

// Finally, we can use the similarity scores to recommend Products to a Customer based on what similar Customers have rated highly.
MATCH (me:Customer)-[:SIMILARITY]->(c:Customer)-[r:RATED]->(p:Product)
WHERE me.CustomerID = 'ANTON' and NOT ( (me)-[:RATED*1..2]->(p:Product) )
WITH p, COLLECT(r.Rating)[0..1] as ratings, collect(c.CompanyName)[0..1] as customers
WITH p, customers, round(REDUCE(s=0,i in ratings | s+i) / size(ratings), 5)  as recommendation
ORDER BY recommendation DESC
RETURN p.ProductName, customers, recommendation LIMIT 25;


// -------------------------------------------------------------------   //

// Application Query Examples
// These are examples of queries that could be used in an Application built on top of the NorthWind Graph Data Model.
// These queries demonstrate how to create a new Order, check inventory levels, fulfill an Order, and update inventory levels accordingly.
// We will add an "N" prefix to new OrderIDs to differentiate them from imported Orders, so we can test the Application Queries without interfering with the imported data.

// Creating a New Order:
MATCH (c:Customer {CustomerID:"ALFKI"}), (e:Employee {EmployeeID:"5"}), (p1:Product {ProductID:"1"}), (p2:Product {ProductID:"2"}), (p:OrderStatus_OpeN {Status: "Open"})
CREATE (o:Order {OrderID:"N10000", OrderDate:date(), RequireDate:date()+duration("P7D")})<-[:HAS {RelType: "IS_OPEN"}]-(p)
CREATE (o)-[:HAS_CUSTOMER]->(c) 
CREATE (o)-[:SOLD_BY]->(e)
CREATE (o)-[:HAS_PRODUCT {Quantity:10, UnitPrice:p1.UnitPrice, Discount:0.0}]->(p1)
CREATE (o)-[:HAS_PRODUCT {Quantity:5, UnitPrice:p2.UnitPrice, Discount:0.1}]->(p2)
RETURN o;

// Checking Inventory before Fulfilling an Order:
MATCH (o:Order {OrderID:"N10000"})-[r:HAS_PRODUCT]->(p:Product)-[:CURRENT_STOCK]->(s:InventoryLevel)
RETURN p.ProductName, r.Quantity AS QuantityOrdered, s.UnitsInStock AS CurrentStock;

// Fulfilling an Order (with the assumption that the Shippment Address is the same as the Customer Address, as in the original NorthWind Data Model import files):
MATCH (o:Order {OrderID:"N10000"})<-[r:HAS]-(p:OrderStatus_OpeN {Status: "Open"}), (o)-[:HAS_CUSTOMER]-()-[:HAS_ADDRESS]-(a), (s:Shipper {ShipperID:"1"}), (f:OrderStatus_FulfilleD {Status: "Fulfilled"})
CREATE (i:ShipInfo {ShippmentID:apoc.create.uuid(), ShippedDate:date()})
CREATE (o)-[:HAS_SHIPMENT]->(i)
CREATE (i)-[:HAS_SHIPPER]->(s)
CREATE (f)-[:HAS {RelType: "IS_FULFILLED"}]->(o)
CREATE (i)-[:HAS_SHIPPMENT_ADDRESS]->(a)
DELETE r
RETURN o, i, s;

// Checking Inventory before Updating it after Order Fulfillment:
MATCH n=(o:Order {OrderID: "N10000"})-[]->()-[:CURRENT_STOCK]->() RETURN n;

// Updating Inventory after Order Fulfillment:
MATCH (o:Order {OrderID:"N10000"})-[r:HAS_PRODUCT]->(p:Product)-[:CURRENT_STOCK]->(s:InventoryLevel)
SET s.UnitsInStock = s.UnitsInStock - r.Quantity
RETURN p.ProductName, s.UnitsInStock;

// Add a new Customer with Address and Contact details:
CREATE (c:Customer {CustomerID:"NEWC1", CompanyName:"New Customer Inc.", ContactName:"John Doe", ContactTitle:"Purchasing Manager"})
CREATE (a:Address {Address:"123 New St", City:"New City", Region:"NC", PostalCode:"12345", Country:"USA"})
CREATE (contact:Contact {ContactName:"John Doe", ContactTitle:"Purchasing Manager", Phone:"555-1234", Email:"John.Doe@NewCustomer.com"})
CREATE (c)-[:HAS_ADDRESS]->(a)
CREATE (c)-[:HAS_CONTACT]->(contact)
RETURN c, a, contact;

// Add a new Product, link it to a Category and Supplier, set its initial Inventory Level, and mark it as Available:
MATCH (cat:CategorY {CategoryID:"7"}), (sup:Supplier {SupplierID:"6"}), (avail:ProductStatus_AvailablE {Status: "Available"})
CREATE (p:Product {ProductID:"999", ProductName:"New Product", QuantityPerUnit:"1 box", UnitPrice:19.99, ReorderLevel:30})
CREATE (i:InventoryLevel {UnitsInStock:100})
CREATE (p)-[:CURRENT_STOCK]->(i)
CREATE (cat)-[:HAS {RelType: "HAS_PRODUCT"}]->(p)
CREATE (p)-[:HAS_SUPPLIER]->(sup)
CREATE (sup)-[:SUPPLIES]->(p)
CREATE (avail)-[:HAS {RelType: "IS_AVAILABLE"}]->(p)
RETURN p, i;
