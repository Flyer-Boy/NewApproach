// -- NorthWind Graph Data Model Import v2.1 --//

// This v2 introduces changes of truly *ontological* proportions.

// Previously, I used a single generic relationship type [:HAS] for all elements
// belonging to a collection ("Hub Nodes" that aggregate nodes of a given Label
// based on their State or Context), mainly to preserve UI reusability.

// To maintain some level of Ontology, I added a property called RelType to the
// relationship/edge to indicate its intended ontological meaning.

// This was a conscious trade-off: it kept the UI simple, but it negatively
// affected edge indexing and would eventually impact performance at scale.

// In v2, I removed the common [:HAS] relationship type entirely and adopted
// proper ontology-specific relationship types. This restores semantic clarity
// and improves indexing behavior for large-scale graphs.

// For UI reusability, I will rely on the naming convention I use to
// distinguish Nodes from Collection Nodes (both start and end with capital letters).

// ------------------------------------------------------------------------------------ //


// This script will create the NorthWind Graph Data Model in Neo4j
// It will load data from CSV files and create Nodes, Relationships, Indexes, and Constraints    
// Use the CSV provided in the import folder, as it has been fixed. 
// The original NorthWind CSV files have some issues with commas in the data fields, mainly in the Address fields (for Brazil, France, and Belgium) and some Description fields (Notes).
// These issues can cause problems during import, resulting in misplaced fields and compromising data integrity.

// Let's clear all Nodes and Relationships before we start. 
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
CREATE (reorder:ReorderLevel {StockThreshold:toInteger(row.UnitsOnOrder), LastUpdate: datetime()})
CREATE (n)-[:HAS_REORDER_LEVEL]->(reorder)
CREATE (n)-[:HAS_SUPPLY_ORDER]->(onorder:OrderLevel {UnitsOnOrder: 0, LastUpdate: datetime()})
CREATE (n)-[:HAS_INVENTORY_LEVEL]->(i)
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
REMOVE n.Discontinued, n.ReorderLevel;

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

//-- Including Order Details in the Relationship --//

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





//--**--**--**--------------------------------------------- Plus ---------------------------------------------**--**--**--//





// The following nodes and relationships are an extension of the Model.   


// Create the Employee Directory Domain Collection Node for our demo. (In real life, this would come from the company's Active Directory or other systems.)
CREATE (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"});

// Create the relationship between the EmployeeDirectorY and all the Employees. 
MATCH  (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (e:Employee) 
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e);


// Create the Procurement Roles. 
MATCH (r:RoleS {Name:"RoleS"})
	CREATE (r)-[:HAS_ROLE_TITLE]->(:RolE {Name:"Procurment Assistant", Description:"Procurement Assistant / Coordinator", Rules:"Submits purchase orders based on inventory level and demand, tracks deliveries, and coordinates day-to-day tactical taskss"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Name:"SupplierApprover", Description:"Supplier Approver", Rules:"Approves Suplier in the System"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Name:"Level1Approver", ApprovalBase:0.00, ApprovalLimit:2000.00, Description:"Level 1 Approver", Rules:"Approves PO with a Budget < 1000.00"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Name:"Level2Approver", ApprovalBase:2001.00, ApprovalLimit:4000.00, Description:"Level 2 Approver", Rules:"Approves PO with a Budget > 1001.00 and < 2000.00"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Name:"Level3Approver", ApprovalBase:4001.00,ApprovalLimit:20000.00, Description:"Level 3 Approver", Rules:"Approves PO with a Budget > 2001.00 and < 10000.00"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Name:"Buyer" , Description:"Buyer / Purchasing Officer", Rules:"Manages specific product categories, handles routine vendor discovery, and executes purchase transactions."});

// Create the Supplier States.
CREATE (v:SupplierS {Name:"SupplierS"})-[:HAS_SUPPLIER_PENDING_STATE]->(:PendingSupplierS {Name:"PendingSupplierS"}),
       (v)-[:HAS_SUPPLIER_APPROVED_STATE]->(:ApprovedSupplierS {Name:"ApprovedSupplierS"}),
       (v)-[:HAS_SUPPLIER_REJECTED_STATE]->(:RejectedSupplierS {Name:"RejectedSupplierS"});
       
// Add the existing Suppliers to the ApprovedSupplierS state.
MATCH (a:ApprovedSupplierS {Name:"ApprovedSupplierS"}), (s:Supplier)
CREATE (a)-[:IS_SUPPLIER_APPROVED_STATE]->(s);


// Now create the additional employees who will be part of the Supplier, PO, and RFQ vetting workflows. 
MATCH (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (va:RolE {Name:"SupplierApprover"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e1:Employee {Email:"Adam.Smith@northwind.com", EmployeeID: "10", Extension: "1234" } )-[:HAS_PERSON]->(:Person {FirstName:"Adam", LastName:"Smith", BirthDate:"1989-07-02 00:00:00.000", PersonalPhone:"9551062551", PersonalEmail:"Adam@email.com"}), (e1)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(va),
        (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e2:Employee {Email:"Mary.Jane@northwind.com", EmployeeID: "11", Extension: "1235" } )-[:HAS_PERSON]->(:Person {FirstName:"Mary", LastName: "Jane", BirthDate:"1995-09-10 00:00:00.000",  PersonalPhonePhone:"909870092", PersonalEmail:"Mary@email.com" }), (e2)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(va);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (l1:RolE {Name:"Level1Approver"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e3:Employee {Email:"Gloria.Gaynor@northwind.com", EmployeeID: "12", Extension: "1236" })-[:HAS_PERSON]->(:Person {FirstName:"Gloria", LastName: "Gaynor", BirthDate:"1983-09-7 00:00:00.000", PersonalPhone:"559831373", PersonalEmail:"Gloria@email.com"}), (e3)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(l1);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (l2:RolE {Name:"Level2Approver"})       
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e4:Employee {Email:"Sara.Vaughan@northwind.com", EmployeeID: "13", Extension: "1237" })-[:HAS_PERSON]->(:Person {FirstName:"Sara", LastName: "Vaughan", BirthDate:"1984-03-27 00:00:00.000", PersonalPhone:"4849810343", PersonalEmail:"Sara@email.com"}), (e4)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(l2);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (l3:RolE {Name:"Level3Approver"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e5:Employee {Email:"Christine.McVie@northwind.com", EmployeeID: "14", Extension: "1238" })-[:HAS_PERSON]->(:Person {FirstName:"Christine", LastName: "McVie",  BirthDate:"1973-07-12 00:00:00.000",  PersonalPhon:"9998344731", PersonalEmail:"Christine@email.com"}), (e5)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(l3);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (p:RolE {Name:"Buyer"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e6:Employee {Email:"Cloe.Bailey@northwind.com", EmployeeID: "15", Extension: "1239" })-[:HAS_PERSON]->(:Person {FirstName:"Cloe", LastName: "Bailey",  BirthDate:"1998-07-01 00:00:00.000", PersonalPhon:"998195044", PersonalEmail:"Cloe@email.com"}), (e6)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(p);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (pa:RolE {Name:"Procurment Assistant"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e7:Employee {Email:"Albert.Camus@northwind.com", EmployeeID: "16", Extension: "1240" })-[:HAS_PERSON]->(:Person {FirstName:"Albert", LastName: "Camus",  BirthDate:"1993-11-07 00:00:00.000", PersonalPhon:"983435644", PersonalEmail:"Albert@email.com"}), (e7)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(pa);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (pa:RolE {Name:"Procurment Assistant"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e7:Employee {Email:"Bernard.Shaw@northwind.com", EmployeeID: "17", Extension: "1241" })-[:HAS_PERSON]->(:Person {FirstName:"Bernard", LastName: "Shaw",  BirthDate:"1983-07-26 00:00:00.000", PersonalPhon:"978535644", PersonalEmail:"Bernard@email.com"}), (e7)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(pa);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (pa:RolE {Name:"Procurment Assistant"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e7:Employee {Email:"Carlos.Santana@northwind.com", EmployeeID: "18", Extension: "1242" })-[:HAS_PERSON]->(:Person {FirstName:"Carlos", LastName: "Santana",  BirthDate:"1987-07-20 00:00:00.000", PersonalPhon:"97853474", PersonalEmail:"Carlos@email.com"}), (e7)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(pa);


// Lastly, let's create a SYSTEM user in case we need one in our 
MATCH (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"})        
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(:Employee {Email:"system@northwind.com", EmployeeID: "00", Extension: "0000" });


// Create a random Customer order with 1 to 11 products. We will execute this a few times to create some Open Orders to fulfill later.
MATCH (e:Employee)-[]-(:RolE {Title: "Sales Representative"}), (op:OrderStatusOpeN {Status: "Open"})
WITH e, op
ORDER BY rand() LIMIT 1
MATCH (c:Customer) 
WITH e, c, op
ORDER BY rand() LIMIT 1
CREATE (o:Order {OrderID: "N"+left(randomUUID(),3)+right(randomUUID(),3) , OrderDate:date(), RequireDate:date()+duration("P7D")})<-[:IS_OPEN_ORDER_STATE]-(op)
CREATE (o)-[:HAS_ORDER_CUSTOMER]->(c) 
CREATE (o)-[:SOLD_BY]->(e)
WITH o
MATCH (p:Product) 
ORDER BY rand() LIMIT toInteger(round(rand()*10 + 1))
CREATE (o)-[:HAS_ORDER_PRODUCT {Quantity: round(rand()*20), UnitPrice:p.UnitPrice, Discount:0.0}]->(p);



// Let's check which Products have Stock Levels below the Restock level so we can place new POs with their respective Suppliers. 
// We will set a minimum order quantity based on the current stock level and the reorder threshold. 
MATCH (s:Supplier)-[]->(p:Product)<-[]-(a:ProductStatusAvailablE),(r:ReorderLevel)<-[]-(p)-[]->(i:InventoryLevel) WHERE i.UnitsInStock <= r.StockThreshold
 RETURN DISTINCT  s.SupplierID, s.CompanyName, p.ProductName, p.ProductID, i.UnitsInStock, r.StockThreshold, (r.StockThreshold)-i.UnitsInStock+(r.StockThreshold/2) as MinOrder
 ORDER BY s.SupplierID ;

// Let's check the open Customer Orders by Product. 
MATCH (p:Product)<-[cop:HAS_ORDER_PRODUCT]-(o:Order)-[]-(op:OrderStatusOpeN {Status: "Open"}) RETURN p.ProductID, SUM(cop.Quantity) ORDER BY p.ProductID;

// Creating PO's

// For PO States, I will create the respective Node Labels and property names.   
// Create the PO Domain Collection Nodes.
CREATE (t:PoS {Name:"PoS"})-[:HAS_NEW_PO_STATE]->(:NewPoS {Name:"NewPoS"}),
       (t)-[:HAS_APPROVED_PO_STATE]->(:ApprovedPoS {Name:"ApprovedPoS"}),
       (t)-[:HAS_REJECTED_PO_STATE]->(:RejectedPoS {Name:"RejectedPoS"}),
       (t)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS {Name:"SubmittedPoS"}),
       (t)-[:HAS_CLOSED_PO_STATE]->(:ClosedPoS {Name:"ClosedPoS"});

// As we move the POs through the Vetting process, we will connect the PO State to the POs.
// We will use the following Ontology for this:
// For Approved POs: (PO)<-[:IS_APPROVED_PO_STATE {Date:datetime()}]-(:ApprovedPoS {Name:"ApprovedPoS"}) - POs approved during the vetting workflow. 
// For Rejected POs: (PO)<-[:IS_REJECTED_PO_STATE {Date:datetime()}]-(:RejectedPoS {Name:"RejectedPoS"}) - POs rejected during the vetting workflow. 
// For Submitted POs: (PO)<-[:IS_SUBMITTED_PO_STATE {Date:datetime()}]-(:SubmittedPoS {Name:"SubmittedPoS"}) - Approved POs submitted to the Supplier so they can send an RFQ. 
// For Closed POs: (PO)<-[:IS_CLOSED_PO_STATE {Date:datetime()}]-(:ClosedPoS {Name:"ClosedPoS"}) - POs closed (RFQ approved and products delivered, all RFQs rejected, PO canceled, etc.).


// Clean up any existing POs.
MATCH (po:PurchaseOrder)-[]->() DETACH DELETE po;
       

// The Procurement Assistant will create POs for Suppliers whose Products have low Inventory Levels.  
  // Select a random Employee with the role "Procurement Assistant".
MATCH (pa:RolE {Name: "Procurment Assistant"})-[:IS_ACTIVE_ROLE]->(e:Employee), (n:NewPoS {Name:"NewPoS"})
WITH n, e ORDER BY rand() LIMIT 1
  // Find Products with low inventory (Inventory Level <= Restock Threshold). 
MATCH (s:Supplier)-[:SUPPLIES]->(p:Product)
  <-[:IS_AVAILABLE_PRODUCT]-(a:ProductStatusAvailablE),
  (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel) 
WHERE i.UnitsInStock <= r.StockThreshold
     // Group the low-stock products and calculations by Supplier.
WITH e, n, s, COLLECT({
    Product: p, 
    qty: (r.StockThreshold) - i.UnitsInStock + (r.StockThreshold / 2)
}) AS orderItems
    // Create ONE Purchase Order per Supplier, linking it to the Employee
CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {
    PONumber: "PO" + left(randomUUID(), 3) + right(randomUUID(), 3), 
    PODate: localdatetime()
})
CREATE (s)<-[:PO_FOR_SUPPLIER]-(po)
CREATE (po)-[:PO_CREATED_BY]->(e)
WITH po, orderItems
    // Unwind the collected products to create the items for this specific PO
UNWIND orderItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (po)-[:HAS_PO_ITEM {POQt: item.qty}]->(p);


// Check the POs that were created: 
MATCH n=(p:PurchaseOrder)-[]->() RETURN n ;

//Let's get the PO costs per product and the total cost per PO.
MATCH (p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product), 
      (p)-[:PO_FOR_SUPPLIER]-(s:Supplier)
WITH p, s, id, i, (id.POQt * i.UnitPrice) AS EstimatedCost
// Find the total cost for each specific purchase order.
MATCH (p)-[r:HAS_PO_ITEM]->(otherItem:Product)
WITH p, s, id, i, EstimatedCost, sum(r.POQt * otherItem.UnitPrice) AS TotalPurchaseOrderCost
RETURN p.PONumber, 
       p.PODate, 
       s.SupplierID, 
       s.CompanyName, 
       i.ProductName, 
       id.POQt, 
       i.UnitPrice, 
       EstimatedCost, 
       TotalPurchaseOrderCost
ORDER BY s.SupplierID, p.PONumber;


// PO Vetting

//Summary of New (pending approval) POs by Total Cost.
MATCH (:NewPoS {Name:"NewPoS"})-[r]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier) 
RETURN p.PONumber, SUM((id.POQt * i.UnitPrice)) AS EstimatedCost ORDER BY EstimatedCost;

// Level 1 vetting


// Level 1 is now ready to vet the New (pending approval) POs.
// Let's have the L1 approver approve all applicable POs.
// We select the POs that are below the L1 Approval Limit and move them to the Approved State.
MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Name:"Level1Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
WITH a, ro, l1 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier) 
WITH a, ro, l1, np, p, SUM(id.POQt * i.UnitPrice) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L1_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L1 due to..< Approval justification for Decison Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1),
      (a)-[:IS_APPROVED_PO_STATE {Date:datetime()}]->(p)
DELETE np;

// Level 1 is now ready to vet the New (pending approval) POs whose cost exceeds the Level 1 approval limit, so they cannot fully approve them, 
// however, they will still vet them so the next Approval level can continue the approval process.
MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Name:"Level1Approver"}) 
WITH  ro, l1 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier) 
WITH  ro, l1, np, p, SUM(id.POQt * i.UnitPrice) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L1_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L1 due to..< Approval justification for Decison Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1);


// The following command is not supported by Cypher, but it would be very helpful if it were, as one Cypher command would suffice for both cases. 
// I am commenting it out and leaving it here as an enhancement request for the Graph Database provider. 

// MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Name:"Level1Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
// WITH a, ro, l1 ORDER BY rand() LIMIT 1
// MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier) 
// WITH a, ro, np, p, SUM(id.POQt * i.UnitPrice) AS EstimatedCost ORDER BY EstimatedCost
// CREATE (p)-[:HAS_L1_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L1 due to..< Approval justification for Decison Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1)
//   CASE EstimatedCost > ro.ApprovalBase AND EstimatedCost < ro.ApprovalLimit
//       CREATE (a)-[:IS_APPROVED_PO_STATE {Date:datetime()}]->(p),
//       DELETE np
//   ELSE END;


// Now we move to Level 2 vetting - similar to Level 1, but we will check whether L1 has already approved the PO.
MATCH (l2:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Name:"Level2Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
WITH a, ro, l2 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier), (p)-[:HAS_L1_PO_APPROVAL]-()
WITH a, ro, l2, np, p, SUM(id.POQt * i.UnitPrice) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L2 due to..< Approval justification for Decison Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l2),
      (a)-[:IS_APPROVED_PO_STATE {Date:datetime()}]->(p)
DELETE np;

MATCH (l2:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Name:"Level2Approver"}) 
WITH  ro, l2 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier), (p)-[:HAS_L1_PO_APPROVAL]-()
WITH  ro, l2, np, p, SUM(id.POQt * i.UnitPrice) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L2 due to..< Approval justification for Decison Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l2);


//Finally, Level 3 vetting - same as Level 2. 
MATCH (l3:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Name:"Level3Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
WITH a, ro, l3 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier), (p)-[:HAS_L2_PO_APPROVAL]-()
WITH a, ro, l3, np, p, SUM(id.POQt * i.UnitPrice) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L3_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L3 due to..< Approval justification for Decison Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l3),
      (a)-[:IS_APPROVED_PO_STATE {Date:datetime()}]->(p)
DELETE np;

MATCH (l3:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Name:"Level3Approver"}) 
WITH  ro, l2 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier), (p)-[:HAS_L2_PO_APPROVAL]-()
WITH  ro, l2, np, p, SUM(id.POQt * i.UnitPrice) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L3_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L3 due to..< Approval justification for Decison Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l3);

// You can add as many vetting levels as you want, following the same pattern. Simple, isn't it? 

// Next up in the workflow is the "Buyer", who will review the Approved POs (and vet them if needed) and submit them to the respective Suppliers so they can send their RFQs for each PO. 
// Before we start submitting POs to the Suppliers, we must create the appropriate Graph schemas for Suppliers to receive and submit RFQs, and for POs to accept or reject RFQs. 

// Suppliers must have a collection to hold the New POs so they can query, "What new/open POs do I have to submit RFQs for?" You might say: "Easy, check all the Approved/Submitted POs from Procurement where I am the Supplier." 
// However, we don't want a query from the Supplier frontend to have access to all the Approved/Submitted POs from Procurement, but only to a subset controlled by Procurement containing their POs. 
// This subset that the Supplier has access to is the collection I am referring to. 
// Procurement will then "connect" the Submitted POs to this Supplier Collection, where the Supplier can see only the POs that matter to them.
// There is much more to access rights that I have not covered in these code comments or in my articles. However, access rights are considered throughout this model. 
// The original models/graph from which these concepts came used DRM down to the Node level. This was a huge overhead at the time, but it helped frame our work and models.
// I will write about this in an article at some point. For now, let's get our model working.

MATCH (s:Supplier)
CREATE (s)-[:HAS_NEW_PENDIG_POS]->(:NewPoS) // Answers to supplier question: Do I have any new PO's  
       (s)-[:HAS_IN_PROGRESS_POS]->(:InProgressPoS)  // Answers to supplier question: Do I have PO's in progress that require my followup 
       (s)-[:HAS_CLOSED_POS]->(:ClosedPoS); // Answers to supplier question: Where are my passed PO's 

// We will also have to Create a schemas for the PO's that have made it thrugh the entire vetting process and are submitted to the Supplier. 
// We will do this as part of the PO submission process.

// Let's now put on the "Buyer" hat and do the last phase of the PO vetting.
// The Buyer will Approve and Submit the PO's to the respective Supplier

MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Name:"Buyer"}), (su:SubmittedPoS {Name:"SubmittedPoS"})
WITH su, bu ORDER BY rand() LIMIT 1
MATCH (a:ApprovedPoS {Name:"ApprovedPoS"})-[ap]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier)-[:HAS_NEW_PENDIG_POS]->(snp:NewPoS) 
WITH ap, s, bu, su, p
CREATE (p)-[:HAS_BUYER_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by Buyer due to..< Approval justification for Decison Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(bu),
       (su)-[:IS_SUBMITTED_PO_STATE {Date:datetime()}]->(p)
       (snp)-[:HAS_NEW_PO]-(p)  // The Buyer places the PO in the Supplire's NewPoS collection 
       (p)-[:HAS_SUPPLIER_NEW_RFQ]-(:PoNewRFQ)  //The Buyer enhances the Schema of the PO with s collection to hold future RFQs submited by the Supplier
       (p)-[:HAS_SUPPLIER_NEW_RFQ]-(:PoNewRFQ)
       (p)-[:HAS_SUPPLIER_APPROVED_RFQ]-(:PoApprovedRFQ)
       (p)-[:HAS_SUPPLIER_REJECTED_RFQ]-(:PoRejectedRFQ)
DELETE ap;
















































//  -------------------------------------------------------------------   //


// Query Examples to Run Against the NorthWind Graph Data Model 
// These are examples of queries that can be used to extract insights from the NorthWind Graph Data Model.


// Total Amount of OrderID 10461
MATCH (o:Order {OrderID:"10461"})-[r:HAS_ORDER_PRODUCT]->(p:Product)
RETURN o.OrderID, SUM(r.Quantity * r.UnitPrice) AS TotalAmmountOrder;

// Total Amount of OrderID 10461 broken down by Product
MATCH (o:Order {OrderID:"10461"})-[r:HAS_ORDER_PRODUCT]->(p:Product)
RETURN o.OrderID, p.ProductName, r.Quantity , r.UnitPrice, r.Quantity * r.UnitPrice AS AmmountByProduct
ORDER BY AmmountByProduct DESC;

// Top 25 Orders by Total Amount
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

// Total Product Orders, Stock Available, and Supply Orders 
MATCH (u)<-[:HAS_SUPPLY_ORDER]-(p:Product)-[:HAS_INVENTORY_LEVEL]->(s:InventoryLevel), (o:Order)-[details:HAS_ORDER_PRODUCT]->(p)
RETURN p.ProductID, p.ProductName, SUM(details.Quantity) AS TotalOrdered, s.UnitsInStock AS StockAvailable, u.UnitsOnOrder AS SupplyOrders
ORDER BY TotalOrdered DESC;

// Top 5 Products by Number of Orders
MATCH (c:Customer)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_PRODUCT]->(p:Product)
RETURN c.CompanyName, p.ProductName, count(o) AS orders
ORDER BY orders DESC
LIMIT 5;

// Product Recommendation for Customers Based on the Most-Ordered Products by Other Customers
MATCH (c:Customer)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_PRODUCT]->(p:Product)
<-[:HAS_ORDER_PRODUCT]-(o2:Order)-[:HAS_ORDER_PRODUCT]->(p2:Product)<-[:IS_PRODUCT_CATEGORY_OF]-(:ProductCategorY)-[:IS_PRODUCT_CATEGORY_OF]->(p)
WHERE c.CustomerID = 'ANTON' and NOT( (c)<-[:HAS_ORDER_CUSTOMER]-(:Order)-[:HAS_ORDER_PRODUCT]->(p2) )
RETURN c.CompanyName, p.ProductName AS has_purchased, p2.ProductName AS has_also_purchased, count(DISTINCT o2) AS occurrences
ORDER BY occurrences DESC
LIMIT 5;


//  End of Query Examples  //

//   -------------------------------------------------------------------   //

// Application Query Examples
// These are examples of queries that could be used in an application built on top of the NorthWind Graph Data Model.
// These queries demonstrate how to create a new Order, check inventory levels, fulfill an Order, and update inventory levels accordingly.
// We will add an "N" prefix to new OrderIDs to distinguish them from imported Orders, allowing us to test the Application Queries without interfering with the imported data.

// Creating a New Order:
MATCH (c:Customer {CustomerID:"ALFKI"}), (e:Employee {EmployeeID:"5"}), (p1:Product {ProductID:"1"}), (p2:Product {ProductID:"2"}), (p:OrderStatusOpeN {Status: "Open"})
CREATE (o:Order {OrderID:"N10000", OrderDate:date(), RequireDate:date()+duration("P7D")})<-[:IS_OPEN_ORDER_STATE]-(p)
CREATE (o)-[:HAS_ORDER_CUSTOMER]->(c) 
CREATE (o)-[:SOLD_BY]->(e)
CREATE (o)-[:HAS_ORDER_PRODUCT {Quantity:10, UnitPrice:p1.UnitPrice, Discount:0.0}]->(p1)
CREATE (o)-[:HAS_ORDER_PRODUCT {Quantity:5, UnitPrice:p2.UnitPrice, Discount:0.1}]->(p2)
RETURN o;

// Checking Inventory Before Fulfilling an Order:
MATCH (o:Order {OrderID:"N10000"})-[r:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(s:InventoryLevel)
RETURN p.ProductName, r.Quantity AS QuantityOrdered, s.UnitsInStock AS CurrentStock;

// Fulfilling an Order (assuming that the Shipment Address is the same as the Customer Address, as in the original NorthWind Data Model import files):
MATCH (a)<-[:HAS_CUSTOMER_ADDRESS]-()<-[:HAS_ORDER_CUSTOMER]-(o:Order {OrderID:"N10000"})<-[r]-(p:OrderStatusOpeN {Status: "Open"}), (s:Shipper {ShipperID:"1"}), (f:OrderStatusFulfilleD {Status: "Fulfilled"})
CREATE (i:ShipInfo {ShippmentID:randomUUID(), ShippedDate:date()})
CREATE (o)-[:HAS_SHIPMENT_INFO]->(i)
CREATE (i)-[:HAS_SHIPPER]->(s)
CREATE (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: datetime()}]->(o)
CREATE (i)-[:HAS_SHIPMENT_ADDRESS]->(a)
DELETE r
RETURN o, i, s;

// Checking Inventory Before Updating It After Order Fulfillment:
MATCH n=(o:Order {OrderID: "N10000"})-[]->()-[:HAS_INVENTORY_LEVEL]->() RETURN n;

// Updating Inventory After Order Fulfillment:

// *** This is the only exception to the rule of not updating node properties directly; in this case, the InventoryLevel property. 
// *** In this case, we are updating the UnitsInStock property of the InventoryLevel node to reflect the fulfillment of the Order, and the LastUpdate property to reflect the date and time of the update.

MATCH (o:Order {OrderID:"N10000"})-[r:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(s:InventoryLevel)
SET s.UnitsInStock = s.UnitsInStock - r.Quantity
SET s.LastUpdate = datetime()
RETURN p.ProductName, s.UnitsInStock;

// Add a New Customer with Address and Contact Details:
CREATE (c:Customer {CustomerID:"NEWC1", CompanyName:"New Customer Inc.", ContactName:"John Doe", ContactTitle:"Purchasing Manager"})
CREATE (a:Address {Address:"123 New St", City:"New City", Region:"NC", PostalCode:"12345", Country:"USA"})
CREATE (contact:Contact {ContactName:"John Doe", ContactTitle:"Purchasing Manager", Phone:"555-1234", Email:"John.Doe@NewCustomer.com"})
CREATE (c)-[:HAS_CUSTOMER_ADDRESS]->(a)
CREATE (c)-[:HAS_CUSTOMER_CONTACT]->(contact)
RETURN c, a, contact;

// Add a New Product, Link It to a Category and Supplier, Set Its Initial Inventory Level, and Mark It as Available:
MATCH (cat:ProductCategorY {CategoryID:"7"}), (sup:Supplier {SupplierID:"6"}), (avail:ProductStatusAvailablE {Status: "Available"})
CREATE (p:Product {ProductID:"999", ProductName:"New Product", QuantityPerUnit:"1 box", UnitPrice:19.99, ReorderLevel:30})
CREATE (i:InventoryLevel {UnitsInStock:100})
CREATE (p)-[:HAS_INVENTORY_LEVEL]->(i)
CREATE (cat)-[:IS_PRODUCT_CATEGORY_OF]->(p)
CREATE (p)-[:HAS_PRODUCT_SUPPLIER]->(sup)
CREATE (sup)-[:SUPPLIES]->(p)
CREATE (avail)-[:IS_AVAILABLE_PRODUCT]->(p)
RETURN p, i;



//  -------------------------------------------------------------------   //

// Recommendation Engine based on the Neo4j NorthWind Recommendation Engine GraphGist, adapted for the NorthWind Application Graph Data Model (and Cypher Version 5).

// Collaborative Filtering - Product Ratings by Customers 
// Collaborative Filtering is a technique used by recommendation engines to recommend content based on feedback from other Customers. 
// To do this, we can use the k-NN (k-nearest neighbors) algorithm. k-NN works by grouping items based on their similarity to each other. 
// In our case, the similarity is based on ratings between two Customers for a Product. 
// As a real-world example, this is how sites like Netflix can make recommendations based on ratings given to shows you have already watched.

// The first thing we need to do to make this model work is create some "rating relationships". 
// For now, let's create a score between 0 and 1 for each Product based on the number of times a Customer has purchased that Product.

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

// Now that we have ratings between Customers and Products, we can start finding similarities between Customers based on their ratings.

// View a Customer's Ratings
MATCH (me:Customer)-[r:RATED]->(p:Product)
WHERE me.CustomerID = 'ANTON'
RETURN p.ProductName, r.Rating limit 10;

// View a Customer's Ratings Compared with Other Customers
MATCH (c1:Customer {CustomerID:'ANTON'})-[r1:RATED]->(p:Product)<-[r2:RATED]-(c2:Customer)
RETURN c1.CustomerID, c2.CustomerID, p.ProductName, r1.Rating, r2.Rating,
CASE WHEN r1.Rating-r2.Rating < 0 THEN -(r1.Rating-r2.Rating) ELSE r1.Rating-r2.Rating END as difference
ORDER BY difference ASC
LIMIT 15; 

// Now we can calculate the similarity between Customers based on their ratings using Cosine Similarity.
// We can create a similarity score between two Customers using Cosine Similarity.  
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
