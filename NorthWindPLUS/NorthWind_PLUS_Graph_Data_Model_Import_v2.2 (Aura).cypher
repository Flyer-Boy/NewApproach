// -- NorthWind PLUS Graph Data Model Import v2.2 For Aura --//

// If you find yourself filtering on a Node property that represents state, context, or an entity's relevance to something else, that's a sign the model needs a relationship instead, 
// as it was most likely built with a table mentality.
// This is what this model intends to achieve, by using a Graph mentality to rebuild a well known model that once was a reference for a Relational Database model.  


// This v2 introduces changes of truly *ontological* proportions.
// Previously, I used a single generic relationship type [:HAS] for all elements belonging to a collection ("Hub Nodes" that aggregate nodes of a given Label
// based on their State or Context), mainly to preserve UI reusability.
// To maintain some level of Ontology, I added a property called RelType to the relationship/edge to indicate its intended ontological meaning.
// This was a conscious trade-off: it kept the UI simple, but it negatively affected edge indexing and would eventually impact performance at scale.
// In v2, I removed the common [:HAS] relationship type entirely and adopted proper ontology-specific relationship types. This restores semantic clarity
// and improves indexing behavior for large-scale graphs.
// For UI reusability, I will rely on the naming convention I use to distinguish Nodes from Collection Nodes (Pascal with ending capital letter).

// I will stick to the key principles:

// **Proper Noun Nodes:**

//    Nodes should only store properties that define the uniqueness of the entity (the "Thing") they represent. 
//    Any property that represents a state or an entity’s contextual relevance to another entity should be modeled as a relationship, not a property of the entity. This makes the model semantically explicit.
//    Nothing is hidden inside entity properties. You (and AI) can understand and reason on the entire model at any state without reading its properties. 

// **Never Delete Nodes:**

//    Nodes are never deleted, ensuring full traceability of all entities over time. Time flows in one direction. What is done cannot be undone. 
//    If the model is a faithful representation of the real world, this principle should be respected. In this model, entities are archived and timestamped so they can be looked up later.    

// **Read-Only Nodes:**

//    Once created, node properties should remain unchanged. The SET command is strictly reserved for value corrections or certain edge cases/exceptions, but not the norm. 
//    This approach significantly simplifies transaction concurrency and consistency management, which is a major differentiator from traditional RDBMS models, where property updates are common and often introduce complexity.
//    If your domain model requires/demands constant property updates across multiple entities (e.g., ledger systems), you might stick to the traditional RDBMS/table-based architecture rather than the one being proposed here.   

// **Relationships Drive the System (workflow):**

//    The system relies on creating new nodes and then creating/deleting their relationships according to the model workflow rules/state changes. 
//    This might sound odd at first, but think of it…this is how everything you know, from the micro to macro universe, including yourself, works. 
//    There are 118 stable elements in the periodic table (that we know of) that create everything we know just by altering their relationships. 
//    Not by changing their properties, except for isotopes (the edge cases I mention earlier, the exceptions but not the norm). Nature is showing us the way. 
//    This is biomimicry applied to software architecture.  

//  **Lean Nodes:**

//    Outgoing relationships are minimized. For one-to-many connections, we use some nodes as Collections. 
//    Collections can represent domain States as well as Context (i.e, virtual aggregation). While relational algebra relies on implicit set operations (Union, Intersection, Difference, Cartesian product), 
//    I will use explicit ones (Superset, Subset, Element of), aligning with how nature and humans intuitively organize reality into sets. This aligns the Graph with the domain expert mental model.
//    While this introduces an additional traversal cost, the structure scales better as the database grows.
//    There are deeper considerations behind this, involving how the Graph is stored (how Node properties and its adjacency table are stored) and the implications for indexing, query optimization, and performance, 
//    as well as Node digital rights management (DRM) considerations. Still, I won’t go down that rabbit hole here. However, they are highly relevant and taken into consideration. 
//
//    I’m aware that current Graph Databases are not fully optimized for this approach I am suggesting, but I trust they will at some point. I witnessed and worked with the first RDBMS and saw how they evolved in the past decades; 
//    Graph Databases will too.

// ------------------------------------------------------------------------------------ //


// This script will create the NorthWind Graph Data Model in Neo4j
// It will load data from CSV files and create Nodes, Relationships, Indexes, and Constraints    
// Use the CSV provided in the import folder (https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/), as they have been fixed. 
// The original NorthWind CSV files (https://github.com/neo4j-graph-examples/northwind) have some issues with commas in the data fields, mainly in the Address fields (for Brazil, France, and Belgium) and some Description fields (Notes).
// These issues can cause problems during import, resulting in misplaced fields and compromising data integrity.

// Here we go!!

//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
//                                                                    ** Quick Run Instructions: **
// Copy this script from line 73 to 1052. Paste it into the Neo4j Aura Query console. Execute and wait. 
// Follow the instructions from line 1084 to 1097 to run the Python simulation loops.  Run the Queries on line 1210 onwards as the Python loops run. Enjoy!! 
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//


// Let's clear all Nodes and Relationships before we start. 
MATCH (n) DETACH DELETE n;

//-- Loading Data from CSV files --//
// We start by importing the Product Categories 
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/categories.csv" AS row
MERGE (n:ProductCategorY {CategoryID:row.CategoryID, CategoryName:row.CategoryName, Description:row.Description}); 

// Let's create the Product availability Status as Collections where we will connect the products later and the SuperSet CategorieS
CREATE (:CategorieS {Name: "CategorieS"});
CREATE (:ProductStatusDiscontinueD {Status: "Discontinued"}); 
CREATE (:ProductStatusAvailablE {Status: "Available"}); 

// We import the Suppliers
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/suppliers.csv" AS row
MERGE (n:Supplier {SupplierID:row.SupplierID, CompanyName:row.CompanyName, ContactName:row.ContactName, ContactTitle:row.ContactTitle, Address:row.Address, City:row.City, Region:row.Region, PostalCode:row.PostalCode, Country:row.Country, Phone:row.Phone, Fax:row.Fax, HomePage:"https://www." + replace(replace(replace(row.CompanyName," ",""),"'",""),".","") + ".com"});

// We do our first Graph normalization extracting the Address and Contact from the Supplier and placing them in different Nodes with a proper relationship
MATCH (n:Supplier)
CREATE (a:Address {Address:n.Address, City:n.City, Region:n.Region, PostalCode:n.PostalCode, Country:n.Country})
CREATE (c:Contact {ContactName:n.ContactName, ContactTitle:n.ContactTitle, Phone:n.Phone, Fax:n.Fax, Email: replace(n.ContactName, " ", ".") +"@" + replace(replace(replace(n.CompanyName," ",""),"'",""),".","") + ".com"})
CREATE (n)-[:HAS_SUPPLIER_ADDRESS]->(a)
CREATE (n)-[:HAS_SUPPLIER_CONTACT]->(c);


// We import the Product and as we import we normalize it so the Product only keeps the Properties that define the Product 

// **Read-Only Nodes note:**

//    Once created, node properties should remain unchanged. The SET command is strictly reserved for value corrections or certain edge cases/exceptions, but not the norm. 
//    This approach significantly simplifies transaction concurrency and consistency management, which is a major differentiator from traditional RDBMS models, where property updates are common and often introduce complexity.
//    If your domain model requires/demands constant property updates across multiple entities (e.g., ledger systems), you might stick to the traditional RDBMS/table-based architecture rather than the one being proposed here.   
//    This model has three deliberate exceptions to this rule -- InventoryLevel.UnitsInStock, OrderLevel.UnitsOnOrder and ReorderLevel.StockThreshold -- explained where they occur below.
//    Therefore, we will place the reorder level, supply order level and Inventory level in separate Nodes. 
//    We will keep the Price though, for simplicity. In an ideal model we should place it in a separate Node as the Price is not part of the Product Identity but an attribute that might change over time. 

//    We will connect the Product to its respective Product Category
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/products.csv" AS row
MERGE (n:Product {ProductID:row.ProductID, ProductName:row.ProductName, UnitPrice:toFloat(row.UnitPrice), ReorderLevel:toInteger(row.ReorderLevel), QuantityPerUnit:row.QuantityPerUnit, Discontinued:toInteger(row.Discontinued), SupplierID:row.SupplierID})
CREATE (i:InventoryLevel {UnitsInStock:toInteger(row.UnitsInStock), LastUpdate: datetime()})             // Here is the InventoryLevel.UnitsInStock as a separate Node, as it is a state that will change over time.
CREATE (reorder:ReorderLevel {StockThreshold:toInteger(row.UnitsInStock) + 10, LastUpdate: datetime()})  // Here is the ReorderLevel.StockThreshold as a separate Node. The StockThreshold is intentionally set to the UnitsInStock + 10 for this Demo. This number will allow the script to generate more PO's later and subsequently more RFQ's in the process creating a richer dataset for us to play with 
CREATE (n)-[:HAS_REORDER_LEVEL]->(reorder)
CREATE (n)-[:HAS_SUPPLY_ORDER]->(onorder:OrderLevel {UnitsOnOrder: 0, LastUpdate: datetime()})           // Here is the OrderLevel.UnitsOnOrder as a separate Node, as it is a state that will change over time.
CREATE (n)-[:HAS_INVENTORY_LEVEL]->(i)
WITH n, row
MATCH (c:ProductCategorY) WHERE c.CategoryID = row.CategoryID
MERGE (c)-[:IS_PRODUCT_CATEGORY_OF]->(n);

// We will normalize the Discontinued products by connecting them to the respective collection
MATCH (d:ProductStatusDiscontinueD {Status: "Discontinued"}), (n:Product)
WHERE n.Discontinued = 1
MERGE (d)-[:IS_DISCONTINUED_PRODUCT]->(n);

// We will normalize the Available products by connecting them to the respective collection
MATCH (a:ProductStatusAvailablE {Status: "Available"}), (n:Product)
WHERE n.Discontinued = 0 
MERGE (a)-[:IS_AVAILABLE_PRODUCT]->(n);

// Remove the Productr properties that were normalized
MATCH (n:Product)
REMOVE n.Discontinued, n.ReorderLevel;

// Connect the Product to the respective supplier 
MATCH (s:Supplier), (p:Product)
WHERE s.SupplierID = p.SupplierID 
MERGE (p)-[:HAS_PRODUCT_SUPPLIER]->(s)
MERGE (s)-[:SUPPLIES]->(p);

// Remove the SupplierID from Product 
MATCH (n:Product)
REMOVE n.SupplierID;

MATCH (s:Supplier)
REMOVE s.ContactName, s.ContactTitle, s.Address, s.City, s.Region, s.PostalCode, s.Country, s.Phone, s.Fax;

MATCH (k:CategorieS {Name: "CategorieS"}), (c:ProductCategorY)
MERGE (k)-[:HAS_CATEGORY]->(c);

LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/customers.csv" AS row
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

LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/employees.csv" AS row
MERGE (l:RolE {Title:row.Title}) 
WITH l
MATCH (r:RoleS)
MERGE (r)-[:HAS_ROLE_TITLE]->(l);

LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/employees.csv" AS row
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

LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/territories.csv" AS row
MERGE (n:Territory {TerritoryID:row.TerritoryID})
SET n += row;

LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/regions.csv" AS row
MERGE (n:Regions {RegionID:row.RegionID})
SET n += row;

LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/employee-territories.csv" AS row
MATCH (e:Employee), (t:Territory)
WHERE e.EmployeeID = row.EmployeeID AND t.TerritoryID = row.TerritoryID
MERGE (t)-[:HAS_EMPLOYEE]->(e);

MATCH (t:Territory), (r:Regions)
WHERE t.RegionID = r.RegionID
MERGE (r)-[:HAS_TERRITORY]->(t);

MATCH (t:Territory) REMOVE t.RegionID;

LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/shippers.csv" AS row
MERGE (n:Shipper {ShipperID:row.ShipperID, CompanyName:row.CompanyName, Phone:row.Phone});

LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/orders.csv" AS row
MERGE (n:OrderTmp {OrderID:row.OrderID})
SET n += row;

// We will normalize the OrderDate, RequiredDate to proper datetime format.
MATCH (o:OrderTmp) 
SET o.OrderDate = datetime(left(o.OrderDate, 10)+"T"+right(o.OrderDate, 12)), 
o.RequiredDate = datetime(left(o.RequiredDate, 10)+"T"+right(o.RequiredDate, 12));
 
MATCH (n:OrderTmp)
WITH collect(n) AS originalNodes
CALL apoc.refactor.cloneNodes(originalNodes, false)
YIELD output AS clonedNode
SET clonedNode:Order
RETURN count(clonedNode) AS clonedCount;

MATCH (n:OrderTmp) DETACH DELETE  n;

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

LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/Flyer-Boy/NewApproach/refs/heads/main/NorthWind/Import/order-details.csv" AS row
MATCH (p:Product), (o:Order)
WHERE p.ProductID = row.ProductID AND o.OrderID = row.OrderID 
MERGE (o)-[details:HAS_ORDER_PRODUCT]->(p)
SET details.Quantity = toInteger(row.Quantity), details.UnitPrice = toFloat(row.UnitPrice), details.Discount = toFloat(row.Discount); 

// Create the OrderS Superset Collection and the subset OrderStatus Collection Nodes
CREATE (o:OrderS {Name: "OrderS"})-[:HAS_OPEN_ORDER_STATUS]->(:OrderStatusOpeN {Status: "Open"}),
       (o)-[:HAS_FULFILLED_ORDER_STATUS]->(:OrderStatusFulfilleD {Status: "Fulfilled"}),
       (o)-[:HAS_CANCELED_ORDER_STATUS]->(:OrderStatusCanceleD {Status: "Canceled"});

MATCH (f:OrderStatusFulfilleD {Status: "Fulfilled"}), (n:Order)-[:HAS_SHIPMENT_INFO]->(s:ShipInfo)
WHERE s.ShippedDate IS NOT NULL
CREATE (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: datetime() }]->(n); 

MATCH (o:OrderStatusOpeN {Status: "Open"}), (n:Order)-[:HAS_SHIPMENT_INFO]->(s:ShipInfo)
WHERE s.ShippedDate IS NULL 
CREATE (o)-[:IS_OPEN_ORDER_STATE]->(n);

//-- End of NorthWind Graph Data Model Import --//

// The Database is set up and ready to go. You can now run the queries below to extract insights from the data as it is being updated in real-time.

//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// ###### **Inventory Level Report** ######  //
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//


//  -- Remember this query as we will run it several times to see how the Inventory Level changes as we run the simulation of the NorthWind PLUS Graph Data Model.

// First run of the ###### **Inventory Level Report** ######, to see the current Inventory Level of all Products in the system just after the import.

  // To visualize the Product's Inventory Levels, Supply Orders (RFQ Approved) pending fulfilment, Stock Threashold, Open Customer Orders and Open PO's to resupply from Today on the Graph console, use the following query:
  // Product Supply/Demand Dashboard -- one row per Product, ordered by name
  MATCH ()-[:IS_AVAILABLE_PRODUCT]-(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel),
        (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel),
        (p)-[:HAS_SUPPLY_ORDER]->(suo:OrderLevel)
  // Open Customer Order demand for this Product
  OPTIONAL MATCH (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(o:Order)-[details:HAS_ORDER_PRODUCT]->(p)
  WITH p, inv, r, suo,
       count(DISTINCT o) AS OpenCustomerOrders,
       coalesce(sum(details.Quantity), 0) AS QtyDemanded
  // Quantity confirmed by an approved RFQ, not yet delivered by the Warehouse
  OPTIONAL MATCH (po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(:RFQ)-[rfi:HAS_RFQ_ITEM]->(p)
  WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
  WITH p, inv, r, suo, OpenCustomerOrders, QtyDemanded,
       coalesce(sum(rfi.RFQqt), 0) AS QtyApprovedRFQPendingDelivery
  // Quantity requested via an open PO that does NOT yet have an approved RFQ
  // (excluded here to avoid double-counting the same units already captured above)
  OPTIONAL MATCH (po2:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p)
  WHERE ((po2)<-[:IS_NEW_PO_STATE]-(:NewPoS)
      OR (po2)<-[:IS_APPROVED_PO_STATE]-(:ApprovedPoS)
      OR (po2)<-[:IS_SUBMITTED_PO_STATE]-(:SubmittedPoS))
    AND NOT (po2)-[:HAS_APPROVED_RFQ]->(:RFQ)
  WITH p, inv, r, suo, OpenCustomerOrders, QtyDemanded, QtyApprovedRFQPendingDelivery,
       coalesce(sum(poi2.POqt), 0) AS QtyOpenPOsNotYetConfirmed
  RETURN p.ProductName AS ProductName,
         inv.UnitsInStock AS UnitsInStock,
         r.StockThreshold AS StockThreshold,
         suo.UnitsOnOrder AS UnitsOnOrder_Tracked,
         QtyApprovedRFQPendingDelivery AS QtyApprovedRFQPendingDelivery,
         QtyOpenPOsNotYetConfirmed AS QtyOpenPOsNotYetConfirmed,
         (QtyApprovedRFQPendingDelivery + QtyOpenPOsNotYetConfirmed) AS TotalIncomingQty,
         OpenCustomerOrders AS OpenCustomerOrders,
         QtyDemanded AS QtyDemanded
  ORDER BY ProductName;


//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
//--**--**--**---------------------------------------------------------------- PLUS ----------------------------------------------------------------**--**--**--//
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//


// The following nodes and relationships are an extension of the Model.   
// This is an ambitious project in which I am adding a full ontology to this old model and making it a 360 full-cycle process with everything I can add. 
// When the Graph model is completed, I will create the Python loop applications that will simulate each part of the model separately (Random Customer Orders, PO generation for low inventory, 
// PO vetting with 3+ vetting levels, Supplier RFQ submission for incoming PO’s, RFQ vetting, Inventory update as PO’s are fulfilled, Customer Order fulfillment, Inventory update, Customer order shipping,
// recommendation engine update, etc.. ) so you can run them in paralell and see if the Graph holds the load.

// The following Cypher commands will create the base schemas for the NorthWind PLUS Graph Data Model.

// Disclaimer: You will notice that the Graph database will call your attention for "a part of a query contains multiple disconnected patterns, this will build a cartesian product between all those parts." 
// This is because the Graph Database does not now that we are referencing Domain collections that only have one instance of each Node. 
// The Graph Database is just warning you that it will create a cartesian product, but in this case it is not a problem as we are referencing Domain collections that only have one instance of each Node.


// Disclaimer on the Employee Directory: The following Cypher commands are for demonstration purposes only. 
// They are not intended for production use and may require further customization to fit specific business needs.
// A proper employee directory system would be used in a real-world scenario (idelly on a graph), and the relationships between employees and roles would be managed through an HR system or similar.
// This would be an entire system in itself, but for the purpose of this demo, we will create a simplified version of an employee directory and role management system within the NorthWind PLUS Graph Data Model.
// They will not be properly normalized as they are not the focus of this demo, but they will serve the purpose of demonstrating the workflow and relationships between employees, roles, and the procurement process.


// Create the Employee Directory Domain Collection Node for our demo. (In real life, this would come from the company's Active Directory or other systems.)
CREATE (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"});

// Create the relationship between the EmployeeDirectorY and all the Employees. 
MATCH  (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (e:Employee) 
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e);


// Create the Procurement Roles. 
// The RolE is one of those exceptions where we will keep the properties of the Role in the Node itself as they are somewhat part of the Role Identity and not a state or context.
// We could have them in a separate Node, but for simplicity we will keep them in the RolE Node.
MATCH (r:RoleS {Name:"RoleS"})
	CREATE (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Procurement Assistant", Description:"Procurement Assistant / Coordinator", Rules:"Submits purchase orders based on inventory level and demand, tracks deliveries, and coordinates day-to-day tactical tasks"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"SupplierApprover", Description:"Supplier Approver", Rules:"Approves Suppliers in the System"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Level1Approver", ApprovalBase:0.00, ApprovalLimit:2000.00, Description:"Level 1 Approver", Rules:"Approves PO with a Budget < 2000.00"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Level2Approver", ApprovalBase:2001.00, ApprovalLimit:4000.00, Description:"Level 2 Approver", Rules:"Approves PO with a Budget > 2001.00 and < 4000.00"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Level3Approver", ApprovalBase:4001.00,ApprovalLimit:20000.00, Description:"Level 3 Approver", Rules:"Approves PO with a Budget > 4001.00 and < 20000.00"}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Buyer" , Description:"Buyer / Purchasing Officer", Rules:"Manages specific product categories, handles routine vendor discovery, and executes purchase transactions."}),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"WarehouseClerk", Description:"Warehouse Clerk", Rules:"Receives and inspects incoming shipments, updates inventory records, and ensures proper storage of goods."} ),
      (r)-[:HAS_ROLE_TITLE]->(:RolE {Title:"Finance", Description:"Finance Officer", Rules:"Manages financial transactions, processes payments, and maintains financial records."} );

// Create the Supplier States.
CREATE (v:SupplierS {Name:"SupplierS"})-[:HAS_SUPPLIER_PENDING_STATE]->(:PendingSupplierS {Name:"PendingSupplierS"}),
       (v)-[:HAS_SUPPLIER_APPROVED_STATE]->(:ApprovedSupplierS {Name:"ApprovedSupplierS"}),
       (v)-[:HAS_SUPPLIER_REJECTED_STATE]->(:RejectedSupplierS {Name:"RejectedSupplierS"});
       
// Add the existing Suppliers to the ApprovedSupplierS state.
MATCH (a:ApprovedSupplierS {Name:"ApprovedSupplierS"}), (s:Supplier)
CREATE (a)-[:IS_SUPPLIER_APPROVED_STATE]->(s);


// Now create the additional employees who will be part of the Supplier, PO, and RFQ vetting workflows. 
MATCH (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (va:RolE {Title:"SupplierApprover"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e1:Employee {Email:"Adam.Smith@northwind.com", EmployeeID: "10", Extension: "1234" } )-[:HAS_PERSON]->(:Person {FirstName:"Adam", LastName:"Smith", BirthDate:"1989-07-02 00:00:00.000", PersonalPhone:"9551062551", PersonalEmail:"Adam@email.com"}), (e1)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(va),
        (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e2:Employee {Email:"Mary.Jane@northwind.com", EmployeeID: "11", Extension: "1235" } )-[:HAS_PERSON]->(:Person {FirstName:"Mary", LastName: "Jane", BirthDate:"1995-09-10 00:00:00.000",  PersonalPhone:"909870092", PersonalEmail:"Mary@email.com" }), (e2)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(va);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (l1:RolE {Title:"Level1Approver"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e3:Employee {Email:"Gloria.Gaynor@northwind.com", EmployeeID: "12", Extension: "1236" })-[:HAS_PERSON]->(:Person {FirstName:"Gloria", LastName: "Gaynor", BirthDate:"1983-09-7 00:00:00.000", PersonalPhone:"559831373", PersonalEmail:"Gloria@email.com"}), (e3)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(l1);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (l2:RolE {Title:"Level2Approver"})       
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e4:Employee {Email:"Sara.Vaughan@northwind.com", EmployeeID: "13", Extension: "1237" })-[:HAS_PERSON]->(:Person {FirstName:"Sara", LastName: "Vaughan", BirthDate:"1984-03-27 00:00:00.000", PersonalPhone:"4849810343", PersonalEmail:"Sara@email.com"}), (e4)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(l2);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (l3:RolE {Title:"Level3Approver"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e5:Employee {Email:"Christine.McVie@northwind.com", EmployeeID: "14", Extension: "1238" })-[:HAS_PERSON]->(:Person {FirstName:"Christine", LastName: "McVie",  BirthDate:"1973-07-12 00:00:00.000",  PersonalPhone:"9998344731", PersonalEmail:"Christine@email.com"}), (e5)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(l3);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (p:RolE {Title:"Buyer"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e6:Employee {Email:"Cloe.Bailey@northwind.com", EmployeeID: "15", Extension: "1239" })-[:HAS_PERSON]->(:Person {FirstName:"Cloe", LastName: "Bailey",  BirthDate:"1998-07-01 00:00:00.000", PersonalPhone:"998195044", PersonalEmail:"Cloe@email.com"}), (e6)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(p);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (pa:RolE {Title:"Procurement Assistant"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e7:Employee {Email:"Albert.Camus@northwind.com", EmployeeID: "16", Extension: "1240" })-[:HAS_PERSON]->(:Person {FirstName:"Albert", LastName: "Camus",  BirthDate:"1993-11-07 00:00:00.000", PersonalPhone:"983435644", PersonalEmail:"Albert@email.com"}), (e7)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(pa);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (pa:RolE {Title:"Procurement Assistant"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e7:Employee {Email:"Bernard.Shaw@northwind.com", EmployeeID: "17", Extension: "1241" })-[:HAS_PERSON]->(:Person {FirstName:"Bernard", LastName: "Shaw",  BirthDate:"1983-07-26 00:00:00.000", PersonalPhone:"978535644", PersonalEmail:"Bernard@email.com"}), (e7)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(pa);

MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (pa:RolE {Title:"Procurement Assistant"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e7:Employee {Email:"Carlos.Santana@northwind.com", EmployeeID: "18", Extension: "1242" })-[:HAS_PERSON]->(:Person {FirstName:"Carlos", LastName: "Santana",  BirthDate:"1987-07-20 00:00:00.000", PersonalPhone:"97853474", PersonalEmail:"Carlos@email.com"}), (e7)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(pa);


//We will create a Warehouse Klerk role and one employees to manage the warehouse and the inventory.
MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (wk:RolE {Title:"WarehouseClerk"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e8:Employee {Email:"John.Doe@northwind.com", EmployeeID: "19", Extension: "1243" })-[:HAS_PERSON]->(:Person {FirstName:"John", LastName: "Doe",  BirthDate:"1990-07-20 00:00:00.000", PersonalPhone:"95644474", PersonalEmail:"John@email.com"}), (e8)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(wk);

// We will create the Finance role and one employee to manage the finance and the payments.
MATCH   (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (f:RolE {Title:"Finance"})
CREATE  (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(e9:Employee {Email:"Jane.Doe@northwind.com", EmployeeID: "20", Extension: "1244" })-[:HAS_PERSON]->(:Person {FirstName:"Jane", LastName: "Doe",  BirthDate:"1985-03-15 00:00:00.000", PersonalPhone:"96755574", PersonalEmail:"Jane@email.com"}), (e9)<-[:IS_ACTIVE_ROLE {StartDate:datetime()}]-(f);  


// Lastly, let's create a SYSTEM user in case we need one in our 
MATCH (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"})        
CREATE (ed)-[:HAS_ACTIVE_EMPLOYEE {StartDate:datetime()}]->(:Employee {Email:"system@northwind.com", EmployeeID: "00", Extension: "0000" });


// Create a random Customer order with 1 to 11 products. We will execute this a few times to create some Open Orders to fulfill later.
// The bellow command will create 50 Random Customer orders.
UNWIND range(1, 50) AS i
CALL (i)  {with i
MATCH (e:Employee)-[]-(:RolE {Title: "Sales Representative"}), (op:OrderStatusOpeN {Status: "Open"})
WITH e, op
ORDER BY rand() LIMIT 1
MATCH (c:Customer) 
WITH e, c, op
ORDER BY rand() LIMIT 1
CREATE (o:Order {OrderID: "CO-"+left(randomUUID(),3)+right(randomUUID(),3) , OrderDate:datetime(), RequiredDate:datetime()+duration("P7D")})<-[:IS_OPEN_ORDER_STATE]-(op)
CREATE (o)-[:HAS_ORDER_CUSTOMER]->(c) 
CREATE (o)-[:SOLD_BY]->(e)
WITH o
MATCH (p:Product)-[]-(:ProductStatusAvailablE {Status: "Available"}) 
ORDER BY rand() LIMIT toInteger(round(rand()*10 + 1))
CREATE (o)-[:HAS_ORDER_PRODUCT {Quantity: toInteger(round(rand()*19)+1), UnitPrice:p.UnitPrice, Discount:0.0}]->(p)
};

// ###### Run the **Inventory Level Report** ######  
// You will see how the Inventory Level changes after the random Customer Orders were created.
// Feel free to run the above Cypher command multiple times to create more random Customer Orders and see how the Inventory Level changes after each run.


// You will notice that the above Cypher command creates a random Customer Order with 1 to 11 products and it only creates one new Order node per Order and the rest is managed by the relatioships.
// Unlike Relational databases, where you would likely have to create new records for each Item in the Order table, 
// in a Graph database you can create a single Order node and connect it to multiple Product nodes with the HAS_ORDER_PRODUCT relationship, 
// which can hold the Quantity, UnitPrice, and Discount properties for each product in the order.

// Let's check which Products have Stock Levels below the Restock Threshold level so we can place new POs with their respective Suppliers. 
// We will set a minimum order quantity based on the current stock level and the reorder threshold. 
MATCH (s:Supplier)-[]->(p:Product)<-[]-(a:ProductStatusAvailablE),(r:ReorderLevel)<-[]-(p)-[]->(i:InventoryLevel) WHERE i.UnitsInStock <= r.StockThreshold
 RETURN DISTINCT  s.SupplierID, s.CompanyName, p.ProductName, p.ProductID, i.UnitsInStock, r.StockThreshold, (r.StockThreshold)-i.UnitsInStock+(r.StockThreshold/2) as MinOrder
 ORDER BY s.SupplierID ;

// Let's check the open Customer Orders by Product. 
MATCH (p:Product)<-[cop:HAS_ORDER_PRODUCT]-(o:Order)-[]-(op:OrderStatusOpeN {Status: "Open"}) RETURN p.ProductID, SUM(cop.Quantity) ORDER BY p.ProductID;

// Creating PO's states schemas in preparation for the PO Vetting process.

// For PO States, I will create the respective Node Labels and property names.   
// Create the PO Domain Collection Nodes.
// The "PoS" Node/Collection is the superset of all the PO States. 
CREATE (t:PoS {Name:"PoS"})-[:HAS_NEW_PO_STATE]->(:NewPoS {Name:"NewPoS"}),
       (t)-[:HAS_APPROVED_PO_STATE]->(:ApprovedPoS {Name:"ApprovedPoS"}),
       (t)-[:HAS_REJECTED_PO_STATE]->(:RejectedPoS {Name:"RejectedPoS"}),
       (t)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS {Name:"SubmittedPoS"}),
       (t)-[:HAS_CLOSED_PO_STATE]->(:ClosedPoS {Name:"ClosedPoS"});

// Procurement Perspective: As we move the POs through the Vetting process, we will connect the PO State to the POs.
// We will use the following Ontology for this:
// For Approved POs: (PO)<-[:IS_APPROVED_PO_STATE {Date:datetime()}]-(:ApprovedPoS {Name:"ApprovedPoS"}) - POs approved during the vetting workflow. 
// For Rejected POs: (PO)<-[:IS_REJECTED_PO_STATE {Date:datetime()}]-(:RejectedPoS {Name:"RejectedPoS"}) - POs rejected during the vetting workflow. 
// For Submitted POs: (PO)<-[:IS_SUBMITTED_PO_STATE {Date:datetime()}]-(:SubmittedPoS {Name:"SubmittedPoS"}) - Approved POs submitted to the Supplier so they can send an RFQ. 
// For Closed POs: (PO)<-[:IS_CLOSED_PO_STATE {Date:datetime()}]-(:ClosedPoS {Name:"ClosedPoS"}) - POs closed (RFQ approved and products delivered, all RFQs rejected, PO canceled, etc.).

// We will also create a collection of POs for the Supplier to see only the POs that matter to them. We will use them later in the PO Submission and RFQ process.
// Suppliers must have a collection to hold the New POs so they can query, "What new/open POs do I have to submit RFQs for?" You might say: "Easy, check all the Approved/Submitted POs from Procurement where I am the Supplier." 
// However, we don't want a query from the Supplier frontend to have access to all the Approved/Submitted POs from Procurement, but only to a subset controlled by Procurement containing their POs. 
// This subset that the Supplier has access to is the collection I am referring to. 
// Procurement will then "connect" the Submitted POs to this Supplier Collection, where the Supplier can see only the POs that matter to them.
// There is much more to access rights that I have not covered in these code comments or in my articles. However, access rights are considered throughout this model. 
// The original models/graph from which these concepts came used DRM down to the Node level. This was a huge overhead at the time, but it helped frame our work and models.
// I will write about this in an article at some point. For now, let's get our model working.

MATCH (s:Supplier)
CREATE (s)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(:SupplierNewPoS {Name:"SupplierNewPoS"}), // Answers to supplier question: Do I have any new PO's  
       (s)-[:HAS_SUPPLIER_OPEN_POS]->(:SupplierOpenPoS {Name:"SupplierOpenPoS"}),  // Answers to supplier question: Do I have PO's in progress that require my followup 
       (s)-[:HAS_SUPPLIER_CLOSED_POS]->(:SupplierClosedPoS {Name:"SupplierClosedPoS"});

// Supplier Perspective: As the Supplier receives POs and start submitting RFQ's we will move (disconnect/connect) the 'POs from the Supplier collections as they are addressed. 
// We will use the following Ontology for this:
// For New incoming POs: (PO)<-[:IS_SUPPLIER_NEW_PO_STATE {Date:datetime()}]-(:SupplierNewPoS {Name:"SupplierNewPoS"}) - New POs submitted by Buyer. 
// For Open/Replied POs: (PO)<-[:IS_SUPPLIER_OPEN_PO_STATE {Date:datetime()}]-(:SupplierOpenPoS {Name:"SupplierOpenPoS"}) - POs that the Supplier has an RFQ, is negotiating or has still to deliver the products. 
// For Closed POs: (PO)<-[:IS_SUPPLIER_CLOSED_PO_STATE {Date:datetime()}]-(:SupplierClosedPoS {Name:"SupplierClosedPoS"}) - POs closed (RFQ approved and products delivered, all RFQs rejected, PO canceled, etc.).


//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// **PO Creation**
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

// The Procurement Assistant will create POs for Suppliers whose Products have low Inventory Levels (nearing restock threashold level).  
// Select a random Employee with the role "Procurement Assistant".
MATCH (pa:RolE {Title: "Procurement Assistant"})-[:IS_ACTIVE_ROLE]->(e:Employee), (n:NewPoS {Name:"NewPoS"})
WITH n, e ORDER BY rand() LIMIT 1
MATCH (s:Supplier)-[:SUPPLIES]->(p:Product)
  <-[:IS_AVAILABLE_PRODUCT]-(a:ProductStatusAvailablE),
  (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)     // Find Products with low inventory (Inventory Level <= Restock Threshold). 
OPTIONAL MATCH (activePO:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p)
WHERE (activePO)<-[:IS_NEW_PO_STATE]-(:NewPoS)
   OR (activePO)<-[:IS_APPROVED_PO_STATE]-(:ApprovedPoS)       // Check if there are any active POs for this product that are either New or Approved (not yet submitted to Supplier)
   OR (activePO)<-[:IS_SUBMITTED_PO_STATE]-(:SubmittedPoS)
WITH e, n, s, p, r, i, SUM(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty
WHERE i.UnitsInStock + AlreadyPendingQty - (r.StockThreshold * 0.5) <= r.StockThreshold
WITH e, n, s, COLLECT({
    Product: p,
    qty: (r.StockThreshold) - (i.UnitsInStock + AlreadyPendingQty) + (r.StockThreshold * 2)
}) AS orderItems
CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {
    PONumber: "PO-" + left(randomUUID(), 3) + right(randomUUID(), 3),
    PODate: localdatetime()
})
CREATE (s)<-[:PO_FOR_SUPPLIER]-(po)     // Connect the PO to the respective Supplier
CREATE (po)-[:PO_CREATED_BY]->(e)       // Connect the PO to the employee that created it
WITH po, orderItems, s                  // Unwind the collected products to create the items for this specific PO
UNWIND orderItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7}]->(p)   // We add the PO items and their order quantity, in this demo we will get the unit cost as a % of the Product price 
RETURN DISTINCT po.PONumber AS PONumber, s.SupplierID AS SupplierID, size(orderItems) AS ItemCount;


// ###### Run the **Inventory Level Report** ######  
// You will see how the Inventory Level changes after the POs were created. 
// You will notice that the Inventory Level has not changed yet, as the POs have not been fulfilled yet, 
// but you will see the OpePO quantys in the report, which are the quantities of products that are on open POs that have not yet been fulfilled.

// Check the POs that were created: 
MATCH n=(p:PurchaseOrder)-[]->() RETURN n ;

//Let's get the PO costs per product and the total cost per PO.
MATCH (p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product), 
      (p)-[:PO_FOR_SUPPLIER]-(s:Supplier)
WITH p, s, id, i, (id.POqt * i.UnitPrice) AS EstimatedCost
// Find the total cost for each specific purchase order.
MATCH (p)-[r:HAS_PO_ITEM]->(otherItem:Product)
WITH p, s, id, i, EstimatedCost, sum(r.POqt * otherItem.UnitPrice) AS TotalPurchaseOrderCost
RETURN p.PONumber, 
       p.PODate, 
       s.SupplierID, 
       s.CompanyName, 
       i.ProductName, 
       id.POqt, 
       i.UnitPrice, 
       EstimatedCost, 
       TotalPurchaseOrderCost
ORDER BY s.SupplierID, p.PONumber;



//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// **PO Vetting**
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

// We will do a 3+1 Level Vetting process folowing the PO Budget approval level of each Procurement Approver as defined by their Role.

//Summary of New (pending approval) POs by Total Cost (we will apply a ~30% standard discount by Suppliers as product cost).
MATCH (:NewPoS {Name:"NewPoS"})-[r]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier) 
RETURN p.PONumber, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS EstimatedCost ORDER BY EstimatedCost;

// **Level 1 vetting**

// Level 1 is now ready to vet the New (pending approval) POs.
// For our Demo, we will Reject two POs at Level 1 so we have one instance (we will resubmit one of them later)
MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level1Approver"}), (a:RejectedPoS {Name:"RejectedPoS"})
WITH a, ro, l1 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier) 
WITH a, ro, l1, np, p, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS POCost ORDER BY p LIMIT 2
WHERE POCost > ro.ApprovalBase  
CREATE (p)-[:HAS_L1_PO_REJECTION {Date:datetime(), Comment:"This PO is rejected by L1 due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1),
      (a)-[:IS_REJECTED_PO_STATE {Date:datetime()}]->(p)
DELETE np;


// Let's have the L1 approver approve all the remaining applicable POs.
// We select the POs that are below the L1 Approval Limit and move them to the Approved State. For Demo purposes we will only approve 20 PO's here
MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level1Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
WITH a, ro, l1 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier) 
WITH a, ro, l1, np, p, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS POCost ORDER BY p LIMIT 20
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L1_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L1 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1),
      (a)-[:IS_APPROVED_PO_STATE {Date:datetime()}]->(p)
DELETE np;

// Level 1 is now ready to vet the New (pending approval) POs whose cost exceeds the Level 1 approval limit, so they cannot fully approve them, 
// however, they will still vet them so the next Approval level can continue the approval process. 
MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level1Approver"}) 
WITH  ro, l1 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier) 
WITH  ro, l1, np, p, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS POCost 
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L1_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L1 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1);


// The following command is not supported by Cypher/GQL, but it would be very helpful if it were, as one Cypher command would suffice for both CASES. 
// I am commenting it out and leaving it here as an enhancement request for the Graph Database provider. 

// MATCH (l1:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level1Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
// WITH a, ro, l1 ORDER BY rand() LIMIT 1
// MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier) 
// WITH a, ro, np, p, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS EstimatedCost ORDER BY EstimatedCost
// CREATE (p)-[:HAS_L1_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L1 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l1)
//   CASE EstimatedCost > ro.ApprovalBase AND EstimatedCost < ro.ApprovalLimit
//       CREATE (a)-[:IS_APPROVED_PO_STATE {Date:datetime()}]->(p),
//       DELETE np
//   ELSE END;

// **Level 2 vetting**

// Now we move to Level 2 vetting - similar to Level 1, but we will check whether L1 has already approved the PO.
MATCH (l2:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level2Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
WITH a, ro, l2 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier), (p)-[:HAS_L1_PO_APPROVAL]-()
WITH a, ro, l2, np, p, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L2 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l2),
      (a)-[:IS_APPROVED_PO_STATE {Date:datetime()}]->(p)
DELETE np;

// Level 2 is now ready to vet the New (pending approval) POs whose cost exceeds the Level 2 approval limit, so they cannot fully approve them, 
// however, they will still vet them so the next Approval level can continue the approval process.

// For our Demo, we will Reject one PO at level 2 so we have one instance s these PO will not be approved by L3 as it will be rejected at L2 despite the fact that they were approved at L1 and beyond the L2 approval limit.
MATCH (l2:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level2Approver"}), (a:RejectedPoS {Name:"RejectedPoS"})
WITH a, ro, l2 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier), (p)-[:HAS_L1_PO_APPROVAL]-()
WITH a, ro, l2, np, p, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS POCost ORDER BY p LIMIT 1
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_REJECTION {Date:datetime(), Comment:"This PO is rejected by L2 due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l2),
      (a)-[:IS_REJECTED_PO_STATE {Date:datetime()}]->(p)
DELETE np;


MATCH (l2:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level2Approver"}) 
WITH  ro, l2 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier), (p)-[:HAS_L1_PO_APPROVAL]-()
WITH  ro, l2, np, p, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS POCost
WHERE POCost > ro.ApprovalBase AND POCost > ro.ApprovalLimit
CREATE (p)-[:HAS_L2_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L2 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l2);


// **Level 3 vetting**

//Finally, Level 3 vetting  
// For our Demo, we will Reject one PO at level 3 so we have one instance  
MATCH (l3:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level3Approver"}), (a:RejectedPoS {Name:"RejectedPoS"})
WITH a, ro, l3 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier), (p)-[:HAS_L2_PO_APPROVAL]-()
WITH a, ro, l3, np, p, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS POCost ORDER BY p LIMIT 1
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit 
CREATE (p)-[:HAS_L3_PO_REJECTION {Date:datetime(), Comment:"This PO is rejected by L3 due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l3),
      (a)-[:IS_REJECTED_PO_STATE {Date:datetime()}]->(p)
DELETE np;


// Level 3 will approve the two remaining PO's , so we leave some PO's pending approval. 
MATCH (l3:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Level3Approver"}), (a:ApprovedPoS {Name:"ApprovedPoS"})
WITH a, ro, l3 ORDER BY rand() LIMIT 1
MATCH (:NewPoS {Name:"NewPoS"})-[np]->(p:PurchaseOrder)-[id:HAS_PO_ITEM]->(i:Product)-[]-(s:Supplier), (p)-[:HAS_L2_PO_APPROVAL]-()
WITH a, ro, l3, np, p, SUM((id.POqt * (i.UnitPrice*id.POPriceDiscount))) AS POCost ORDER BY p LIMIT 2
WHERE POCost > ro.ApprovalBase AND POCost < ro.ApprovalLimit
CREATE (p)-[:HAS_L3_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by L3 due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(l3),
      (a)-[:IS_APPROVED_PO_STATE {Date:datetime()}]->(p)
DELETE np;



//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// **PO Resubmission**
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

// Remember those PO's that were rejected, well, we will now act as one of the Procurement Assistants that had one PO rejected and have him/her resubmit the PO
// Notice that the New PO will point back to the Rejected one for auditing and added context 
MATCH (re:RejectedPoS)-[:IS_REJECTED_PO_STATE]->(rpo:PurchaseOrder)-[:PO_CREATED_BY]->(e:Employee), (n:NewPoS {Name:"NewPoS"})
WITH n, rpo, e ORDER BY rpo LIMIT 1
MATCH (rpo)-[:HAS_PO_ITEM]->(p),(s:Supplier)-[:SUPPLIES]->(p)
  <-[:IS_AVAILABLE_PRODUCT]-(a:ProductStatusAvailablE),
  (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel) 
WHERE i.UnitsInStock-(r.StockThreshold*0.5) <= r.StockThreshold
     // Group the low-stock products and calculations by Supplier.
WITH rpo, e, n, s, COLLECT({
    Product: p, 
    qty: (r.StockThreshold) - i.UnitsInStock + (r.StockThreshold / 2)
}) AS orderItems
    // Create ONE Purchase Order per Supplier, linking it to the Employee
CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {
    PONumber: "PO-" + left(randomUUID(), 3) + right(randomUUID(), 3), 
    PODate: localdatetime() 
})
CREATE (s)<-[:PO_FOR_SUPPLIER]-(po)    // Connect the PO to the respective Supplier
CREATE (po)-[:PO_CREATED_BY]->(e)      // Connect the PO to the employee that created it
CREATE (po)-[:HAS_PREVIOUS_PO {Resubmission_Justification: "Reason for resubmission. What changed. What was missing or not accurate in the previous one. Comments, etc. "}]->(rpo) // As this is a PO resubmission, we connect the new PO to the previous PO version for auditing 
WITH po, orderItems
    // Unwind the collected products to create the items for this specific PO
UNWIND orderItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7 }]->(p);  // We add the PO items and their order quantity 
 

// You can add as many vetting levels as you want, following the same pattern. Simple, isn't it? 

// Next up in the workflow is the "Buyer", who will review the Approved POs (and vet them if needed) and submit them to the respective Suppliers so they can send their RFQs for each PO. 
// Before we start submitting POs to the Suppliers, we must create the appropriate Graph schemas for Suppliers to receive and submit RFQs, and for POs to accept or reject RFQs. 

// We will also have to Create a schemas for the PO's that have made it through the entire vetting process and are submitted to the Supplier. 
// We will do this as part of the PO submission process.

// **PO Submisson** to Suppliers (last phase of the vetting)

// Let's now put on the "Buyer" hat and do the last phase of the PO vetting.
// The Buyer will Approve and Submit the PO's to the respective Supplier. For Demo purpouse, we will limit to 10 submission and we will leave a few PO's on the Approved collection (state) pending submission 
// When the Buyer submits the PO to the Supplier 

MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Buyer"}), (su:SubmittedPoS {Name:"SubmittedPoS"})
WITH su, bu ORDER BY rand() LIMIT 1
MATCH (a:ApprovedPoS {Name:"ApprovedPoS"})-[ap]->(po:PurchaseOrder)-[:PO_FOR_SUPPLIER]->(s:Supplier)-[:HAS_SUPPLIER_NEW_PENDING_POS]->(snp) 
WITH ap, s, bu, su, po, snp ORDER BY po LIMIT 10             
CREATE (po)-[:HAS_BUYER_PO_APPROVAL {Date:datetime(), Comment:"This PO is approved by Buyer due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(bu),  // We connect the PO to the Buyer that Submitted it. 
       (su)-[:IS_SUBMITTED_PO_STATE {Date:datetime()}]->(po), // We connect the PO to the Submitted state Collection 
       (snp)-[:IS_SUPPLIER_NEW_PO_STATE {Date:datetime()}]->(po),                     // The Buyer places the PO in the Supplier's NewPoS collection 
       (po)-[:HAS_SUPPLIER_NEW_RFQ]->(:PoNewRFQ {Name:"PoNewRFQ"}),             // The Buyer creats the PO's state collections for upcoming RFQ's vetting process - The firts one is PoNewFRQ - to hold the new RFQ's submitted by the Supplier
       (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(:PoRejectedRFQ {Name:"PoRejectedRFQ"})    // The second one is the PoRejectedRFQ - to hold the Rejected RFQ's as there could be more than one rejection in the vetting
                                                              // we don'tt need a collection to hold the Approved RFQ as there will only be one and we can connect it directly to the PO
DELETE ap;                                                    // We remove the PO from the Approved state as we have connected it to Submitted earlier. 

// As we move the 'RFQs through the Vetting process, we will connect the respective RFQ State to the RFQs.
// We will use the following Ontology for this:
// For Approved RFQs: We connect the PO to the RFQ as: (PO)-[:HAS_APPROVED_RFQ]->(RFQ)   
// For Rejected RFQs: (PO)-[:HAS_SUPPLIER_REJECTED_RFQ]->(:PoRejectedRFQ {Name:"PoRejectedRFQ)"})-[:IS_SUPPLIER_REJECTED_RFQ_STATE {Date:datetime()}]->(RFQ) - hold the RFQ's that were rejected during the vetting workflow. 
// And, just as we did in the PO vetting, each employee that participated in the vetting process will be connected to the RFQ with the timedate and justification for the vetting  



//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// ** Supplier RFQ**  
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

// Next step, Suppliers will check what are the Open PO's and submit the respective RFQ's (they will apply the 30% discount on the products) 

MATCH (su:Supplier)-[np:HAS_SUPPLIER_NEW_PENDING_POS]->()-[r]->(po)-[pq:HAS_PO_ITEM]-(p), (po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr), (su)-[:HAS_SUPPLIER_OPEN_POS]->(sop) 
WITH su, r, po, snr, sop, COLLECT({
    Product: p, 
    qty: pq.POqt,              // The Supplier will enter the Quantity of products they will supply in the RFQ
    cost: p.UnitPrice * 0.7    // The Supplier will enter the discount they will provide in their RFQ
}) AS rfqItems
CREATE (rfq:RFQ {
    RFQNumber: "RFQ-" + left(randomUUID(), 3) + right(randomUUID(), 3), 
    RFQDate: localdatetime(), 
    RFQComments: "Thanks for your order, we are able to supply the full PO product request at the discounted price negotiated on our master agreement"})-[:IS_RFQ_FOR_PO]->(po), // We create the RFQ
(rfq)-[:RFQ_FROM_SUPPLIER]->(su),    // We connect the RFQ to the Suppier 
(snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq),  // We place the RFQ in the PO's new RFQ state collection 
(sop)-[:IS_SUPPLIER_OPEN_PO_STATE {Date:datetime()}]->(po)    // We move the PO to the Supplier Open PO's (with RFQ submitted)
DELETE r                              // We remove the PO from the Supplier New PO's
WITH rfq, rfqItems
UNWIND rfqItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (rfq)-[:HAS_RFQ_ITEM {RFQqt: item.qty, RFQcost: item.cost}]->(p);  // We add the RFQ data (product quantity and unit cost) in the Relationship of the RFQ



//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// **RFQ Vetting**
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

// Lets Compare the PO Budget to the RFQ Costs and check our Inventory Levels prior to approving the RFQ.
MATCH (su:SubmittedPoS)-[]->(po)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po), (inv)<-[:HAS_INVENTORY_LEVEL]-(p)-[:HAS_SUPPLY_ORDER]-(suo)
WHERE poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost
RETURN po.PONumber, rfq.RFQNumber ,p.ProductID, poi.POqt, poi.POqt * (p.UnitPrice * poi.POPriceDiscount) as POBudget,  rfi.RFQqt, rfi.RFQqt * rfi.RFQcost AS RFQcost, inv.UnitsInStock, suo.UnitsOnOrder;


// To keep things simple we will have only the Buyer, who was the last level of the PO Approval and the one who submitted the PO, to vet the RFQ. 
// Alternatively, we could have a 3+1 Level RFQ approval just as we did with the PO 

// We will reject two RFQs just to have an instance and be able to query it later 
MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Buyer"}) 
WITH bu ORDER BY rand() LIMIT 1
MATCH (su:SubmittedPoS)-[]->(po)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq)-[rfi:HAS_RFQ_ITEM]->(p)<-[poi:HAS_PO_ITEM]-(po), (po)-[:HAS_SUPPLIER_REJECTED_RFQ]->(prr)
WHERE poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost
WITH bu, pnr, prr, po, p, r, poi, rfq, rfi 
ORDER BY po.PONumber DESC LIMIT 2
CREATE (rfq)-[:HAS_BUYER_RFQ_REJECTION {Date:datetime(), Comment:"This RFQ is rejected by Buyer due to..< Rejection justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(bu),      // We conect the rfq to the Buyer with the datetime of the Approval and the Buyer justification 
        (prr)-[:IS_SUPPLIER_REJECTED_RFQ_STATE {Date:datetime()}]->(rfq)   // We connect the rfq to the PO's PoRejectedRFQ state collection
DELETE r;   

// The Supplier can then submit another FRQ and just as we did with the PO, the new RFQ will point back to the rejected one for tracking.
// For this demo we will have one radom suppier resubmit one RFQ and we will leave the other in the Rejected state pending resubmisson (so we caq query and find it)


MATCH (su:Supplier)-[np:HAS_SUPPLIER_NEW_PENDING_POS]->()-[r]->(po)-[pq:HAS_PO_ITEM]-(p), (po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr), (su)-[:HAS_SUPPLIER_OPEN_POS]->(sop) 
WITH su, r, po, snr, sop, COLLECT({
    Product: p, 
    qty: pq.POqt,              // The Supplier will enter the Quantity of products they will supply in the RFQ
    cost: p.UnitPrice * 0.7    // The Supplier will enter the discount they will provide in their RFQ
}) AS rfqItems
CREATE (rfq:RFQ {
    RFQNumber: "RFQ-" + left(randomUUID(), 3) + right(randomUUID(), 3), 
    RFQDate: localdatetime(), 
    RFQComments: "Thanks for your order, we are able to supply the full PO product request at the discounted price negotiated on our master agreement"})-[:IS_RFQ_FOR_PO]->(po), // We create the RFQ
(rfq)-[:RFQ_FROM_SUPPLIER]->(su),    // We connect the RFQ to the Suppier 
(snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq),  // We place the RFQ in the PO's new RFQ state collection 
(sop)-[:IS_SUPPLIER_OPEN_PO_STATE {Date:datetime()}]->(po)    // We move the PO to the Supplier Open PO's (with RFQ submitted)
DELETE r                              // We remove the PO from the Supplier New PO's
WITH rfq, rfqItems
UNWIND rfqItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (rfq)-[:HAS_RFQ_ITEM {RFQqt: item.qty, RFQcost: item.cost}]->(p);  // We add the RFQ data (product quantity and unit cost) in the Relationship of the RFQ


// *** ISOTOPE NODES: a deliberate, isolated exception to Read-Only Nodes. ***
//
// InventoryLevel, OrderLevel, and ReorderLevel are the three places in this model where a property is genuinely mutated rather than superseded by a new relationship. Like isotopes 
// of a stable element -- same identity, different neutron count -- these are variants of the same principle, not violations of it: the volatility is isolated to small, dedicated nodes 
// rather than leaking into Product itself, so Product stays a true Proper Noun Node no matter how often its stock and order levels change underneath it.
//
// The split isn't only about isolating *that* something mutates -- it's about isolating mutation *by frequency*, and these three don't all mutate at the same rate:
//
//   - InventoryLevel.UnitsInStock and OrderLevel.UnitsOnOrder are both high-frequency, high-contention. UnitsInStock changes on every order fulfillment; UnitsOnOrder changes 
//     on every RFQ approval (incoming supply) and again on every Warehouse delivery (outgoing from "on order," incoming to stock) -- two separate write paths into the same 
//     property.
//   - ReorderLevel.StockThreshold is low-frequency by comparison, changing only via periodic recalculation (see "Update the Stock Threshold" below).
//
// Keeping all three on separate, dedicated nodes means a hot property never drags a cold one into its contention footprint, and a write to one can never block a read of another.
//
// If Graph Databases evolve into hybrid engines with native stream support, InventoryLevel and OrderLevel are the stronger candidates to become actual streams -- high write rate, real value 
// in a point-in-time history ("what was stock/on-order at 2pm Tuesday"). ReorderLevel behaves more like a periodically-recomputed business parameter than a stream -- there's less inherent 
// value in a full time-series of past thresholds versus simply knowing the current one -- so it would likely remain a conventional mutable node even in that future. 
// However, it would be ideal to keep a temporar record of its changes. 


// For our Demo we will select 8 RFQ's that are within the PO Budget (PO Budget >= RFQ Cost) and have the Buyer Approve them  
MATCH (bu:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Buyer"}) 
WITH bu ORDER BY rand() LIMIT 1
MATCH (su:SubmittedPoS)-[]->(po)-[:HAS_SUPPLIER_NEW_RFQ]->(pnr)-[r:IS_SUPPLIER_NEW_RFQ]->(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po)
WHERE poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost
WITH bu, po, rfq, r, collect({poi: poi, rfi: rfi, p: p}) AS items
ORDER BY po.PONumber
LIMIT 8
UNWIND items AS item
WITH bu, po, rfq, r, item.poi AS poi, item.rfi AS rfi, item.p AS p
MATCH (inv)<-[:HAS_INVENTORY_LEVEL]-(p)-[:HAS_SUPPLY_ORDER]-(suo)
MERGE (rfq)-[:HAS_BUYER_RFQ_APPROVAL {Date:datetime(), Comment:"This RFQ is approved by Buyer due to..< Approval justification for Decision Traces - for Context Graph > - alternatively this could be placed on a separate Node  >..."}]->(bu)   // We conect the rfq to the Buyer with the datetime of the Approval and the Buyer justification 
MERGE  (po)-[:HAS_APPROVED_RFQ {Date:datetime()}]->(rfq)         // We connect the PO to the Approved RFQ   
SET    suo.UnitsOnOrder = suo.UnitsOnOrder + rfi.RFQqt           // We update the Supply Order status to reflect the Approved RFQ     
DELETE r;                                                        // We delete the connection between the PO's PoNewRFQ state collection

// Check the RFQ's that were approved and the updated Supply Order status for the products.
MATCH (su:SubmittedPoS)-[]->(po)-[:HAS_APPROVED_RFQ]->(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]-(p)<-[poi:HAS_PO_ITEM]-(po), (inv)<-[:HAS_INVENTORY_LEVEL]-(p)-[:HAS_SUPPLY_ORDER]-(suo)
WHERE poi.POqt * (p.UnitPrice * poi.POPriceDiscount) >= rfi.RFQqt * rfi.RFQcost
RETURN po.PONumber, rfq.RFQNumber ,p.ProductID, poi.POqt, poi.POqt * (p.UnitPrice * poi.POPriceDiscount) as POBudget,  rfi.RFQqt, rfi.RFQqt * rfi.RFQcost AS RFQcost, inv.UnitsInStock, suo.UnitsOnOrder;

// Unlike the PO, we will not create state collections on the RFQ's as we only have one Supplier per product in this model. 
// The RFQ has been Approved but the PO remains Open for the Procurement (SubmittedPoS state) and Supplier (SupplierOpenPoS state) until it is fulfilled (products deleivered, suppliere payment made, etc.).
// We could craete other states (state collections) in both the Procurement perspective and Supplier perspective to reflect the   



//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// **RFQ Resubmission**
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

// For our Demo we will have one Supplier resubmit one RFQ that was rejected by the Buyer.
MATCH (su:Supplier)<-[:RFQ_FROM_SUPPLIER]-(rrfq:RFQ)<-[:IS_SUPPLIER_REJECTED_RFQ_STATE]-(), (rrfq)-[:IS_RFQ_FOR_PO]-(po), (p)<-[pq:HAS_PO_ITEM]-(po)-[:HAS_SUPPLIER_NEW_RFQ]->(snr) 
WITH rrfq, su, po, snr, COLLECT({
    Product: p, 
    qty: pq.POqt,              // The Supplier will enter the Quantity of products they will supply in the RFQ
    cost: p.UnitPrice * 0.65   // The Supplier will enter the discount they will provide in their RFQ. As this is a resubmission, the Supplier will provide a better discount than the previous RFQ
}) AS rfqItems ORDER BY rand() LIMIT 1  
CREATE (rfq:RFQ {
    RFQNumber: "RFQ-" + left(randomUUID(), 3) + right(randomUUID(), 3), 
    RFQDate: localdatetime(), 
    RFQComments: "Thanks for your order, we resubmitting our RFQ and hope weare able to supply the full PO product request at the discounted price negotiated on our master agreement"})-[:IS_RFQ_FOR_PO]->(po), // We create the RFQ
(rfq)-[:RFQ_FROM_SUPPLIER]->(su),    // We connect the RFQ to the Suppier 
(snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq),  // We place the RFQ in the PO's new RFQ state collection 
(rfq)-[:HAS_PREVIOUS_RFQ {Justification: "This RFQ is a resubmission of the previous rejected RFQ. The Supplier has provided additional justification and/or updated pricing and/or updated product availability."}]->(rrfq)  // We connect the new RFQ to the previous rejected RFQ for tracking and auditing 
WITH rfq, rfqItems
UNWIND rfqItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (rfq)-[:HAS_RFQ_ITEM {RFQqt: item.qty, RFQcost: item.cost}]->(p);  // We add the RFQ data (product quantity and unit cost) in the Relationship of the RFQ

// We will not vet it yet so we can query it later and see that it is pending vetting. We can vet it in a later step.

// ###### Run the **Inventory Level Report** ######  
// You will see how the Inventory Level changes after the RFQ approval and the updated Supply Order status for the products.
// You will now see that the Supply Order status has been updated to reflect the approved RFQ quantities for each product. 
 

//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// **Update the Stock Threshold**
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

// Check the updated Stock Threshold for each Product before the update of Stock Threshold.
MATCH ()-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]-(in), (p)-[:HAS_SUPPLY_ORDER]->(so), (p)-[:HAS_REORDER_LEVEL]->(re), (p)<-[oi:HAS_ORDER_PRODUCT]-(or)
RETURN p.ProductName, in.UnitsInStock, so.UnitsOnOrder, re.StockThreshold, toInteger((avg(oi.Quantity))) AS AverageQuantityPerOrder, min(oi.Quantity), max(oi.Quantity),count(DISTINCT (toString(or.OrderDate.year) + "-" + toString(or.OrderDate.month))) AS OrdersPerMonth ORDER BY  p.ProductName;


// Update the Stock Threshold based on the average quantity ordered per month for each product. 
// This will help in maintaining optimal inventory levels and ensuring that products are reordered in a timely manner to meet customer demand.
// The following query updates the Stock Threshold to 150% of the average monthly order volume for each Product.
// From time to time, the Stock Threshold can be recalculated based on the latest order data to ensure that it reflects current demand patterns and helps in maintaining optimal inventory levels.

MATCH ()-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_REORDER_LEVEL]->(re)
MATCH (p)<-[oi:HAS_ORDER_PRODUCT]-(o:Order)
WITH p, re,
     sum(oi.Quantity) AS TotalQuantityOrdered,
     count(DISTINCT (toString(o.OrderDate.year) + "-" + toString(o.OrderDate.month))) AS MonthsWithOrders
SET re.StockThreshold = toInteger(round((toFloat(TotalQuantityOrdered) / MonthsWithOrders) * 1.5));


// Check the Stock Threshold for each Product after the update of Stock Threshold.
MATCH ()-[:IS_AVAILABLE_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]-(in), (p)-[:HAS_SUPPLY_ORDER]->(so), (p)-[:HAS_REORDER_LEVEL]->(re), (p)<-[oi:HAS_ORDER_PRODUCT]-(or)
RETURN p.ProductName, in.UnitsInStock, so.UnitsOnOrder, re.StockThreshold, toInteger((avg(oi.Quantity))) AS AverageQuantityPerOrder, min(oi.Quantity), max(oi.Quantity),count(DISTINCT (toString(or.OrderDate.year) + "-" + toString(or.OrderDate.month))) AS OrdersPerMonth ORDER BY  p.ProductName;

// ###### Run the **Inventory Level Report** ######  
// You will see how the updated Stock Threshold affects the creation of new Purchase Orders for products that are below their Stock Threshold.

//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// GOTO **PO Creation**   ;-)
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

// If you wish, after running the above command, run the entire script from **PO Creation** onward. You will see how the updated Stock Threshold affects the creation of new Purchase Orders for products that are below their Stock Threshold.
// New PO's, new PO vetting, new RFQ's, new RFQ vetting, and new product deliveries will be created based on the updated Stock Thresholds.

// I will run the PO Creation command once here so that we can have some new PO's created based on the updated Stock Thresholds.  
// This will be usefull once you run the Python code to simulate the creation of new Orders, PO and RFQ Vetting, Supplier restock, Order Fulfillment, and Inventory Updates.


// The Procurement Assistant will create POs for Suppliers whose Products have low Inventory Levels (nearing restock threashold level).  

// Select a random Employee with the role "Procurement Assistant".
MATCH (pa:RolE {Title: "Procurement Assistant"})-[:IS_ACTIVE_ROLE]->(e:Employee), (n:NewPoS {Name:"NewPoS"})
WITH n, e ORDER BY rand() LIMIT 1
MATCH (s:Supplier)-[:SUPPLIES]->(p:Product)
  <-[:IS_AVAILABLE_PRODUCT]-(a:ProductStatusAvailablE),
  (r:ReorderLevel)<-[:HAS_REORDER_LEVEL]-(p)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)     // Find Products with low inventory (Inventory Level <= Restock Threshold). 
OPTIONAL MATCH (activePO:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p)
WHERE (activePO)<-[:IS_NEW_PO_STATE]-(:NewPoS)
   OR (activePO)<-[:IS_APPROVED_PO_STATE]-(:ApprovedPoS)       // Check if there are any active POs for this product that are either New or Approved (not yet submitted to Supplier)
   OR (activePO)<-[:IS_SUBMITTED_PO_STATE]-(:SubmittedPoS)
WITH e, n, s, p, r, i, SUM(coalesce(poi2.POqt, 0)) AS AlreadyPendingQty
WHERE i.UnitsInStock + AlreadyPendingQty - (r.StockThreshold * 0.5) <= r.StockThreshold
WITH e, n, s, COLLECT({
    Product: p,
    qty: (r.StockThreshold) - (i.UnitsInStock + AlreadyPendingQty) + (r.StockThreshold * 2)
}) AS orderItems
CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {
    PONumber: "PO-" + left(randomUUID(), 3) + right(randomUUID(), 3),
    PODate: localdatetime()
})
CREATE (s)<-[:PO_FOR_SUPPLIER]-(po)     // Connect the PO to the respective Supplier
CREATE (po)-[:PO_CREATED_BY]->(e)       // Connect the PO to the employee that created it
WITH po, orderItems, s                  // Unwind the collected products to create the items for this specific PO
UNWIND orderItems AS item
MATCH (p:Product {ProductID: item.Product.ProductID})
MERGE (po)-[:HAS_PO_ITEM {POqt: item.qty, POPriceDiscount: 0.7}]->(p)   // We add the PO items and their order quantity, in this demo we will get the unit cost as a % of the Product price 
RETURN DISTINCT po.PONumber AS PONumber, s.SupplierID AS SupplierID, size(orderItems) AS ItemCount;


// ###### Run the **Inventory Level Report** ######  
// You will see how the updated Stock Threshold affects the creation of new Purchase Orders for products that are below their Stock Threshold. 
// You will now see that new PO's have been created for Suppliers whose Products have low Inventory Levels (nearing restock threashold level).

//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// **Product Delivery at Warhouse and Inventory Update**
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

// Now that we have some RFQ's approved the respective Suppliers will ship the products. 
// This happens on the Supplier system, hopefully also running on a Graph ;-) - We could potentialy have a Graph-to-Graph (federation) integration between the Supplier and the Procurement system to automate this process.
// On our side, we will have the Warehouse Clerk receive the products and update the Inventory Levels accordingly by updating the Product's UnitsOnOrder and UnitsInStock,
// Once the Warehouse Clerk receives the products, Finance will Pay and close the PO and move it to the Closed state.

// First, we will have the Warehouse Clerk (Employee) receive the products and update the Inventory Levels accordingly.
// We will recive 5 PO's and update the Inventory Levels for the products in those PO's. We will leave a few PO's pending delivery so we can query them later and see that they are pending delivery.
MATCH (wc:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"WarehouseClerk"}), (p)<-[poi:HAS_PO_ITEM]-(po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(rfq:RFQ)-[rfi:HAS_RFQ_ITEM]->(p)-[:HAS_INVENTORY_LEVEL]->(inv), (p)-[:HAS_SUPPLY_ORDER]->(suo)
WHERE poi.POqt = rfi.RFQqt AND NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->() // We only want to receive the products for the PO's that have not been received yet (no Warehouse Delivery yet)
WITH wc, po, rfq, inv, suo, rfi, p ORDER BY po.PONumber LIMIT 5
MERGE (po)-[:HAS_WAREHOUSE_DELIVERY {Date:datetime(), Comment:"The products have been received as per PO at the Warehouse and the Inventory Levels have been updated accordingly."}]->(wc)  // We connect the PO to the Warehouse Clerk that received the products and updated the Inventory Levels
SET  inv.UnitsInStock = inv.UnitsInStock + rfi.RFQqt,  // We update the Inventory Level to reflect the received products
     suo.UnitsOnOrder = suo.UnitsOnOrder - rfi.RFQqt;  // We update the Supply Order status to reflect the received products 



//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// **PO Payment and Closure by Finance**
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//


// Next, Finance will Pay and close the PO and move it to the Closed state on both the Procurement and Supplier perspectives.
// We will pay and close 4 PO's and leave a few pending payment so we can query them later and see that they are pending payment.
MATCH (f:Employee)<-[:IS_ACTIVE_ROLE]-(ro:RolE {Title:"Finance"}), 
(cpo)<-[:HAS_CLOSED_PO_STATE]-(:PoS)-[:HAS_SUBMITTED_PO_STATE]->(:SubmittedPoS)-[r1]->(po:PurchaseOrder)-[:HAS_WAREHOUSE_DELIVERY]->(wc:Employee), 
(po)<-[r2:IS_SUPPLIER_OPEN_PO_STATE]-()<-[]-(su:Supplier)-[:HAS_SUPPLIER_CLOSED_POS]->(scp)
WITH r1, r2, cpo, scp, f, po ORDER BY po.PONumber LIMIT 4
MERGE (po)-[:HAS_FINANCE_PAYMENT {Date:datetime(), Comment:"The PO has been paid by Finance and the PO is now closed."}]->(f)  // We connect the PO to the Finance employee that paid the PO and closed it
MERGE (cpo)-[:IS_CLOSED_PO_STATE {Date:datetime(), Comment:"The PO has been paid by Finance and the PO is now closed."}]->(po)  // We connect the PO to the Closed state on the Procurement perspective
MERGE (scp)-[:HAS_SUPPLIER_CLOSED_PO_STATE {Date:datetime(), Comment:"The PO has been paid by Finance and the PO is now closed."}]->(po)  // We connect the PO to the Closed state on the Supplier perspective
DELETE r1, r2;  // We remove the PO from the Submitted state on the Procurement perspective and from the Open state on the Supplier perspective



//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// **Customer Order Fulfillment**
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//


// The Warehouse Clerk will fulfill Open Customer Orders that have sufficient stock for every Product line, ship them, and update the Inventory Levels accordingly. Orders missing stock for 
// one or more Products are skipped and remain Open, pending restock -- we don't want to fulfill a partial Order or push Inventory negative.

// Select the Warehouse Clerk and a Shipper who will handle this batch of fulfillments.
// (Same disconnected-pattern Cartesian product warning noted earlier in the script -- harmless here since we cap it to one Employee and one Shipper via ORDER BY rand() LIMIT 1.)
MATCH (wc:Employee)<-[:IS_ACTIVE_ROLE]-(:RolE {Title:"WarehouseClerk"}), (s:Shipper)
WITH wc, s ORDER BY rand() LIMIT 1

// Find Open Orders where every Product line has sufficient stock (all lines must pass, not just some).
MATCH (op:OrderStatusOpeN {Status:"Open"})-[r:IS_OPEN_ORDER_STATE]->(o:Order)-[details:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
WITH wc, s, op, r, o, count(details) AS TotalLines, sum(CASE WHEN inv.UnitsInStock >= details.Quantity THEN 1 ELSE 0 END) AS LinesWithStock
WHERE TotalLines = LinesWithStock
WITH wc, s, op, r, o ORDER BY o.OrderDate LIMIT 5   // oldest Open Orders first; leave the rest Open for later querying

// Ship and fulfill each selected Order.
MATCH (a)<-[:HAS_CUSTOMER_ADDRESS]-(:Customer)<-[:HAS_ORDER_CUSTOMER]-(o), (f:OrderStatusFulfilleD {Status:"Fulfilled"})
CREATE (i:ShipInfo {ShippmentID:randomUUID(), ShippedDate:date()})
CREATE (o)-[:HAS_SHIPMENT_INFO]->(i)
CREATE (i)-[:HAS_SHIPPER]->(s)
CREATE (i)-[:HAS_SHIPMENT_ADDRESS]->(a)
CREATE (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: datetime()}]->(o)
CREATE (o)-[:HAS_WAREHOUSE_FULFILLMENT {Date:datetime(), Comment:"Order picked, packed, and shipped by the Warehouse Clerk."}]->(wc)
DELETE r
WITH o

// *** Isotope exception (see full rationale at "Updating Inventory After Order Fulfillment" above). ***
MATCH (o)-[details:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
SET inv.UnitsInStock = inv.UnitsInStock - details.Quantity,
    inv.LastUpdate = datetime();

 
// ###### Run the **Inventory Level Report** ######  
// You will see how the Inventory Level changes after the Order Fulfillment and the updated Supply Order status for the products.


//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// And we conclude our 360-degree script initialization process!
// All initial data has been imported from the original NorthWind dataset; it has been normalized to fit this New Graph-Native Approach, and all Domain Collections have been created. 
// The new NorthWind Graph Data Model has been tested, and it is ready to be stressed  
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//



// Now, get the Python script NorthwindPlus_Stress_Test.py and run it to simulate the creation of new Orders, PO and RFQ Vetting, Supplier restock, Order Fulfillment, and Inventory Updates.

// The loops are the following: 

// python NorthwindPlus_Stress_Test.py --loop customer-order --rate 6 & 

  // To visualize on the Graph console the new Orders that were created and fulfilled today.
  MATCH (superset:OrderS)-[edge]->(os)
  OPTIONAL MATCH path = (os)-[]->(o:Order)
   WHERE duration.inDays(o.OrderDate, datetime()).days = 0
   RETURN superset, edge, os, path;

// python NorthwindPlus_Stress_Test.py --loop po-creation --rate 2 &
// python NorthwindPlus_Stress_Test.py --loop po-vetting --rate 4 &

  // To visualize in the Graph console the new POs that were created, approved, submitted, and closed today.
  MATCH (superset:PoS)-[edge]->(collection)
  OPTIONAL MATCH path = (collection)-[]->(po:PurchaseOrder)
   WHERE duration.inDays(po.PODate, datetime()).days = 0
   RETURN superset, edge, collection, path; 

// python NorthwindPlus_Stress_Test.py --loop rfq-vetting --rate 4 &
// python NorthwindPlus_Stress_Test.py --loop warehouse-finance --rate 4 &
// python NorthwindPlus_Stress_Test.py --loop order-fulfillment --rate 4 &


// NOTE:   --rate is executions per minute. Adjust them as you like. 
// For instance, for PO creation, a longer interval might make more sense (e.g., 0.1 = every 10 minutes) so you don't get PO's ordering small quantities of products 


// STEPS to run them (presuming you have Python installed):

// 1) Set up your Neo4j Aura Database instance, if you don't have one yet. Retrieve the Aura instance credentials: 
//    NEO4J_URI=
//    NEO4J_USERNAME= 
//    NEO4J_PASSWORD= 
//    NEO4J_DATABASE= 

// 2) Update the PySetup.bat file provided with the Neo4j Cedentials (Optionally, you can change the Loop --rate from the default provided  )
// 3) Open the Command Line Interface (CLI) 
// 4) Install the Neo4j interface (if you haven't done so):  pip install neo4j
// 5) Run the PySetup.bat batch file - This will set up the proper environment variables and open 6 different windows
// 6) Arrange the 6 windows so you can see all separately
// 7) Start each independent Loop by pressing ENTER (Press Ctrl+C to STOP the Loop at any moment and wait for it to end)   


// As the Loops run independently, go to the Neo4j Query Console and run some queries
// ###### Run the **Inventory Level Report** ######  
// You will see how the Inventory Levels change as the loops run.

// This will create a continuous stream of new Orders, PO and RFQ Vetting, Supplier restock, Order Fulfillment, and Inventory Updates. 
// You can play with the rates of each loop to simulate different scenarios and see how the system behaves under different loads.
// Practice your Cypher skills and try to extract insights from the data. You can also try creating your own queries and see how they perform on the NorthWind Graph Data Model (in real time!!!).

// Isn't that amazing?!?!

// Feel free to extend the Model and add additional context/semantic/knowledge layers. 
// A good example is the recommendation engine below; it adds a new layer of context to the model. It can be used to recommend products to customers based on their purchase history and the purchase histories of other customers.
// It does not affect the core model and can be added as a new layer of context/semantics/knowledge to the model. 
// Like that one, you can add as many layers of context/semantics as you want to the model and create a rich and complex graph data model that can be used to extract insights and make better decisions. In real-time!! 
// It is a dynamic and ever-changing environment that you can keep querying and adjusting.


// Notice that by the end of this script, the proportion of nodes to relationships (edges) is roughly 1:3.27, which is a significant characteristic of this graph model.
// If we create another 50 customer orders, the proportion of nodes to relationships (edges) will roughly grow to 1:3.38.
// The model grows in "knowledge" more than "data", as the relationships between the nodes represent the knowledge.
// As you keep running the script and creating new Orders, PO and RFQ Vetting, Supplier restock, Order Fulfillment, and Inventory Updates, etc., you will see how the graph grows mostly on the relationships 
// (edges) than on the nodes themselves. The only nodes that will grow in number are the Customer Orders, PurchaseOrder, and RFQ. The rest of the nodes will remain the same. 
// If you add additional context layers, you will likely add more "knowledge" to the model.

// Now ask yourself, what if your business was running on a Graph Database and you could query it in real-time to extract insights and make better decisions without having to wait
// for batch processing jobs or complex and expensive ETL pipelines to run to only then query the data to extract insights and make better decisions.
// Look at the Python code to see how it creates new Orders, PO and RFQ Vetting, Supplier restock, Order Fulfillment, and Inventory Updates in real time with minimal coding.
// The Python code is mostly scaffolding to orchestrate Cypher commands and simulate what humans or AI Agents would do. 
// Think of all the possibilities to introduce AI Agents to automate parts of the process, all within a controlled and governed Ontology setting the guardrails 
// so AI does not go rogue and make decisions that are not aligned with the business goals and objectives. 
// You could even have a library of pre-validated Cypher commands for each business function and have your AI Agents pick from them rather than giving them freedom to build their own without your validation.  
// And here is the interesting part: If you provide your AI with this Script, plus the companion RDF and GRAPH TYPE files, your AI will help you create the Cypher commands for you to validate, tweak, or perfect. 

// THIS IS THE FUTURE OF AI-ENABLED BUSINESS APPLICATIONS AND DATA MANAGEMENT, AND IT IS HAPPENING NOW!!!!!!

//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//


//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// Recommendation Engine based on the Neo4j NorthWind Recommendation Engine GraphGist, adapted for the NorthWind Application Graph Data Model (and Cypher Version 5).
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//


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
	SUM(r1.Rating*r2.Rating) as dot_product,
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




//--------------------------------------------------------------------------------------------------------------------------------------------------------------//
// Query Examples to Run Against the NorthWind Graph Data Model 
// These are examples of queries that can be used to extract insights from the NorthWind Graph Data Model.
//--------------------------------------------------------------------------------------------------------------------------------------------------------------//

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

// Products Never Ordered by a Customer
MATCH (p:Product)
WHERE NOT (p)<-[:HAS_ORDER_PRODUCT]-(:Order)
RETURN p.ProductName;

// Products Currently Below Restock Threshold, with their Supplier
MATCH (p:Product)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel), (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel), (p)-[:HAS_PRODUCT_SUPPLIER]->(s:Supplier)
WHERE i.UnitsInStock <= r.StockThreshold
RETURN p.ProductName, i.UnitsInStock, r.StockThreshold, s.CompanyName AS Supplier
ORDER BY i.UnitsInStock ASC;

// At-Risk Products -- below Restock Threshold with NO Purchase Order currently in flight to resupply them
MATCH (p:Product)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel), (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel)
WHERE i.UnitsInStock <= r.StockThreshold
OPTIONAL MATCH (po:PurchaseOrder)-[:HAS_PO_ITEM]->(p)
WHERE (po)<-[:IS_NEW_PO_STATE]-(:NewPoS) OR (po)<-[:IS_APPROVED_PO_STATE]-(:ApprovedPoS) OR (po)<-[:IS_SUBMITTED_PO_STATE]-(:SubmittedPoS)
WITH p, i, r, count(po) AS InFlightPOs
WHERE InFlightPOs = 0
RETURN p.ProductName, i.UnitsInStock, r.StockThreshold
ORDER BY i.UnitsInStock ASC;

// Supplier Reliability -- RFQ Rejection Rate
MATCH (s:Supplier)<-[:RFQ_FROM_SUPPLIER]-(rfq:RFQ)
WITH s, count(rfq) AS TotalRFQs,
     count(CASE WHEN (rfq)<-[:IS_SUPPLIER_REJECTED_RFQ_STATE]-() THEN 1 END) AS RejectedRFQs
WHERE TotalRFQs > 0
RETURN s.CompanyName, TotalRFQs, RejectedRFQs, round(100.0 * RejectedRFQs / TotalRFQs, 1) AS RejectionRatePct
ORDER BY RejectionRatePct DESC;

// PO Rejection Value by Approval Level -- where is procurement friction concentrated?
MATCH (po:PurchaseOrder)-[r:HAS_L1_PO_REJECTION|HAS_L2_PO_REJECTION|HAS_L3_PO_REJECTION]->(:Employee), (po)-[poi:HAS_PO_ITEM]->(p:Product)
WITH type(r) AS RejectionLevel, po, SUM(poi.POqt * (p.UnitPrice * poi.POPriceDiscount)) AS POCost
RETURN RejectionLevel, count(DISTINCT po) AS RejectedPOs, round(SUM(POCost), 2) AS TotalRejectedValue
ORDER BY TotalRejectedValue DESC;

// Approval Workload by Employee -- who is doing the most PO/RFQ vetting?
MATCH (e:Employee)<-[r:HAS_L1_PO_APPROVAL|HAS_L2_PO_APPROVAL|HAS_L3_PO_APPROVAL|HAS_L1_PO_REJECTION|HAS_L2_PO_REJECTION|HAS_L3_PO_REJECTION|HAS_BUYER_RFQ_APPROVAL|HAS_BUYER_RFQ_REJECTION]-()
RETURN e.EmployeeID, count(r) AS ActionsTaken
ORDER BY ActionsTaken DESC;

// Open Customer Orders currently blocked, waiting on Product Inventory to fulfill
MATCH (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(o:Order)-[details:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel), (o)-[:HAS_ORDER_CUSTOMER]->(c:Customer)
WITH c, o, collect({ProductName: p.ProductName, Ordered: details.Quantity, InStock: inv.UnitsInStock, Shortfall: details.Quantity - inv.UnitsInStock}) AS lines
WITH c, o, [line IN lines WHERE line.Shortfall > 0] AS blockingProducts
WHERE size(blockingProducts) > 0
RETURN c.CompanyName AS Customer, o.OrderID, o.OrderDate, blockingProducts
ORDER BY o.OrderDate ASC;

// Products Urgently Needed to Fulfill Blocked Customer Orders (Might influence vetting proecess of new Purchase Orders and/or RFQ's)
MATCH (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(o:Order)-[details:HAS_ORDER_PRODUCT]->(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel)
WHERE details.Quantity > inv.UnitsInStock
WITH p, inv, count(DISTINCT o) AS BlockedOrders, sum(details.Quantity - inv.UnitsInStock) AS TotalUnitsShort
OPTIONAL MATCH (po:PurchaseOrder)-[:HAS_PO_ITEM]->(p)
WHERE (po)<-[:IS_NEW_PO_STATE]-(:NewPoS) OR (po)<-[:IS_APPROVED_PO_STATE]-(:ApprovedPoS) OR (po)<-[:IS_SUBMITTED_PO_STATE]-(:SubmittedPoS)
WITH p, inv, BlockedOrders, TotalUnitsShort, count(po) AS POsAlreadyInFlight
RETURN p.ProductName, inv.UnitsInStock, BlockedOrders, TotalUnitsShort, POsAlreadyInFlight
ORDER BY TotalUnitsShort DESC;

// Full Resubmission Lineage -- how many times has a Purchase Order's line item journey been rejected and resubmitted?
// This is the kind of query that needs a recursive CTE (or isn't supported at all) in most relational databases --
// here it's a one-line variable-length path traversal.
MATCH chain = (latest:PurchaseOrder)-[:HAS_PREVIOUS_PO*1..]->(original:PurchaseOrder)
WHERE NOT ()-[:HAS_PREVIOUS_PO]->(latest)
RETURN latest.PONumber AS CurrentPO, original.PONumber AS OriginalPO, length(chain) AS TimesRejectedAndResubmitted
ORDER BY TimesRejectedAndResubmitted DESC;

// Full Context Trace for a single Purchase Order -- everything within 2 hops (edit PONumber).
// Run this one on the Graph console: it visually shows every Employee, Supplier, RFQ, Product, and
// state Collection touching one PO, without a single JOIN or ETL step -- the graph IS the answer.
MATCH path = (po:PurchaseOrder {PONumber:"PO-XXXXXXX"})-[*1..2]-(connected)
RETURN path;

// Product Recommendation for Customers Based on the Most-Ordered Products by Other Customers (if you ran the Recommendation Engine commands earlier )
MATCH (c:Customer)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_PRODUCT]->(p:Product)
<-[:HAS_ORDER_PRODUCT]-(o2:Order)-[:HAS_ORDER_PRODUCT]->(p2:Product)<-[:IS_PRODUCT_CATEGORY_OF]-(:ProductCategorY)-[:IS_PRODUCT_CATEGORY_OF]->(p)
WHERE c.CustomerID = 'ANTON' and NOT( (c)<-[:HAS_ORDER_CUSTOMER]-(:Order)-[:HAS_ORDER_PRODUCT]->(p2) )
RETURN c.CompanyName, p.ProductName AS has_purchased, p2.ProductName AS has_also_purchased, count(DISTINCT o2) AS occurrences
ORDER BY occurrences DESC
LIMIT 5;

// The Inventory Level Report (again)
// To visualize the Product's Inventory Levels, Supply Orders (RFQ Approved) pending fulfilment, Stock Threashold, Open Customer Orders and Open PO's to resupply from Today on the Graph console, use the following query:
  // Product Supply/Demand Dashboard -- one row per Product, ordered by name
  MATCH ()-[:IS_AVAILABLE_PRODUCT]-(p:Product)-[:HAS_INVENTORY_LEVEL]->(inv:InventoryLevel),
        (p)-[:HAS_REORDER_LEVEL]->(r:ReorderLevel),
        (p)-[:HAS_SUPPLY_ORDER]->(suo:OrderLevel)
  // Open Customer Order demand for this Product
  OPTIONAL MATCH (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(o:Order)-[details:HAS_ORDER_PRODUCT]->(p)
  WITH p, inv, r, suo,
       count(DISTINCT o) AS OpenCustomerOrders,
       coalesce(sum(details.Quantity), 0) AS QtyDemanded
  // Quantity confirmed by an approved RFQ, not yet delivered by the Warehouse
  OPTIONAL MATCH (po:PurchaseOrder)-[:HAS_APPROVED_RFQ]->(:RFQ)-[rfi:HAS_RFQ_ITEM]->(p)
  WHERE NOT (po)-[:HAS_WAREHOUSE_DELIVERY]->()
  WITH p, inv, r, suo, OpenCustomerOrders, QtyDemanded,
       coalesce(sum(rfi.RFQqt), 0) AS QtyApprovedRFQPendingDelivery
  // Quantity requested via an open PO that does NOT yet have an approved RFQ
  // (excluded here to avoid double-counting the same units already captured above)
  OPTIONAL MATCH (po2:PurchaseOrder)-[poi2:HAS_PO_ITEM]->(p)
  WHERE ((po2)<-[:IS_NEW_PO_STATE]-(:NewPoS)
      OR (po2)<-[:IS_APPROVED_PO_STATE]-(:ApprovedPoS)
      OR (po2)<-[:IS_SUBMITTED_PO_STATE]-(:SubmittedPoS))
    AND NOT (po2)-[:HAS_APPROVED_RFQ]->(:RFQ)
  WITH p, inv, r, suo, OpenCustomerOrders, QtyDemanded, QtyApprovedRFQPendingDelivery,
       coalesce(sum(poi2.POqt), 0) AS QtyOpenPOsNotYetConfirmed
  RETURN p.ProductName AS ProductName,
         inv.UnitsInStock AS UnitsInStock,
         r.StockThreshold AS StockThreshold,
         suo.UnitsOnOrder AS UnitsOnOrder_Tracked,
         QtyApprovedRFQPendingDelivery AS QtyApprovedRFQPendingDelivery,
         QtyOpenPOsNotYetConfirmed AS QtyOpenPOsNotYetConfirmed,
         (QtyApprovedRFQPendingDelivery + QtyOpenPOsNotYetConfirmed) AS TotalIncomingQty,
         OpenCustomerOrders AS OpenCustomerOrders,
         QtyDemanded AS QtyDemanded
  ORDER BY ProductName;

//  End of Query Examples  //

// I invite you to explore the NorthWind Graph Data Model and create your own queries to extract insights from the data.