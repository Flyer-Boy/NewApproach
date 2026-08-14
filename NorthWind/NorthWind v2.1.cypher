// -- NorthWind Graph Data Model Import v2.1 --//

// This v2 introduces changes of truly *ontological* proportions.

// Previously, I used a single generic relationship type [:HAS] for all elements
// belonging to a collection (“Hub nodes” that aggregate nodes of a given Label
// based on their State or Context), mainly to preserve UI reusability.

// To maintain some level of Ontology, I added a property called RelType on the
// relationship/edge to indicate its intended ontological meaning.

// This was a conscious trade-off: it kept the UI simple, but it negatively
// affected edge indexing and would eventually harm performance at scale.

// In v2, I removed the common [:HAS] relationship type entirely and adopted
// proper ontology-specific relationship types. This restores semantic clarity
// and improves indexing behavior for large-scale graphs.

// As for UI reusability, I will rely on the naming convention I use to
// distinguish Nodes from Collection Nodes (both start and end with capital letters).

// ------------------------------------------------------------------------------------ //


// This script will create the NorthWind Graph Data Model in Neo4j
// It will load data from CSV files and create Nodes, Relationships, Indexes, and Constraints    
// Use the CSV provided in the import folder, as it has been fixed. 
// The original CSV files from NorthWind have some issues with commas in the data fields. Mainly in the Address (for Brazil, France, and Belgium) and some Description fields (Notes).
// This causes problems when importing the data, leading to misplaced fields and compromising data integrity.

// Lets Clear all Nodes and Relationships before we start 
MATCH (n) DETACH DELETE n;

//-- Loading Data from CSV files --//
LOAD CSV WITH HEADERS FROM "file:///categories.csv" AS row
MERGE (n:ProductCategorY {CategoryID:row.CategoryID, CategoryName:row.CategoryName, Description:row.Description}); 

LOAD CSV WITH HEADERS FROM "file:///suppliers.csv" AS row
MERGE (n:Supplier {SupplierID:row.SupplierID, CompanyName:row.CompanyName, ContactName:row.ContactName, ContactTitle:row.ContactTitle, Address:row.Address, City:row.City, Region:row.Region, PostalCode:row.PostalCode, Country:row.Country, Phone:row.Phone, Fax:row.Fax, HomePage:"https://www." + replace(replace(replace(row.CompanyName," ",""),"'",""),".","") + ".com"});

MATCH (n:Supplier)
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Contact {ContactName:n.ContactName, ContactTitle:n.ContactTitle, Phone:n.Phone, Fax:n.Fax, Email: replace(n.ContactName, " ", ".") +"@" + replace(replace(replace(n.CompanyName," ",""),"'",""),".","") + ".com"})
CREATE (n)-[:HAS_SUPPLIER_ADDRESS]->(a)
CREATE (n)-[:HAS_SUPPLIER_CONTACT]->(c);

CREATE (:CategorieS {Name: "CategorieS"});
CREATE (:ProductStatusDiscontinueD {Status: "Discontinued"}); 
CREATE (:ProductStatusAvailablE {Status: "Available"}); 

LOAD CSV WITH HEADERS FROM "file:///products.csv" AS row
MERGE (n:Product {ProductID:row.ProductID, ProductName:row.ProductName, UnitPrice:toFloat(row.UnitPrice), ReorderLevel:toInteger(row.ReorderLevel), QuantityPerUnit:row.QuantityPerUnit, Discontinued:toInteger(row.Discontinued), SupplierID:row.SupplierID})
CREATE (i:InventoryLevel {UnitsInStock:toInteger(row.UnitsInStock), LastUpdate: datetime()})
CREATE (onorder:OrderLevel {UnitsOnOrder:toInteger(row.UnitsOnOrder), LastUpdate: datetime()})
CREATE (n)-[:HAS_SUPPLY_ORDER]->(onorder)
CREATE (n)-[:HAS_CURRENT_STOCK]->(i)
WITH n, row
MATCH (c:ProductCategorY) WHERE c.CategoryID = row.CategoryID
MERGE (c)-[:IS_PRODUCT_CATEGORY_OF]->(n);

MATCH (d:ProductStatusDiscontinueD {Status: "Discontinued"}), (n:Product)
WHERE n.Discontinued = 1
MERGE (d)-[:IS_DISCONTINUED_PRODUCT]->(n);

MATCH (a:ProductStatusAvailablE {Status: "Available"}), (n:Product)
WHERE n.Discontinued = 0 
MERGE (a)-[:IS_AVAILABLE_PRODUCT]->(n);

MATCH (n:Product)
REMOVE n.Discontinued;

MATCH (s:Supplier), (p:Product)
WHERE s.SupplierID = p.SupplierID 
MERGE (p)-[:HAS_PRODUCT_SUPPLIER]->(s)
MERGE (s)-[:SUPPLIES]->(p);

MATCH (n:Product)
REMOVE n.SupplierID;

MATCH (s:Supplier)
REMOVE s.ContactName, s.ContactTitle, s.Address, s.City, s.Region, s.PostalCode, s.Country, s.Phone, s.Fax;

MATCH (k:CategorieS {Name: "CategorieS"}), (c:ProductCategorY)
MERGE (k)-[:HAS_CATEGORY]->(c);

LOAD CSV WITH HEADERS FROM "file:///customers.csv" AS row
MERGE (n:Customer {CustomerID:row.CustomerID})
SET n += row;

MATCH (n:Customer)
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Contact {ContactName:n.ContactName, ContactTitle:n.ContactTitle, Phone:n.Phone, Fax:n.Fax, Email: replace(n.ContactName, " ", ".") +"@" + replace(replace(replace(n.CompanyName," ",""),"'",""),".","") + ".com"})
CREATE (n)-[:HAS_CUSTOMER_ADDRESS]->(a) 
CREATE (n)-[:HAS_CUSTOMER_CONTACT]->(c);

MATCH (n:Customer)
REMOVE n.Address, n.City, n.Region, n.PostalCode, n.Country, n.ContactName, n.ContactTitle, n.Phone, n.Fax; 

CREATE (:RoleS {Name: "RoleS"});

LOAD CSV WITH HEADERS FROM "file:///employees.csv" AS row
MERGE (l:RolE {Title:row.Title}) 
WITH l
MATCH (r:RoleS)
MERGE (r)-[:HAS_ROLE_TITLE]->(l);

LOAD CSV WITH HEADERS FROM "file:///employees.csv" AS row
MERGE (n:Employee {EmployeeID:row.EmployeeID, Email: row.FirstName + "." + row.LastName + "@northwind.com"}) 
SET n += row
WITH n, row 
MATCH (l:RolE {Title: n.Title})
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Person {FirstName:row.FirstName, LastName: row.LastName, TitleOfCourtesy: row.TitleOfCourtesy, BirthDate: row.BirthDate, PersonalPhone:n.HomePhone, PersonalEmail: row.FirstName + "." + row.LastName + "@outlook.com"})
CREATE (o:Notes {Notes:n.Notes})
MERGE (l)-[:IS_ACTIVE_ROLE {StartDate: datetime()}]->(n)
CREATE (n)-[:HAS_PERSON]->(c)
CREATE (c)-[:HAS_HOME_ADDRESS]->(a)
CREATE (n)-[:HAS_EMPLOYEE_NOTES]->(o);

MATCH (n:Employee)
WHERE n.ReportsTo IS NOT NULL
MATCH (m:Employee)
WHERE n.ReportsTo = m.EmployeeID 
MERGE (n)-[:REPORTS_TO]->(m);

MATCH (n:Employee)
REMOVE n.FirstName, n.LastName, n.TitleOfCourtesy, n.BirthDate, n.Address, n.City, n.Region, n.PostalCode, n.Country, n.HomePhone, n.Fax, n.Notes, n.Photo, n.ReportsTo, n.Title; 

LOAD CSV WITH HEADERS FROM "file:///territories.csv" AS row
MERGE (n:Territory {TerritoryID:row.TerritoryID})
SET n += row;

LOAD CSV WITH HEADERS FROM "file:///regions.csv" AS row
MERGE (n:Regions {RegionID:row.RegionID})
SET n += row;

LOAD CSV WITH HEADERS FROM "file:///employee-territories.csv" AS row
MATCH (e:Employee), (t:Territory)
WHERE e.EmployeeID = row.EmployeeID AND t.TerritoryID = row.TerritoryID
MERGE (t)-[:HAS_EMPLOYEE]->(e);

MATCH (t:Territory), (r:Regions)
WHERE t.RegionID = r.RegionID
MERGE (r)-[:HAS_TERRITORY]->(t);

MATCH (t:Territory) REMOVE t.RegionID;

LOAD CSV WITH HEADERS FROM "file:///shippers.csv" AS row
MERGE (n:Shipper {ShipperID:row.ShipperID, CompanyName:row.CompanyName, Phone:row.Phone});


LOAD CSV WITH HEADERS FROM "file:///orders.csv" AS row
MERGE (n:Order {OrderID:row.OrderID})
SET n += row;

MATCH (c:Customer),(o:Order)
WHERE c.CustomerID = o.CustomerID
MERGE (o)-[:HAS_ORDER_CUSTOMER]->(c);

MATCH (n:Order), (s:Shipper)
WHERE n.ShipVia = s.ShipperID 
CREATE (n)-[:HAS_SHIPMENT_INFO]->(i:ShipInfo {ShipName:n.ShipName, ShippedDate:n.ShippedDate, Freight:n.Freight })
CREATE (i)-[:HAS_SHIPPER]->(s)
WITH n, i
MATCH (a:Address) WHERE a.Address = n.ShipAddress AND a.City = n.ShipCity AND a.Region = n.ShipRegion AND a.PostalCode = n.ShipPostalCode AND a.Country = n.ShipCountry
MERGE (i)-[:HAS_SHIPMENT_ADDRESS]->(a)
WITH n, i
WHERE NOT EXISTS((i)-[:HAS_SHIPMENT_ADDRESS]->(:Address {Address:n.ShipAddress, City:n.ShipCity, Region:n.ShipRegion, PostalCode:n.ShipPostalCode, Country:n.ShipCountry}) ) 
CREATE (a:Address {Address:n.ShipAddress, City:n.ShipCity, Region:n.ShipRegion, PostalCode:n.ShipPostalCode, Country:n.ShipCountry})
CREATE (i)-[:HAS_SHIPMENT_ADDRESS]->(a);

MATCH (e:Employee), (o:Order)
WHERE e.EmployeeID = o.EmployeeID 
MERGE (o)-[:SOLD_BY]->(e);

MATCH (n:Order)
REMOVE n.CustomerID, n.ShipVia, n.ShipName, n.ShipAddress, n.ShipCity, n.ShipRegion, n.ShipPostalCode, n.ShipCountry, n.Freight, n.ShippedDate, n.EmployeeID;

//-- Including Order Details on the Relationship --//

LOAD CSV WITH HEADERS FROM "file:///order-details.csv" AS row
MATCH (p:Product), (o:Order)
WHERE p.ProductID = row.ProductID AND o.OrderID = row.OrderID 
MERGE (o)-[details:HAS_ORDER_PRODUCT]->(p)
SET details.Quantity = toInteger(row.Quantity), details.UnitPrice = toFloat(row.UnitPrice), details.Discount = toFloat(row.Discount); 


CREATE (:OrderStatusOpeN {Status: "Open"});
CREATE (:OrderStatusFulfilleD {Status: "Fulfilled"});
CREATE (:OrderStatusCanceleD {Status: "Canceled"});

MATCH (f:OrderStatusFulfilleD {Status: "Fulfilled"}), (n:Order)-[:HAS_SHIPMENT_INFO]->(s:ShipInfo)
WHERE s.ShippedDate IS NOT NULL
CREATE (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: datetime() }]->(n); 

MATCH (o:OrderStatusOpeN {Status: "Open"}), (n:Order)-[:HAS_SHIPMENT_INFO]->(s:ShipInfo)
WHERE s.ShippedDate IS NULL 
CREATE (o)-[:IS_OPEN_ORDER_STATE]->(n);



//-- End of NorthWind Graph Data Model Import --//


//  -------------------------------------------------------------------   //


// Queries Examples to run against the NorthWind Graph Data Model 
// These are examples of queries that could be used to extract insights from the NorthWind Graph Data Model.


// Total Ammount of OrderID 10461
MATCH (o:Order {OrderID:"10461"})-[r:HAS_ORDER_PRODUCT]->(p:Product)
RETURN o.OrderID, SUM(r.Quantity * r.UnitPrice) AS TotalAmmountOrder;

// Total Ammount of OrderID 10461 broken down by Product
MATCH (o:Order {OrderID:"10461"})-[r:HAS_ORDER_PRODUCT]->(p:Product)
RETURN o.OrderID, p.ProductName, r.Quantity , r.UnitPrice, r.Quantity * r.UnitPrice AS AmmountByProduct
ORDER BY AmmountByProduct DESC;

// Top 25 Orders by Total Ammount
MATCH (o:Order)-[r:HAS_ORDER_PRODUCT]->(p:Product)
RETURN o.OrderID, SUM(r.Quantity * r.UnitPrice) AS TotalAmmountOrder 
ORDER BY TotalAmmountOrder DESC
LIMIT 25;

// Top 10 Customers by Number of Orders
MATCH (c:Customer)<-[:HAS_ORDER_CUSTOMER]-(o:Order)
RETURN c.CustomerID, COUNT(o) AS NumberOfOrders
ORDER BY NumberOfOrders DESC
LIMIT 10;

// Top 10 Employees by Number of Orders Sold
MATCH (p:Person)<-[]-(e:Employee)<-[:SOLD_BY]-(o:Order)
RETURN e.EmployeeID, p.FirstName, p.LastName, COUNT(o) AS NumberOfOrdersSold
ORDER BY NumberOfOrdersSold DESC
LIMIT 10;

// Total Sales by Region
MATCH (r:Regions)-[:HAS_TERRITORY]->(t:Territory)-[:HAS_EMPLOYEE]->(e:Employee)<-[:SOLD_BY]-(o:Order)-[details:HAS_ORDER_PRODUCT]->(p:Product)
RETURN r.RegionID, r.RegionDescription, SUM( (details.Quantity * details.UnitPrice) ) AS TotalSales
ORDER BY TotalSales DESC;

// Total Sales by Region and Territory
MATCH (r:Regions)-[:HAS_TERRITORY]->(t:Territory)-[:HAS_EMPLOYEE]->(e:Employee)<-[:SOLD_BY]-(o:Order)-[details:HAS_ORDER_PRODUCT]->(p:Product)
RETURN r.RegionID, r.RegionDescription, t.TerritoryDescription, SUM( (details.Quantity * details.UnitPrice) ) AS TotalSales
ORDER BY TotalSales DESC;

// Total Sales by Category
MATCH (cat:ProductCategorY)-[:IS_PRODUCT_CATEGORY_OF]->(p:Product)<- [details:HAS_ORDER_PRODUCT]-(o:Order)
RETURN cat.CategoryName, SUM( (details.Quantity * details.UnitPrice) ) AS TotalSales
ORDER BY TotalSales DESC;

// Total Sales by Employee
MATCH (s:Person)<-[]-(e:Employee)<-[:SOLD_BY]-(o:Order)-[details:HAS_ORDER_PRODUCT]->(p:Product)
RETURN e.EmployeeID, s.FirstName, s.LastName, SUM( (details.Quantity * details.UnitPrice) ) AS TotalSales
ORDER BY TotalSales DESC;

// Total Product Orders and Stock available and Supply Orders 
MATCH (u)<-[:HAS_SUPPLY_ORDER]-(p:Product)-[:HAS_CURRENT_STOCK]->(s:InventoryLevel), (o:Order)-[details:HAS_ORDER_PRODUCT]->(p)
RETURN p.ProductID, p.ProductName, SUM(details.Quantity) AS TotalOrdered, s.UnitsInStock AS StockAvailable, u.UnitsOnOrder AS SupplyOrders
ORDER BY TotalOrdered DESC;

// Top 5 Products by Number of Orders
MATCH (c:Customer)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_PRODUCT]->(p:Product)
RETURN c.CompanyName, p.ProductName, count(o) AS orders
ORDER BY orders DESC
LIMIT 5;

// Product recomendaton for Customers based on most ordered Products by another Customers
MATCH (c:Customer)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_PRODUCT]->(p:Product)
<-[:HAS_ORDER_PRODUCT]-(o2:Order)-[:HAS_ORDER_PRODUCT]->(p2:Product)<-[:IS_PRODUCT_CATEGORY_OF]-(:ProductCategorY)-[:IS_PRODUCT_CATEGORY_OF]->(p)
WHERE c.CustomerID = 'ANTON' and NOT( (c)<-[:HAS_ORDER_CUSTOMER]-(:Order)-[:HAS_ORDER_PRODUCT]->(p2) )
RETURN c.CompanyName, p.ProductName AS has_purchased, p2.ProductName AS has_also_purchased, count(DISTINCT o2) AS occurrences
ORDER BY occurrences DESC
LIMIT 5;


//  End of Query Examples  //

//   -------------------------------------------------------------------   //

// Application Query Examples
// These are examples of queries that could be used in an Application built on top of the NorthWind Graph Data Model.
// These queries demonstrate how to create a new Order, check inventory levels, fulfill an Order, and update inventory levels accordingly.
// We will add an "N" prefix to new OrderIDs to differentiate them from imported Orders, so we can test the Application Queries without interfering with the imported data.

// Creating a New Order:
MATCH (c:Customer {CustomerID:"ALFKI"}), (e:Employee {EmployeeID:"5"}), (p1:Product {ProductID:"1"}), (p2:Product {ProductID:"2"}), (p:OrderStatusOpeN {Status: "Open"})
CREATE (o:Order {OrderID:"N10000", OrderDate:date(), RequireDate:date()+duration("P7D")})<-[:IS_OPEN_ORDER_STATE]-(p)
CREATE (o)-[:HAS_ORDER_CUSTOMER]->(c) 
CREATE (o)-[:SOLD_BY]->(e)
CREATE (o)-[:HAS_ORDER_PRODUCT {Quantity:10, UnitPrice:p1.UnitPrice, Discount:0.0}]->(p1)
CREATE (o)-[:HAS_ORDER_PRODUCT {Quantity:5, UnitPrice:p2.UnitPrice, Discount:0.1}]->(p2)
RETURN o;

// Checking Inventory before Fulfilling an Order:
MATCH (o:Order {OrderID:"N10000"})-[r:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_CURRENT_STOCK]->(s:InventoryLevel)
RETURN p.ProductName, r.Quantity AS QuantityOrdered, s.UnitsInStock AS CurrentStock;

// Fulfilling an Order (with the assumption that the Shippment Address is the same as the Customer Address, as in the original NorthWind Data Model import files):
MATCH (a)<-[:HAS_CUSTOMER_ADDRESS]-()<-[:HAS_ORDER_CUSTOMER]-(o:Order {OrderID:"N10000"})<-[r]-(p:OrderStatusOpeN {Status: "Open"}), (s:Shipper {ShipperID:"1"}), (f:OrderStatusFulfilleD {Status: "Fulfilled"})
CREATE (i:ShipInfo {ShippmentID:randomUUID(), ShippedDate:date()})
CREATE (o)-[:HAS_SHIPMENT_INFO]->(i)
CREATE (i)-[:HAS_SHIPPER]->(s)
CREATE (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: datetime()}]->(o)
CREATE (i)-[:HAS_SHIPMENT_ADDRESS]->(a)
DELETE r
RETURN o, i, s;

// Checking Inventory before Updating it after Order Fulfillment:
MATCH n=(o:Order {OrderID: "N10000"})-[]->()-[:HAS_CURRENT_STOCK]->() RETURN n;

// Updating Inventory after Order Fulfillment:

// *** This is the only exception to the rule of not updating nodes properties directly, in this case, the InventoryLevel property. 
// *** In this case, we are updating the UnitsInStock property of the InventoryLevel node to reflect the fulfillment of the Order, and the LastUpdate property to reflect the date and time of the update.

MATCH (o:Order {OrderID:"N10000"})-[r:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_CURRENT_STOCK]->(s:InventoryLevel)
SET s.UnitsInStock = s.UnitsInStock - r.Quantity
SET s.LastUpdate = datetime()
RETURN p.ProductName, s.UnitsInStock;

// Add a new Customer with Address and Contact details:
CREATE (c:Customer {CustomerID:"NEWC1", CompanyName:"New Customer Inc.", ContactName:"John Doe", ContactTitle:"Purchasing Manager"})
CREATE (a:Address {Address:"123 New St", City:"New City", Region:"NC", PostalCode:"12345", Country:"USA"})
CREATE (contact:Contact {ContactName:"John Doe", ContactTitle:"Purchasing Manager", Phone:"555-1234", Email:"John.Doe@NewCustomer.com"})
CREATE (c)-[:HAS_CUSTOMER_ADDRESS]->(a)
CREATE (c)-[:HAS_CUSTOMER_CONTACT]->(contact)
RETURN c, a, contact;

// Add a new Product, link it to a Category and Supplier, set its initial Inventory Level, and mark it as Available:
MATCH (cat:ProductCategorY {CategoryID:"7"}), (sup:Supplier {SupplierID:"6"}), (avail:ProductStatusAvailablE {Status: "Available"})
CREATE (p:Product {ProductID:"999", ProductName:"New Product", QuantityPerUnit:"1 box", UnitPrice:19.99, ReorderLevel:30})
CREATE (i:InventoryLevel {UnitsInStock:100})
CREATE (p)-[:HAS_CURRENT_STOCK]->(i)
CREATE (cat)-[:IS_PRODUCT_CATEGORY_OF]->(p)
CREATE (p)-[:HAS_PRODUCT_SUPPLIER]->(sup)
CREATE (sup)-[:SUPPLIES]->(p)
CREATE (avail)-[:IS_AVAILABLE_PRODUCT]->(p)
RETURN p, i;



//  -------------------------------------------------------------------   //

// Recommendation Engine as per: https://neo4j.com/graphgists/northwind-recommendation-engine/ adaped for NorthWind Application Graph Data Model (and Cypher Version 5)

// Collaborative Filtering - Product Rating by Customers 
// Collaborative Filtering is a technique used by recommendation engines to recommend content based on the feedback from other Customers. 
// To do this, we can use the k-NN (k-nearest neighbors) Algorithm. k-N works by grouping items into classifications based on their similarity to eachother. 
// In our case, this could be ratings between two Customers for a Product. 
// To give a real world example, this is how sites like Netflix make recommendations based on the ratings given to shows you’ve already watched.

// The first thing we need to do to make this model work is create some "ratings relationships". 
// For now, let’s create a score somewhere between 0 and 1 for each product based on the number of times a customer has purchased a product.

MATCH (c:Customer)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_PRODUCT]->(p:Product)
WITH c, count(p) AS Total
MATCH (c)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_PRODUCT]->(p:Product)
WITH c, Total,p, count(o)*1.0 AS Orders
MERGE (c)-[rated:RATED]->(p)
ON CREATE SET rated.Rating = Orders/Total
ON MATCH SET rated.Rating = Orders/Total
WITH c.CompanyName AS Company, p.ProductName AS Product, Orders, Total, rated.Rating AS Rating
ORDER BY Rating DESC
RETURN Company, Product, Orders, Total, Rating LIMIT 10; 

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
WITH p, COLLECT(r.Rating)[0..1] as Ratings, collect(c.CompanyName)[0..1] as Customers
WITH p, Customers, round(REDUCE(s=0,i in Ratings | s+i) / size(Ratings), 5)  as Recommendation
ORDER BY Recommendation DESC
RETURN p.ProductName, Customers, Recommendation LIMIT 25;

//   -------------------------------------------------------------------   //
