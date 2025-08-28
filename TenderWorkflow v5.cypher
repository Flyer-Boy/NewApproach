// This Cypher script simulates a simplified Tendering System Proof of Concept (POC) featuring three distinct workflows: Vendor vetting, Tender vetting, and Bid vetting. 
// It includes the interactions between these workflows, as well as AI Agent iterations and conversations between various stakeholders. All in the Graph!
// The simulation starts from an empty Graph and progressively builds out, simulating 130+ user/database interactions using Cypher commands that 20+ users would typically execute through their respective UIs.
// This script simulates the creation of 19 employees, 6 Roles, 10 Vendors with respective Contact persons, 13 Tenders, and 6 Bids, along with all the respective vetting processes and interactions between parties. 

// Purpose:
// The goal of this POC is to demonstrate that Graph databases can effectively power Line-of-Business (LOB) applications, such as workflow systems, in addition to traditional Knowledge Graphs or Graph RAG (Retrieval-Augmented Generation) solutions. 
// It also showcases an alternative development approach to conventional RDBMS-based applications, leveraging the unique strengths of Graphs. 
//
// !! The script illustrates how Graphs can serve as both the DATA LAYER and the EXECUTION ENGINE/LOGIC LAYER for business applications, enabling a more intuitive and efficient development process. !!


// While this example focuses on a Tendering system, the underlying principles apply to any workflow-based system.
// Considering that an estimated 70% to 90% of all Line-of-Business (LOB) applications (e.g., HR systems, CRM, ERP, Customer Support, Compliance) involve workflows,
// This highlights the significant untapped potential for adopting Graph-Native systems in business application development.
// This approach has the potential to be a true game changer.

// Note: This is not a fully functional Tendering Solution. The script was developed in approximately four days and is intended purely as a conceptual demonstration. 
//       There is room for improvement, enhancements, and optimization, and there are probably some errors/bugs/typos, but the core idea holds. 
//       I will keep enhancing it, so by the time you read this, there might be an improved version. 

// This model was built using a "mathematical set ontology", where:
// -  Super-Collections (e.g. TenderS, VendorS, etc.) = universal sets,
// -  Collections (States) (e.g. NewTenderS, ApprovedVendorS, etc.) = subsets,
// -  Entities (e.g. Tender {…}, Vendor {…}, etc.) = elements of these sets,
// -  Edges with name "HAS" = membership operator (∈).
// -  Therefore: Entity ∈ Collection ⊆ Super-Collection
// -  Edges with name <> "HAS" folow normal ontology
//
//    This is an elegant way to makes lifecycle management explicit in graph structure rather than hidden in properties.
//    Providing mathematical clarity, LLM interpretation/reasoning and optimized for UI Component reusabilty ("HAS" = ∈ for all UI components that handle Collections)

// Key Principles (Design Goals):
// 1)	Proper Noun Nodes:
//      Nodes should only store properties that are immutable — those that define the uniqueness of the entity (the "Thing") and should never change.
//      Any property that represents a state or relevance to another entity should be modelled as a relationship, not a node property.

// 2)	Read-Only Nodes:
//      Once created, node properties remain unchanged. (The SET command is reserved strictly for value corrections).
//      This approach significantly simplifies transaction concurrency and consistency management, which is a major differentiator from traditional RDBMS models where updates are common and often introduce complexity (concurrency & consistency).

// 3)	Never Delete Nodes:
//      Nodes are never deleted, ensuring full traceability of all entities over time. 
//      (Time flows in one direction. What is done cannot be undone. If the model is a faithful representation of the real world, this principle should be respected.)

// 4)	Relationships Drive the System (workflow):
//      The system relies on creating new nodes and relationships, and deleting relationships as per the workflow rules/state.

// 5)	Lean Nodes:
//      Outgoing relationships are minimized. For one-to-many connections, we use Collections.
//      While this introduces an additional traversal cost, the structure scales better as the database grows.
//      (There’s a deeper explanation behind this, and considerations about the incoming relationships, but I won’t go down that rabbit hole here.)


// Key Advantages:
// 1.	Model Symmetry with the real world:
//      The Graph model closely mirrors the real-world domain model, enabling domain experts to easily understand (intuitive mental model), build, and evolve it without requiring deep technical skills.

// 2.	Common Ground:
//      Both developers (solution domain) and business stakeholders (problem domain) can collaborate directly on the model, without the need for complex translations or intermediaries.
//      In an ideal scenario, the modelling process would be collaborative, involving both a Business domain expert and an Interaction designer with a development background.

// 3.	Low-Code Development:
//      Aside from the UI layer, minimal coding is required. Most of the application logic is embedded within the Graph itself and executed through Cypher, reducing development time and complexity.

// 4.	AI-Ready by Design:
//      The Graph naturally captures both information and context from the outset, making it immediately usable and comprehensible by AI agents. No additional data wrangling or restructuring needed.

// 5.   Built-in real-time Knowledge Graph
//      Built on a Graph for business insights and all the amazing things Knowledge Graphs provide (No need to ingest data) 
//


// Walkthrough:

// You can run the entire script at once (it takes approximately 30 seconds to execute) to see and study the final resulting Graph, 
// and then re-execute it step-by-step (or in batches) to observe how the Graph evolves (executes the logic) with each interaction/iteration by dynamically changing the relationships between the Nodes.
// I’ve included comments in the script to explain what’s happening at each phase. I hope you find them helpful.
// I don't expect you to understand everything at once, but I hope you can follow the logic and see how the Graph evolves with each step.
// Take your time to explore the approach as it is very different from traditional RDBMS-based applications' logic. So it might take a while to get used to it.
// I am sure you will have a natural resistance to this approach at first. But don't let that discourage you. Please keep an open mind and try to understand the logic behind it.
// Once you get the hang of it, you will see how powerful and flexible this approach is, and you might never want to go back to the old way of doing things.

// ----- Enjoy! (If you want to discuss or learn more, you can reach out to me at marcos.pinedo@outlook.com or https://www.linkedin.com/in/marcospinedo/) -----
// ----- You can also read more about this approach in many articles I have published at https://medium.com/@marcospinedo -----


// -----  Here we go!!!  ----- 

// Before we start, let's clear all Nodes and relationships and drop all constraints    
 
MATCH (n) DETACH DELETE n; 

DROP CONSTRAINT unique_TenderS IF EXISTS;
DROP CONSTRAINT unique_NewTenderS IF EXISTS;
DROP CONSTRAINT unique_ApprovedTenderS IF EXISTS;
DROP CONSTRAINT unique_RejectedTenderS IF EXISTS;
DROP CONSTRAINT unique_AwarderTenderS IF EXISTS;
DROP CONSTRAINT unique_ClosedTenderS IF EXISTS;

DROP CONSTRAINT unique_TenderTypeS IF EXISTS;
DROP CONSTRAINT unique_TenderType IF EXISTS;

DROP CONSTRAINT unique_mployeeDirectorY IF EXISTS;

DROP CONSTRAINT unique_RoleS IF EXISTS;
DROP CONSTRAINT unique_Role IF EXISTS;

DROP CONSTRAINT unique_VendorS IF EXISTS;
DROP CONSTRAINT unique_PendingVendorS IF EXISTS;
DROP CONSTRAINT unique_ApprovedVendorS IF EXISTS;
DROP CONSTRAINT unique_RejectedVendorS IF EXISTS;

DROP CONSTRAINT unique_Vendor IF EXISTS;
DROP CONSTRAINT unique_Tender IF EXISTS;
DROP CONSTRAINT unique_Bid IF EXISTS;

// ---------- Domain Collections 

// About Collections as Nodes
// The primary purpose of using Collections as Nodes is to align the Graph structure with the mental model of the domain expert, even though this comes at the cost of additional traversals.
// (Yes, Collections could technically be replaced by direct relationships or adding Labels, but this design improves model clarity and usability besides other considerations - Principle #5.)

// In this approach, Collections are nodes like any other node in the Graph, but instead of representing individual Things, they represent Sets of Things.
// This is what I called "mathematical set ontology" in the script intro.

// Collections can serve two key purposes:
// 1) State Representation:
//    Collections can represent States, based on the entities they contain at a given time.
// 2) Grouping Similar Entities:
//    Collections can also represent groups or sets of similar nodes that function as supersets or subsets. This is a way of reducing the outgoing relationships of key nodes (one to many) 

// Naming Convention:
// You can identify Collection Nodes by their labels. 
// In this model, Collection labels always start and end with capital letters — CamelCase with a capital letter at the end (e.g., CollectioN).

// Consistent Relationship:
// I intentionally use the same relationship type, [:HAS], to represent all "contained-in" connections between Collections and their items.
// Yes, this is a deliberate overuse of [:HAS], but it greatly simplifies:
// 1) The modelling process
// 2) The design of reusable UI components

// This design choice allows us to create reusable UI components that can handle any Collection, regardless of its type or content.
// It also enables us to create generic Cypher queries that can retrieve any Collection and its items, regardless of the specific domain or context.
// I’d be happy to discuss this design choice further if you’re interested. It is not compulsory, but it is a good practice to follow. There are pros and cons, but I believe the pros outweigh the cons in this case.

// There is only one occurrence of Domain Collections in the entire Graph. 
// (When including them in the MATCH clause, you will often get a warning that this might create a Cartesian product. It won't, as there is only one occurrence of these Node Labels in the Graph.)

// There are two ways of implementing this: 1) Different Node Label or 2) Common Node Label but different Property. 
// There are Pros and Cons, and probably depending on the Graph Database implementation and optimization, one could be better than the other.   
// As both methods work, I will use both cases in this Demo: 

// For Tenders states I will use different Node Labels and Name  
// Create the Tender Domain Collections Nodes
CREATE (t:TenderS {Name: "TenderS"})-[:HAS]->(:NewTenderS {Name: "NewTenderS"}),
       (t)-[:HAS]->(:ApprovedTenderS {Name: "ApprovedTenderS"}),
       (t)-[:HAS]->(:RejectedTenderS {Name: "RejectedTenderS"}),
       (t)-[:HAS]->(:PublishedTenderS {Name: "PublishedTenderS"}),
       (t)-[:HAS]->(:AwardedTenderS {Name: "AwardedTenderS"}),
       (t)-[:HAS]->(:ClosedTenderS {Name: "ClosedTenderS"});
       
CREATE CONSTRAINT unique_TenderS IF NOT EXISTS
FOR (t:TenderS)
REQUIRE t.Name IS UNIQUE; 

CREATE CONSTRAINT unique_NewTenderS IF NOT EXISTS
FOR (t:NewTenderS)
REQUIRE t.Name IS UNIQUE; 

CREATE CONSTRAINT unique_ApprovedTenderS IF NOT EXISTS
FOR (t:ApprovedTenderS)
REQUIRE t.Name IS UNIQUE; 

CREATE CONSTRAINT unique_RejectedTenderS IF NOT EXISTS
FOR (t:RejectedTenderS)
REQUIRE t.Name IS UNIQUE; 

CREATE CONSTRAINT unique_AwardedTenderS IF NOT EXISTS
FOR (t:AwardedTenderS)
REQUIRE t.Name IS UNIQUE; 

CREATE CONSTRAINT unique_ClosedTenderS IF NOT EXISTS
FOR (t:ClosedTenderS)
REQUIRE t.Name IS UNIQUE; 


// For Tender Types I will use a Common Label (:TenderType) and different Property ({Name})
//Create the Tender Types
CREATE (ty:TenderTypeS {Name: "TenderTypeS"})-[:HAS]->(:TenderType {Name: "Open", Description: "Open Tender", Rules: "Open to all vendors"}),
         (ty)-[:HAS]->(:TenderType {Name: "Selective", Description: "Selective Tender", Rules: "Only selected vendors can bid"}),
         (ty)-[:HAS]->(:TenderType {Name: "Negotiated", Description: "Negotiated Tender", Rules: "Negotiation with selected vendors"}),
         (ty)-[:HAS]->(:TenderType {Name: "Framework", Description: "Framework Tender", Rules: "Long-term agreement with selected vendors"}),
         (ty)-[:HAS]->(:TenderType {Name: "DirectAward", Description: "Direct Award Tender", Rules: "Directly awarded to a vendor without bidding"});
 

CREATE CONSTRAINT unique_TenderTypeS IF NOT EXISTS
FOR (t:TenderTypeS)
REQUIRE t.Name IS UNIQUE; 

CREATE CONSTRAINT unique_TenderType IF NOT EXISTS
FOR (t:TenderType)
REQUIRE t.Name IS UNIQUE; 



// Create the Employee Directory Domain Collections Node for our Demo (In real life, this will come from the Company's Active Directory or other systems)
CREATE (ed:EmployeeDirectorY {Name: "EmployeeDirectorY"});

CREATE CONSTRAINT unique_mployeeDirectorY IF NOT EXISTS
FOR (e:TmployeeDirectorY)
REQUIRE e.Name IS UNIQUE; 

// For Roles I will use a Common Label (:Role) and different Property ({Name})
// Create the Employee Roles Domain Collection Nodes
CREATE (r:RoleS {Name: "RoleS"})-[:HAS]->(:Role {Name: "Requester", Description: "Requester", Rules: "Requests Tenders"}),
       (r)-[:HAS]->(:Role {Name: "VendorApprover", Description: "Vendor Approver", Rules: "Approves Vendors"}),
       (r)-[:HAS]->(:Role {Name: "Level1Approver", ApprovalBase: 0, ApprovalLimit: 200000, Description: "Level 1 Approver", Rules: "Approves Tenders with a Budget < 200000"}),
       (r)-[:HAS]->(:Role {Name: "Level2Approver", ApprovalBase: 200001, ApprovalLimit: 300000, Description: "Level 2 Approver", Rules: "Approves Tenders with a Budget < 300000"}),
       (r)-[:HAS]->(:Role {Name: "Level3Approver", ApprovalBase: 300001,ApprovalLimit: 2000000, Description: "Level 3 Approver", Rules: "Approves Tenders with a Budget < 2000000"}),
       (r)-[:HAS]->(:Role {Name: "Publisher" , Description: "Publisher", Rules: "Publishes Tenders"});

// So here we have a superset Collection Node (:RoleS) that contains all the subset Role Collection Node as well.
// This allows us to have a single point of reference for all Roles in the system, and we can easily add or remove Roles as needed.
// All employees that are elements of a given Role Collection "(:Role {Name:"Requester"})-[:HAS]->(:Employee)" will have that Role. 
// The employee can have multiple Roles, as they can be part of multiple Role Collections.
// You are probably wondering why I don't create an outgoing relationship from the Employee to the Role, to build the Role hierarchy.
// The reasons are: 
// 1) The Roles are set by another system, and therefore set by an incoming relationship where the employee has no right* to change them. 
// 2) I want to avoid having a many-to-many relationship between Employees and Roles, as this would complicate the model and the queries (Principle #5).
// 3) I want to keep the model simple and easy to understand for the domain expert.
// 4) I want to keep the model flexible and adaptable to changes, as the Roles can change over time.
// * There is a deeper explanation behind this, and considerations about rights management and incoming relationships, but I won’t go down that rabbit hole here.


CREATE CONSTRAINT unique_RoleS IF NOT EXISTS
FOR (r:RoleS)
REQUIRE r.Name IS UNIQUE; 

CREATE CONSTRAINT unique_Role IF NOT EXISTS
FOR (r:Role)
REQUIRE r.Name IS UNIQUE; 

// For Vendors states I will use different Node Labels and Name  
//Create the Vendor Domain Collection Nodes
CREATE (v:VendorS {Name: "VendorS"})-[:HAS]->(:PendingVendorS {Name: "PendingVendorS"}),
       (v)-[:HAS]->(:ApprovedVendorS {Name: "ApprovedVendorS"}),
       (v)-[:HAS]->(:RejectedVendorS {Name: "RejectedVendorS"});
       
CREATE CONSTRAINT unique_VendorS IF NOT EXISTS
FOR (v:VendorS)
REQUIRE v.Name IS UNIQUE; 

CREATE CONSTRAINT unique_PendingVendorS IF NOT EXISTS
FOR (v:PendingVendorS)
REQUIRE v.Name IS UNIQUE;

CREATE CONSTRAINT unique_ApprovedVendorS IF NOT EXISTS
FOR (v:ApprovedVendorS)
REQUIRE v.Name IS UNIQUE;

CREATE CONSTRAINT unique_RejectedVendorS IF NOT EXISTS
FOR (v:RejectedVendorS)
REQUIRE v.Name IS UNIQUE;

// Now that we have the Domain Collections Nodes created, we can start creating the Employees and Vendors, and then the Tenders and Bids.

// --------- Employees & Roles

// Create 19 Employees and link them to the Employee Directory Node (this will likely come from the Company's Active Directory and use SSO to authenticate the users).
// The first 13 are Requesters (Alber, Brandon, Charles, Donald, Eduard, Fred, Gilbert, Harold, Ingrid, Juliet, Keneth, Marlon, Nelson),
// Robert and Mary are Vendor Approvers, 
// Gloria is a Level 1 Approver, Sara is a Level 2 Approver, and Christine is a Level 3 Approver, 
// Cloe is the Publisher
// For demo purposes, I will add a relationship to another node that will state the Employee's role (Approver and Publisher) in the Tender Workflow. 
// We avoid adding roles as Properties to the Employee Node, as this dynamic property can change over time
// Ideally, we only use Properties for static data that will not change over time. (This is a core principle)
// We will assign a role by creating a relationship between the Employees and the Role using a HAS_ROLE relationship.

// Employees & Roles

// Now we can create the Employees and link them to the Employee Directory Node and the Roles Nodes
MATCH  (ed:EmployeeDirectorY {Name: "EmployeeDirectorY"}), (rq:Role {Name: "Requester"})
CREATE  (ed)-[:HAS]->(e1:Employee {Name: "Albert", ID: "S12345678N", Phone: "443344331", Email: "Albert@email.com" , Photo: "/src/assets/images/People/4139948.png" })<-[:HAS]-(rq),
        (ed)-[:HAS]->(e2:Employee {Name: "Brandon", ID: "S84765968N", Phone: "944453321", Email: "Brandon@email.com" , Photo: "/src/assets/images/People/4139993.png"})<-[:HAS]-(rq), 
        (ed)-[:HAS]->(e3:Employee {Name: "Charles", ID: "S324538736N", Phone: "997766544", Email: "Charles@email.com" , Photo: "/src/assets/images/People/4140050.png"})<-[:HAS]-(rq), 
        (ed)-[:HAS]->(e4:Employee {Name: "Donald", ID: "S67828333N",  Phone: "944455541", Email: "Donald@email.com" , Photo: "/src/assets/images/People/4140057.png"})<-[:HAS]-(rq),  
        (ed)-[:HAS]->(e5:Employee {Name: "Eduard", ID: "S98376432N",  Phone: "955445551", Email: "Eduard@email.com" , Photo: "/src/assets/images/People/4140037.png"})<-[:HAS]-(rq), 
        (ed)-[:HAS]->(e6:Employee {Name: "Fred", ID: "S25984432N",  Phone: "909876665", Email: "Fred@email.com" , Photo: "/src/assets/images/People/4139981.png"})<-[:HAS]-(rq),  
        (ed)-[:HAS]->(e7:Employee {Name: "Gilbert", ID: "S093983333N", Phone: "55446773", Email: "Gilbert@email.com" , Photo: "/src/assets/images/People/4140055.png"})<-[:HAS]-(rq), 
        (ed)-[:HAS]->(e8:Employee {Name: "Harold", ID: "S763663638N",  Phone: "484747443", Email: "Harold@email.com" , Photo: "/src/assets/images/People/4140063.png"})<-[:HAS]-(rq), 
        (ed)-[:HAS]->(e9:Employee {Name: "Ingrid", ID: "S18487473N",  Phone: "998474731", Email: "Ingrid@email.com" , Photo: "/src/assets/images/People/4140060.png"})<-[:HAS]-(rq), 
        (ed)-[:HAS]->(e10:Employee {Name: "Juliet", ID: "S17477328N",Phone: "998474744", Email: "Juliet@email.com" , Photo: "/src/assets/images/People/4140078.png" })<-[:HAS]-(rq),
        (ed)-[:HAS]->(e11:Employee {Name: "Keneth", ID: "T84735968N",  Phone: "9494453321", Email: "Keneth@email.com" , Photo: "/src/assets/images/People/6997675.png"})<-[:HAS]-(rq),
        (ed)-[:HAS]->(e12:Employee {Name: "Marlon", ID: "T324518736N", Phone: "9909136544", Email: "Marlon@email.com" , Photo: "/src/assets/images/People/4140050.png" })<-[:HAS]-(rq),
        (ed)-[:HAS]->(e13:Employee {Name: "Nelson", ID: "T67028333N", Phone: "9449851541", Email: "Nelson@email.com" , Photo: "/src/assets/images/People/4140057.png"})<-[:HAS]-(rq);

MATCH (ed:EmployeeDirectorY {Name: "EmployeeDirectorY"}), (va:Role {Name: "VendorApprover"})
CREATE  (ed)-[:HAS]->(e14:Employee {Name: "Robert", ID: "T98846432N", Phone: "9551062551", Email: "Robert@email.com" , Photo: "/src/assets/images/People/4140037.png"})<-[:HAS]-(va),
        (ed)-[:HAS]->(e15:Employee {Name: "Mary", ID: "T25980932N", Phone: "909870092", Email: "Mary@email.com" , Photo: "/src/assets/images/People/4140076.png"})<-[:HAS]-(va);

MATCH   (ed:EmployeeDirectorY {Name: "EmployeeDirectorY"}), (l1:Role {Name: "Level1Approver"})
CREATE  (ed)-[:HAS]->(e16:Employee {Name: "Gloria", ID: "T093982633N", Phone: "559831373", Email: "Gloria@email.com" , Photo: "/src/assets/images/People/4140047.png"})<-[:HAS]-(l1);

MATCH   (ed:EmployeeDirectorY {Name: "EmployeeDirectorY"}), (l2:Role {Name: "Level2Approver"})       
CREATE  (ed)-[:HAS]->(e17:Employee {Name: "Sara", ID: "T763663208N", Phone: "4849810343", Email: "Sara@email.com" , Photo: "/src/assets/images/People/4143768.png"})<-[:HAS]-(l2);

MATCH   (ed:EmployeeDirectorY {Name: "EmployeeDirectorY"}), (l3:Role {Name: "Level3Approver"})
CREATE  (ed)-[:HAS]->(e18:Employee {Name: "Christine", ID: "T14987473N", Phone: "9998344731", Email: "Christine@email.com" , Photo: "/src/assets/images/People/4140071.png"})<-[:HAS]-(l3);

MATCH   (ed:EmployeeDirectorY {Name: "EmployeeDirectorY"}), (p:Role {Name: "Publisher"})
CREATE  (ed)-[:HAS]->(e19:Employee {Name: "Cloe", ID: "T17488328N", Phone: "998195044", Email: "Cloe@email.com" , Photo: "/src/assets/images/People/4140069.png" })<-[:HAS]-(p);

// Lastly, let's create a SYSTEM user who will send messages to Vendors, communicating the tender results.
MATCH (ed:EmployeeDirectorY {Name: "EmployeeDirectorY"})        
CREATE (ed)-[:HAS]->(:Employee {Name: "System", ID: "SYSTEM"});



// --------- Vendors

CREATE CONSTRAINT unique_Vendor IF NOT EXISTS
FOR (v:Vendor)
REQUIRE v.VendorCode IS UNIQUE;

// Each Vendor will have a unique VendorCode and we should always use it to retrieve the Vendors, 
// although for this Demo script, we will use the ShortName, as I don't have a mechanism for storing the auto-generated VendorCode in the script. This will be done via the UI in the real system.
// We will do the same for Tenders and Bids, where each Tender and Bid will have a unique TenderCode and BidCode, respectively, but we will use other properties to retrieve them in this script, 
// or hardcode some of them for the same reasons. 

// Create 10 Vendors and their respective Vendor Contacts. Let's add all of them to the PendingVendorS Collection, and then we will approve some of them later.
// Each vendor should do this via a system UI, following the procurement instructions and RFI Document Template provided. 
// The UI will execute the Cypher commands below. In this Demo, we will process everything in a single batch.  
MATCH (pv:PendingVendorS {Name: "PendingVendorS"}) 
CREATE (pv)-[:HAS]->(v1:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 1", LegalName: "Vendor One Pte Ltd", RegistrartionNumber: "SG409335548", Logo: "/src/assets/images/vlogo1.jpg"})-[:HAS_CONTACT]->(vc1:VendorContact {Name: "Benson", Phone: "40985343" , Email: "Benson@v1email.com" , Photo: "/src/assets/images/People/4140039.png"}), (v1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v1)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor1/Vendor1RFIDoc.pdf", Description: "Vendor RFI template response", Date: localdatetime.transaction()}),
       (pv)-[:HAS]->(v2:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 2", LegalName: "Vendor Two Pte Ltd", RegistrartionNumber: "SG409335549", Logo: "/src/assets/images/vlogo2.jpg"})-[:HAS_CONTACT]->(vc2:VendorContact {Name: "Cleber", Phone: "56230987" , Email: "Cleber@v2email.com" , Photo: "/src/assets/images/People/4140061.png"}), (v2)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v2)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d2:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor2/Vendor2RFIDoc.pdf", Description: "Vendor RFI template response", Date: localdatetime.transaction()}),     
       (pv)-[:HAS]->(v3:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 3", LegalName: "Vendor Three Pte Ltd", RegistrartionNumber: "SG409335550", Logo: "/src/assets/images/vlogo3.jpg"})-[:HAS_CONTACT]->(vc3:VendorContact {Name: "David", Phone: "29837442" , Email: "David@v3email.com" , Photo: "/src/assets/images/People/4140046.png"}), (v3)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v3)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d3:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor3/Vendor3RFIDoc.pdf", Description: "TVendor RFI template response", Date: localdatetime.transaction()}),   
       (pv)-[:HAS]->(v4:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 4", LegalName: "Vendor Four Pte Ltd", RegistrartionNumber: "SG409335551", Logo: "/src/assets/images/vlogo4.jpg"})-[:HAS_CONTACT]->(vc4:VendorContact {Name: "Ernest", Phone: "89207651" , Email: "Ernest@v4email.com" , Photo: "/src/assets/images/People/4140077.png"}), (v4)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v4)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d4:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor4/Vendor4RFIDoc.pdf", Description: "Vendor RFI template response", Date: localdatetime.transaction()}),   
       (pv)-[:HAS]->(v5:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 5", LegalName: "Vendor Five Pte Ltd", RegistrartionNumber: "SG409335552", Logo: "/src/assets/images/vlogo5.jpg"})-[:HAS_CONTACT]->(vc5:VendorContact {Name: "Frank", Phone: "78383822" , Email: "Frank@v5email.com" , Photo: "/src/assets/images/People/4140059.png"}), (v5)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v5)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d5:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor5/Vendor5RFIDoc.pdf", Description: "Vendor RFI template response", Date: localdatetime.transaction()}),
       (pv)-[:HAS]->(v6:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 6", LegalName: "Vendor Six Pte Ltd", RegistrartionNumber: "SG409335553", Logo: "/src/assets/images/vlogo6.jpg"})-[:HAS_CONTACT]->(vc6:VendorContact {Name: "Gunter", Phone: "30982321" , Email: "Gunter@v6email.com" , Photo: "/src/assets/images/People/4140079.png"}), (v6)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v6)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d6:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor6/Vendor6RFIDoc.pdf", Description: "Vendor RFI template response", Date: localdatetime.transaction()}),
       (pv)-[:HAS]->(v7:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 7", LegalName: "Vendor Seven Pte Ltd", RegistrartionNumber: "SG409335554", Logo: "/src/assets/images/vlogo7.jpg"})-[:HAS_CONTACT]->(vc7:VendorContact {Name: "Herbert", Phone: "78323862" , Email: "Herbert@v7email.com" , Photo: "/src/assets/images/People/4139970.png"}), (v7)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v7)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d7:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor7/Vendor7RFIDoc.pdf", Description: "Vendor RFI template response", Date: localdatetime.transaction()}),
       (pv)-[:HAS]->(v8:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 8", LegalName: "Vendor Eight Pte Ltd", RegistrartionNumber: "SG409335555", Logo: "/src/assets/images/vlogo8.jpg"})-[:HAS_CONTACT]->(vc8:VendorContact {Name: "Igor", Phone: "40989221" , Email: "Igor@v8email.com" , Photo: "/src/assets/images/People/4139955.png"}), (v8)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v8)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d8:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor8/Vendor8RFIDoc.pdf", Description: "Vendor RFI template response", Date: localdatetime.transaction()}),
       (pv)-[:HAS]->(v9:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 9", LegalName: "Vendor Nine Pte Ltd", RegistrartionNumber: "SG409335556", Logo: "/src/assets/images/vlogo9.jpg"})-[:HAS_CONTACT]->(vc9:VendorContact {Name: "John", Phone: "94003822" , Email: "John@v9email.com" , Photo: "/src/assets/images/People/7879063.png"}), (v9)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v9)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d9:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor9/Vendor9RFIDoc.pdf", Description: "Vendor RFI template response", Date: localdatetime.transaction()}),
       (pv)-[:HAS]->(v10:Vendor {VendorCode: "V"+left(randomUUID(),8)+right(randomUUID(),4), ShortName: "Vendor 10", LegalName: "Vendor Ten Pte Ltd", RegistrartionNumber: "SG409335557", Logo: "/src/assets/images/vlogo10.jpg"})-[:HAS_CONTACT]->(vc10:VendorContact {Name: "Karl", Phone: "820042321" , Email: "Karl@v10email.com", Photo: "/src/assets/images/People/4140066.png"}), (v10)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}), (v10)-[:HAS_DOCS]->(:VendorDocS {Name: "VendorDocS"})-[:HAS]->(d10:Doc {DocName: "VendorRFIDoc", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor10/Vendor10RFIDoc.pdf", Description: "Vendor RFI template response", Date: localdatetime.transaction()});


// -------- Vendor Vetting

//--------- AI Agent Vendor Assessment

// Before we enter the Vendor Approval workflow, we can have an AI Agent review the RFI's submitted and do a pre-assessment to help the Vendor Approvers 
// So, we get the RFI Documents URLs of all the Pending Vendors for the AI Agent to fetch the Documents and make an assessment

// AI Agent Query: 
MATCH (:PendingVendorS {Name: "PendingVendorS"})-[:HAS]->(v)-[:HAS_DOCS]->()-[:HAS]->(d:Doc {DocName: "VendorRFIDoc"}) RETURN v.VendorCode, v.ShortName, d.URL;

// The AI Agent will then assess and create an output node for each Vendor.

// For demo purposes, we will simulate the AI Agent response and create random ratings for each Vendor and some Lorem ipsum assessments.
MATCH (:PendingVendorS {Name: "PendingVendorS"})-[:HAS]->(v)
WITH v 
CREATE (v)-[:HAS_AI_AGENT_ASSESMENT {Date: localdatetime.transaction()}]->(:AIVendorAssesment {Rating: rand(), 
AssessmentSummary: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Morbi ornare id justo ac varius. Aliquam in dui consequat, pulvinar lorem quis, rhoncus ipsum. Aenean mi dolor, dapibus ac urna eget, condimentum facilisis urna. Sed vulputate fermentum odio, ut mattis magna rhoncus sit amet. Morbi vestibulum tortor et diam placerat, et tristique mauris porta. Sed tellus diam, aliquam ac ullamcorper malesuada, iaculis nec sem. Mauris felis risus, fringilla in pellentesque a, porta eget arcu. Proin id leo eu tortor dapibus pellentesque at eget justo. Nunc quis euismod erat. Nullam non interdum nibh. Sed ipsum erat, feugiat quis mauris et, tempor laoreet nulla. Duis tincidunt dolor a tortor accumsan, vitae eleifend est efficitur. Suspendisse efficitur, justo non malesuada feugiat, leo enim tincidunt tortor, non tempor nunc magna at purus.", 
Advantages: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer blandit auctor sem, ut pharetra erat mollis id. Vestibulum eu mi venenatis, lacinia orci nec, laoreet diam. Maecenas auctor ac ante eu vestibulum. Sed vitae placerat ex, sed pharetra ex. Donec pharetra mi lacus. Etiam et dapibus erat, a mattis diam. Pellentesque rhoncus tellus ac sem pellentesque laoreet. Sed accumsan maximus odio sed molestie.", 
Disadvantages: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla bibendum elementum tristique. Fusce neque nisl, fermentum eget tellus elementum, semper consectetur dui. Morbi eros arcu, vehicula ac magna ut, lacinia ornare felis. Integer tincidunt mi vel dolor convallis pharetra. Cras viverra congue nisi et imperdiet. In posuere vehicula commodo. Ut viverra sapien arcu, vel maximus leo feugiat non."});


// ---------  Vendor Approver Assessment

// --- AI Agent Opportunity: I don't need to say this, but if AI agents are well-trained, this process can be fully automated. 
// The AI Agents will perform the same Cypher commands instead of the UI

// UI Query—Select the Vendors who have submitted their Forms and are willing to participate in Tenders. They are all in the PendingVenorS collection, waiting for approval.

MATCH (:PendingVendorS {Name: "PendingVendorS"})-[:HAS]->(v:Vendor)-[:HAS_AI_AGENT_ASSESMENT]->(ai:AIVendorAssesment), (v)-[:HAS_DOCS]->()-[:HAS]->(d:Doc {DocName: "VendorRFIDoc"})
RETURN ai.Rating as AI_Rating, ai.AssessmentSummary as AI_Assessment, v.VendorCode, v.ShortName, v.LegalName, d.URL as RFI_Response;


// Let's have the L1 Vendor Approvers (Robert or Mary) approve Vendor 1, 3, 4, 7, 8, 10 — one approval level only for this Demo 
// We ensure the Vendor is in the PendingVendorS collection. We then move (delete a relationship and create another relationship) the Vendor to the ApprovedVendorS collection 
// As the Vendor is now approved, we will also add a few Nodes to enhance the Vendor schema so it can accept Tenders and trace its Bids
MATCH (pv:PendingVendorS {Name: "PendingVendorS"})-[r1:HAS]->(v:Vendor {ShortName: "Vendor 1"}), (l1:Employee {Name: "Robert"}), (av:ApprovedVendorS {Name: "ApprovedVendorS"})
CREATE (v)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This vendor is approved"}]->(l1),
       (av)-[:HAS]->(v),
       (v)-[:HAS_ACCEPTED_INVITATONS]->(:AcceptedInvitationS {Name: "AcceptedInvitationS"}),
       (v)-[:HAS_ACTIVE_BIDS]->(:ActiveBidS {Name: "ActiveBidS"}),
       (v)-[:HAS_PAST_BIDS]->(:PastBidS {Name: "PastBidS"}),
       (v)-[:HAS_AWARDED_BIDS]->(:AwardedBidS {Name: "AwardedBidS"})
       DELETE r1;    

MATCH (pv:PendingVendorS {Name: "PendingVendorS"})-[r1:HAS]->(v:Vendor {ShortName: "Vendor 3"}), (l1:Employee {Name: "Mary"}), (av:ApprovedVendorS {Name: "ApprovedVendorS"})
CREATE (v)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This vendor is approved"}]->(l1),
       (av)-[:HAS]->(v),
       (v)-[:HAS_ACCEPTED_INVITATONS]->(:AcceptedInvitationS {Name: "AcceptedInvitationS"}),
       (v)-[:HAS_ACTIVE_BIDS]->(:ActiveBidS {Name: "ActiveBidS"}),
       (v)-[:HAS_PAST_BIDS]->(:PastBidS {Name: "PastBidS"}),
       (v)-[:HAS_AWARDED_BIDS]->(:AwardedBidS {Name: "AwardedBidS"})
       DELETE r1;   

MATCH (pv:PendingVendorS {Name: "PendingVendorS"})-[r1:HAS]->(v:Vendor {ShortName: "Vendor 4"}), (l1:Employee {Name: "Robert"}), (av:ApprovedVendorS {Name: "ApprovedVendorS"})
CREATE (v)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This vendor is approved"}]->(l1),
       (av)-[:HAS]->(v),
       (v)-[:HAS_ACCEPTED_INVITATONS]->(:AcceptedInvitationS {Name: "AcceptedInvitationS"}),
       (v)-[:HAS_ACTIVE_BIDS]->(:ActiveBidS {Name: "ActiveBidS"}),
       (v)-[:HAS_PAST_BIDS]->(:PastBidS {Name: "PastBidS"}),
       (v)-[:HAS_AWARDED_BIDS]->(:AwardedBidS {Name: "AwardedBidS"})
       DELETE r1;   

MATCH (pv:PendingVendorS {Name: "PendingVendorS"})-[r1:HAS]->(v:Vendor {ShortName: "Vendor 7"}), (l1:Employee {Name: "Mary"}), (av:ApprovedVendorS {Name: "ApprovedVendorS"})
CREATE (v)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This vendor is approved"}]->(l1),
       (av)-[:HAS]->(v),
       (v)-[:HAS_ACCEPTED_INVITATONS]->(:AcceptedInvitationS {Name: "AcceptedInvitationS"}),
       (v)-[:HAS_ACTIVE_BIDS]->(:ActiveBidS {Name: "ActiveBidS"}),
       (v)-[:HAS_PAST_BIDS]->(:PastBidS {Name: "PastBidS"}),
       (v)-[:HAS_AWARDED_BIDS]->(:AwardedBidS {Name: "AwardedBidS"})
       DELETE r1;   

MATCH (pv:PendingVendorS {Name: "PendingVendorS"})-[r1:HAS]->(v:Vendor {ShortName: "Vendor 8"}), (l1:Employee {Name: "Robert"}), (av:ApprovedVendorS {Name: "ApprovedVendorS"})
CREATE (v)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This vendor is approved"}]->(l1),
       (av)-[:HAS]->(v),
       (v)-[:HAS_ACCEPTED_INVITATONS]->(:AcceptedInvitationS {Name: "AcceptedInvitationS"}),
       (v)-[:HAS_ACTIVE_BIDS]->(:ActiveBidS {Name: "ActiveBidS"}),
       (v)-[:HAS_PAST_BIDS]->(:PastBidS {Name: "PastBidS"}),
       (v)-[:HAS_AWARDED_BIDS]->(:AwardedBidS {Name: "AwardedBidS"})
       DELETE r1;       
       
MATCH (pv:PendingVendorS {Name: "PendingVendorS"})-[r1:HAS]->(v:Vendor {ShortName: "Vendor 10"}), (l1:Employee {Name: "Mary"}), (av:ApprovedVendorS {Name: "ApprovedVendorS"})
CREATE (v)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This vendor is approved"}]->(l1),
       (av)-[:HAS]->(v),
       (v)-[:HAS_ACCEPTED_INVITATONS]->(:AcceptedInvitationS {Name: "AcceptedInvitationS"}),
       (v)-[:HAS_ACTIVE_BIDS]->(:ActiveBidS {Name: "ActiveBidS"}),
       (v)-[:HAS_PAST_BIDS]->(:PastBidS {Name: "PastBidS"}),
       (v)-[:HAS_AWARDED_BIDS]->(:AwardedBidS {Name: "AwardedBidS"})
       DELETE r1;   


// We will reject Vendor 2 so we can query the RejectedVendorS Collection later and have some data to work with.
MATCH (pv:PendingVendorS {Name: "PendingVendorS"})-[r1:HAS]->(v:Vendor {ShortName: "Vendor 2"}), (l1:Employee {Name: "Robert"}), (rv:RejectedVendorS {Name: "RejectedVendorS"}) 
CREATE (v)-[:HAS_L1_REJECTION {Date: localdatetime.transaction(), Comment: "This vendor is rejected"}]->(l1),
       (rv)-[:HAS]->(v)
       DELETE r1;




// --------- Tender Creation --------------

CREATE CONSTRAINT unique_Tender IF NOT EXISTS
FOR (t:Tender)
REQUIRE t.TenderCode IS UNIQUE;

// Each Tender will have a unique TenderCode and we should always use it to retrieve the Tenders, 
// although for this Demo script, we will use the Title as I don't have a mechanism for storing the auto-generated TenderCode in the script 

// UI Query—Select the Tender Types available for the Tender. The results will be displayed on the UI for the User to select. 
MATCH (TenderTypeS {Name: "TenderTypeS"})-[:HAS]->(ty) RETURN ty.Name, ty.Description, ty.Rules;


// -------- Tender #1

// The Requester Employee will log in and the UI will gather all the information and execute the below Cypher command to create the Tender and supporting schema Nodes 
// Create the Tender 1 + Schema and let the system generate the Tender Code 
MATCH (em:Employee {Name: "Albert"}), (nt:NewTenderS {Name: "NewTenderS"}), (ty:TenderType {Name: "Open"}) 
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 1", Description: "This is the first tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 400000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_1_RFP", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Albert/Tender1/RFPDocument_t1.pdf", Description: "This is the Tender 1 RFP Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_1_RFP_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Albert/Tender1/RFPResponseTemplate-t1.pdf", Description: "This is the Tender 1 RFP mandatory response template", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_1_RFP_Presentation", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Albert/Tender1/RFPPresentation_t1.pdf", Description: "This is the Tender 1 RFP Presentation", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender #2

// Create the Tender 2 + Schema and let the system generate the Tender Code
MATCH (em:Employee {Name: "Brandon"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Selective"}) 
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 2", Description: "This is the second tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 200000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_2_RFP", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Brandon/Tender2/RFPDocument_t2.pdf", Description: "This is the Tender 2 RFP Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_2_RFP_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Brndon/Tender2/RFPResponseTemplate-t2.pdf", Description: "This is the Tender 2 RFP mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender #3

// Create Tender 3 + Schema and let the system generate the Tender Code. This will be a "Negotiated" Tender Type, and we will only invite Vendor 7 to it.
MATCH (em:Employee {Name: "Charles"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Negotiated"}) 
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 3", Description: "This is the third tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 300000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_3_RFP", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Charles/Tender3/RFPDocument_t3.pdf", Description: "This is the Tender 3 RFP Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_3_RFP_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Charles/Tender3/RFPResponseTemplate-t3.pdf", Description: "This is the Tender 3 RFP mandatory response template", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_3_RFP_Presentation", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Charles/Tender3/RFPPresentation_t3.pdf", Description: "This is the Tender 3 RFP Presentation", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender #4

// Create the Tender 4 + Schema and let the system generate the Tender Code  
MATCH (em:Employee {Name: "Donald"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Open"}) 
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 4", Description: "This is the third tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 40000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_4_RFQ", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Donald/Tender4/RFQDocument_t4.pdf", Description: "This is the Tender 4 RFQ Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_4_RFQ_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Donald/Tender4/RFQResponseTemplate-t4.pdf", Description: "This is the Tender 4 RFQ mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender #5

// Create the Tender 5 + Schema and let the system generate the Tender Code  
MATCH (em:Employee {Name: "Eduard"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Selective"}) 
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 5", Description: "This is the fifth tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 200000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_5_RFP", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Eduard/Tender5/RFPDocument_t5.pdf", Description: "This is the Tender 5 RFP Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_5_RFP_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Eduard/Tender5/RFPResponseTemplate-t5.pdf", Description: "This is the Tender 5 RFP mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender #6

// Create the Tender 6 + Schema and let the system generate the Tender Code  
MATCH (em:Employee {Name: "Fred"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Negotiated"})
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 6", Description: "This is the sixth tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 300000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_6_RFP", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Fred/Tender6/RFPDocument_t6.pdf", Description: "This is the Tender 6 RFP Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_6_RFP_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Fred/Tender6/RFPResponseTemplate-t6.pdf", Description: "This is the Tender 6 RFP mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender #7

// Create the Tender 7 + Schema and let the system generate the Tender Code  
MATCH (em:Employee {Name: "Gilbert"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Open"})
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 7", Description: "This is the seventh tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 400000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_7_RFP", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Gilbert/Tender7/RFPDocument_t7.pdf", Description: "This is the Tender 7 RFP Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_7_RFP_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Gilbert/Tender7/RFPResponseTemplate-t7.pdf", Description: "This is the Tender 7 RFP mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});
      

// -------- Tender #8

// Create the Tender 8 + Schema and let the system generate the Tender Code     
MATCH (em:Employee {Name: "Harold"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Selective"})                
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 8", Description: "This is the Tender 8 for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 100000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_8_RFQ", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Harold/Tender8/RFQDocument_t8.pdf", Description: "This is the Tender 8 RFQ Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_8_RFQ_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Harold/Tender8/RFQResponseTemplate-t8.pdf", Description: "This is the Tender 8 RFQ mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});      


// -------- Tender #9

// Create the ninth Tender + Schema and let the system generate the Tender Code  
MATCH (em:Employee {Name: "Ingrid"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Negotiated"})
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 9", Description: "This is the tenth tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 180000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_9_RFQ", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Ingrid/Tender9/RFQDocument_t9.pdf", Description: "This is the Tender 9 RFQ Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_9_RFQ_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Ingrid/Tender9/RFQResponseTemplate-t9.pdf", Description: "This is the Tender 9 RFQ mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


   


// -------------- Tender Vetting Workflow -------------------



// UI Query - Lets have the Tender Approver Level 1 (Gloria) query the NewTenderS Collection to see the Tenders available for vetting that have not been vetted yet. 
// The I will pass the Emplyee Name to the query as a parameter.
MATCH (e:Employee {Name: "Gloria"})<-[]-(o:Role)
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[:HAS]->(t:Tender)-[:HAS_REQUESTER]-(r) 
WHERE NOT (t)-[]->(e) AND  t.Budget >= o.ApprovalBase 
RETURN r.Name as Requester, t.Title as Title, t.TenderCode as TenderCode, t.Description as TenderDescription, 
apoc.temporal.format(t.SubmissionDate,'dd/MM/YY HH:mm:ss')  as TenderStartDate,  
apoc.temporal.format(t.EndBidingDate,'dd/MM/YY HH:mm:ss') as TenderEndDate, t.Budget as TenderBudget;

//----- AI Agent opportunity 
// In the same way we used AI to assess Vendors, we can use AI agents to pre-assess the Tenders, rate them, and create summaries for the approvers.
// We can even have AI Agents with active vetting capabilities as we assess their assessment accuracy    


// ------ Tender #1 Approval

// --- AI Agent Opportunity: I don't need to say, but the following process can be fully automated if AI Agents are well-tuned. 
// The AI Agents will perform the same Cypher commands instead of the UI
// Even the chat between the Approver and the Tender Requester can be performed by the GenAi Agents.

// ------ Chat for Tender #1 Approval

// Before approving, Gloria has some questions. 
// Chat UI - Let's have a chat about the Tender between the Tender Approver L1 and the Tender Requester for Tender 1
// I am using the Title property as I don't know what the auto-generated TenderCode in this Script

MATCH (t:Tender {Title: "Tender 1"})-[:HAS_CHAT]->(c), (l1:Employee {Name: "Gloria"})
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m1:Message {Text: "Hi, I have a question about the tender. Can you please clarify the budget?"})-[:SENT_BY]->(l1);

MATCH (e:Employee)<-[:HAS_REQUESTER]-(t:Tender {Title: "Tender 1"})-[:HAS_CHAT]->(c) 
CREATE  (c)-[:HAS {Date: localdatetime.transaction()}]->(m2:Message {Text: "Sure, the budget is 400000 in order to include the international deployment as discussed on the meeting of March 10th. Is there anything else you need?"})-[:SENT_BY]->(e);

MATCH (t:Tender {Title: "Tender 1"})-[:HAS_CHAT]->(c), (l1:Employee {Name: "Gloria"})
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m3:Message {Text: "No, that will be all. Thank you!"})-[:SENT_BY]->(l1);           

// Gloria (l1) is now ready to approve Tender 1, as she has all the necessary information.
// Let's have the L1 approver (Gloria) approve the Tender 1
MATCH (t:Tender {Title: "Tender 1"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"})
CREATE (t)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l1);


// If Sara (L2) has a question, she uses the Chat to ask, or if she has no questions, she can approve the Tender 1

// Let's have the Tender Approver Level 2 (Sara) query the NewTenderS Collection to see the Tenders available with a Budget >= 200000 and already Approved by L1 but not yet Approved by L2.
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[:HAS]->(t:Tender) 
WHERE NOT (t)-[:HAS_L2_APPROVAL]->(:Employee) AND t.Budget >= 200001 AND (t)-[:HAS_L1_APPROVAL]->()       
RETURN t.Title, t.TenderCode, t.Description, t.SubmissionDate, t.EndBidingDate, t.Budget;

// or (a more costly query fust for testing purposes)

MATCH ()<-[:HAS_L1_APPROVAL]-(t:Tender)-[:!HAS_L2_APPROVAL]->(e:Employee), (:NewTenderS)-[]->(t)  
WHERE t.Budget >= 200001
RETURN t.Title, t.TenderCode, t.Description, t.SubmissionDate, t.EndBidingDate, t.Budget;

// or use the same query we used for L1, but specifying the L2 approver (Sara). The UI will pass this as a parameter. 

MATCH (e:Employee {Name: "Sara"})<-[]-(o:Role)
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[:HAS]->(t:Tender)-[:HAS_REQUESTER]-(r) 
WHERE NOT (t)-[]->(e)<-[]-(o) AND  t.Budget >= o.ApprovalBase AND (t)-[:HAS_L1_APPROVAL]->()  
RETURN r.Name as Requester, t.Title as Title, t.TenderCode as TenderCode, t.Description as TenderDescription, 
apoc.temporal.format(t.SubmissionDate,'dd/MM/YY HH:mm:ss')  as TenderStartDate,  
apoc.temporal.format(t.EndBidingDate,'dd/MM/YY HH:mm:ss') as TenderEndDate, t.Budget as TenderBudget;


// Let’s have the L2 approver (Sara) approve the Tender 1
MATCH (t:Tender {Title: "Tender 1"}), (l2:Employee {Name: "Sara"})<-[:HAS]-(:Role {Name: "Level2Approver"})
CREATE (t)-[:HAS_L2_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l2);


// If Christine (L3) has questions, she uses the Chat to ask, or if no questions, she can approve the Tender 1
// Let the Tender Approver Level 3 (Christine) query the NewTenderS Collection to see the Tenders available with a Budget >= 300000 and already approved by L2.
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[:HAS]->(t:Tender) 
WHERE NOT (t)-[:HAS_L3_APPROVAL]->(:Employee) AND t.Budget >= 300000 AND (t)-[:HAS_L2_APPROVAL]->()
AND NOT (t)-[:HAS_L3_APPROVAL]->(:Employee)              
RETURN t.Title, t.TenderCode, t.Description, t.SubmissionDate, t.EndBidingDate, t.Budget;


// Let’s have the L3 approver (Christine) approve the Tender 1 
// As the L3 is the final approver (Budget >$300000), lets move the Tender to the ApprovedTenderS Collection and remove it from the NewTenderS Collection
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 1"}), (l3:Employee {Name: "Christine"})<-[:HAS]-(:Role {Name: "Level3Approver"}), (at:ApprovedTenderS {Name: "ApprovedTenderS"})
CREATE (t)-[:HAS_L3_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l3),
       (at)-[:HAS]->(t)
DELETE r1;



// ------   Tender #2 Approval
// Let’s have the L1 approver (Gloria) approve the Tender 2 for now; we might add more approvers later.
MATCH (t:Tender {Title: "Tender 2"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"})
CREATE (t)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l1);

// The Approver 2 (Sara) has some questions about Tender 2, as she wants to know the criteria for selecting the two vendors. Let's have a chat about it.
MATCH (t:Tender {Title: "Tender 2"})-[:HAS_CHAT]->(c), (l2:Employee {Name: "Sara"}) 
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m1:Message {Text: "Hi, I have a question about the tender. Can you please clarify the criteria for selecting the 2 vendors?"})-[:SENT_BY]->(l2);

// Let's have the Tender 2 Requester (Brandon) answer the question from Approver 2 (Sara).
MATCH (e:Employee)<-[:HAS_REQUESTER]-(t:Tender {Title: "Tender 2"})-[:HAS_CHAT]->(c)                
CREATE  (c)-[:HAS {Date: localdatetime.transaction()}]->(m2:Message {Text: "Sure, the criteria are based on the vendors experience and the price they offered in previous tenders. Is there anything else you need?"})-[:SENT_BY]->(e);

// Let's have the Approver 2 (Sara) Reply.
MATCH (t:Tender {Title: "Tender 2"})-[:HAS_CHAT]->(c), (l2:Employee {Name: "Sara"}) 
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m3:Message {Text: "No, that will be all. Thank you!"})-[:SENT_BY]->(l2);



// ------ Tender #3 Approval
// Let's have the L1 approver (Gloria) approve the Tender 3 
MATCH (t:Tender {Title: "Tender 3"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"})
CREATE (t)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l1);

// Let’s have the L2 approver (Sara) approve the Tender 3
MATCH (t:Tender {Title: "Tender 3"}), (l2:Employee {Name: "Sara"})<-[:HAS]-(:Role {Name: "Level2Approver"})
CREATE (t)-[:HAS_L2_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l2);


// Let's have the L3 approver (Christine) approve the Tender 3, and as the L3 is the final approver, let's move the Tender to the ApprovedTenderS Collection and remove it from the NewTenderS Collection
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 3"}), (l3:Employee {Name: "Christine"})<-[:HAS]-(:Role {Name: "Level3Approver"}), (at:ApprovedTenderS {Name: "ApprovedTenderS"})
CREATE (t)-[:HAS_L3_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l3),
       (at)-[:HAS]->(t)
DELETE r1;

  
// ------ Tender #4 Approval
// Let's have the L1 approver (Gloria) approve Tender 4. 
// As Tender 4 Budget is less than $200000, we will not have a L2 or L3 approver for it.
// The Tender 4 will be approved by the L1 approver (Gloria) and moved to the ApprovedTenderS Collection.     
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 4"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"}),  (at:ApprovedTenderS {Name: "ApprovedTenderS"})
CREATE (t)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l1),
       (at)-[:HAS]->(t)
DELETE r1;  


// ------ Tender #5 Approval
// Let's have the L1 approver (Gloria) approve the Tender 3 
MATCH (t:Tender {Title: "Tender 5"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"})
CREATE (t)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l1);

// Let’s have the L2 approver (Sara) approve the Tender 3
MATCH (t:Tender {Title: "Tender 5"}), (l2:Employee {Name: "Sara"})<-[:HAS]-(:Role {Name: "Level2Approver"})
CREATE (t)-[:HAS_L2_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l2);


// Let's have the L3 approver (Christine) approve the Tender 3, and as the L3 is the final approver, let's move the Tender to the ApprovedTenderS Collection and remove it from the NewTenderS Collection
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 5"}), (l3:Employee {Name: "Christine"})<-[:HAS]-(:Role {Name: "Level3Approver"}), (at:ApprovedTenderS {Name: "ApprovedTenderS"})
CREATE (t)-[:HAS_L3_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l3),
       (at)-[:HAS]->(t)
DELETE r1;


// ------ Tender #8 Approval
// Let's have the L1 approver (Gloria) approve the Tender 8.
// As Tender 8 Budget is less than $200000, we will not have a L2 or L3 approver for it.
// The Tender 8 will be approved by the L1 approver (Gloria) and moved to the ApprovedTenderS Collection.
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 8"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"}),  (at:ApprovedTenderS {Name: "ApprovedTenderS"})
CREATE (t)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l1),
       (at)-[:HAS]->(t)
DELETE r1;


// ------ Tender #9 Rejection
// Let’s have the L1 approver (Gloria) Reject the Tender 9.
// As Tender 9 Budget is less than $200000, we will not have an L2 or L3 approver for it.
// The Tender 9 will be rejected by the L1 approver (Gloria) and moved to the RejectedTenderS Collection.

// Before approving, Gloria has some questions. 
// Chat UI - Let's have a chat about the Tender between the Tender Approver L1 and the Tender Requester for Tender 9
MATCH (t:Tender {Title: "Tender 9"})-[:HAS_CHAT]->(c), (l1:Employee {Name: "Gloria"})
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m1:Message {Text: "Hi Ingrid, I have a question about the tender. Reading thrugh the documentation, it seems that this Tender is not complient with our Tender norms as per Schedule 11?"})-[:SENT_BY]->(l1);

MATCH (e:Employee)<-[:HAS_REQUESTER]-(t:Tender {Title: "Tender 9"})-[:HAS_CHAT]->(c) 
CREATE  (c)-[:HAS {Date: localdatetime.transaction()}]->(m2:Message {Text: "Opps, my bad! You are right. We overlooked this part. Sorry"})-[:SENT_BY]->(e);

MATCH (t:Tender {Title: "Tender 9"})-[:HAS_CHAT]->(c), (l1:Employee {Name: "Gloria"})
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m3:Message {Text: "No Proble. I will reject it. So if you are willing to move forward, fix the compliance parts and resubmit it. Thank you!"})-[:SENT_BY]->(l1);          

// Now the L1 approver (Gloria) is ready to reject Tender 9, as she has all the information she needs.
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 9"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"}), (rv:RejectedTenderS {Name: "RejectedTenderS"})
CREATE (t)-[:HAS_L1_REJECTION {Date: localdatetime.transaction(), Comment: "This tender is rejected"}]->(l1),
       (rv)-[:HAS]->(t) 
DELETE r1;


// Before we continue with the Workflow, the Tender 9 that was rejected will be resubmitted with some changes by Ingrid (Tender Requester). 
// Note that we do not update the existing Tender 9, but instead we create a new one for traceability. 

// Let's have Ingrid resubmit/create the ninth Tender + Schema and let the system generate a new Tender Code 
// As this is a resubmission, we will create a relationship to the previous version that is in the RejectedTenderS Collection. In this way, we can keep track of the changes made to the Tender.    
MATCH (em:Employee {Name: "Ingrid"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Negotiated"}),  (rt:RejectedTenderS {Name: "RejectedTenderS"})-[r1:HAS]->(ot:Tender {Title: "Tender 9"})
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 9.1", Description: "This is the tenth tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 180000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_9_1_RFQ", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Ingrid/Tender9_1/RFQDocument_t9_1.pdf", Description: "This is the Tender 9.1 RFQ Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_9_1_RFQ_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Ingrid/Tender9_1/RFQResponseTemplate-t9_1.pdf", Description: "This is the Tender 9.1 RFQ mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"}),
         (t1)-[:HAS_PREVIOUS_VERSION]->(ot); 



// --------------  Publishing (Auditing) Vetting Tenders 

// --- AI Agent Opportunity: I don't need to say this, but if AI agents are well-trained, this process can be fully automated or assisted. 
// An AI Agent can flag Tenders that require special attention (long conversations, multiple Approver messages, etc.) to the Publisher 


// UI Query -Let's have the Publisher (Cloe) query the Approved Tenders to audit the approvals before Publishing.
MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[:HAS]->(t:Tender)-[HAS_REQUESTER]->(r:Employee), (t)-[:HAS_L1_APPROVAL]->(l1) WHERE t.Budget < 200000
RETURN "Up to $200000 (L1 Only)" as TenderApprovalLevel, t.Title as Title, t.TenderCode as TenderCode, t.Description as Description, apoc.temporal.format(t.SubmissionDate,'dd/MM/YY HH:mm:ss')  as TenderStartDate,  apoc.temporal.format(t.EndBidingDate,'dd/MM/YY HH:mm:ss') as TenderEndDate, t.Budget as Budget, r.Name AS Requester, l1.Name AS L1_Approver, "N/A" AS L2_Approver, "N/A" AS L3_Approver
UNION
MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[:HAS]->(t:Tender)-[HAS_REQUESTER]->(r:Employee), (t)-[:HAS_L1_APPROVAL]->(l1), (t)-[:HAS_L2_APPROVAL]->(l2) WHERE t.Budget >= 200000 AND t.Budget < 300000
RETURN "Up to $300000 (L1 and L2)" as TenderApprovalLevel, t.Title as Title, t.TenderCode as TenderCode, t.Description as Description, apoc.temporal.format(t.SubmissionDate,'dd/MM/YY HH:mm:ss')  as TenderStartDate,  apoc.temporal.format(t.EndBidingDate,'dd/MM/YY HH:mm:ss') as TenderEndDate, t.Budget as Budget,  r.Name AS Requester, l1.Name AS L1_Approver, l2.Name AS L2_Approver, "N/A" AS L3_Approver
UNION
MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[:HAS]->(t:Tender)-[HAS_REQUESTER]->(r:Employee), (t)-[:HAS_L1_APPROVAL]->(l1), (t)-[:HAS_L2_APPROVAL]->(l2), (t)-[:HAS_L3_APPROVAL]->(l3) WHERE t.Budget >= 300000
RETURN "Above $300000 (L1, L2 and L3)" as TenderApprovalLevel,t.Title as Title, t.TenderCode as TenderCode, t.Description as Description, apoc.temporal.format(t.SubmissionDate,'dd/MM/YY HH:mm:ss')  as TenderStartDate,  apoc.temporal.format(t.EndBidingDate,'dd/MM/YY HH:mm:ss') as TenderEndDate, t.Budget as Budget,  r.Name AS Requester, l1.Name AS L1_Approver, l2.Name AS L2_Approver, l3.Name AS L3_Approver;


// If the Publisher (Cloe) has questions, she can use the Chat of each Tender to ask, or if she has no questions, she can publish Tenders 1 and 4 that are approved and ready for Publishing.

// Publish Tender 1
// Let's move Tender 1 to the PublishedTenderS Collection by the Publisher (Cloe) and delete the relationship from the ApprovedTenderS Collection.
// Now that we are publishing the Tender, we will also create the Tender's "InvitedVenrorS" collection to place the Vendors that will be invited and the TenderBidS collection
MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 1"}), (p:Employee {Name: "Cloe"})<-[:HAS]-(:Role {Name: "Publisher"}), (pt:PublishedTenderS {Name: "PublishedTenderS"})
CREATE (t)-[:HAS_PUBLISHER_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved for Publishing"}]->(p),
       (t)-[:HAS_INVITEES]->(:InvitedVendorS {Name: "InvitedVendorS"}),
       (t)-[:HAS_BIDS]->(:TenderBidS {Name: "TenderBidS"}),
       (pt)-[:HAS]->(t)
DELETE r1;       

// As Tender 1 is Type "Open", we can invite all the Approved Vendors to it. The UI will do this.
// In a real scenario, there would be more criteria to select the Vendors (type, size, etc.), and the Cypher query would need to be tailored, but for this demo, we will invite all of them.
MATCH (t:Tender {Title: "Tender 1"})-[:HAS_INVITEES]->(iv:InvitedVendorS {Name: "InvitedVendorS"})
UNWIND COLLECT {MATCH (v:Vendor)<-[:HAS]-(:ApprovedVendorS) RETURN v} AS vendor
        CREATE (iv)-[:HAS {Date: localdatetime.transaction()}]->(vendor);


// Now we must communicate all the Tender 1 invitees about their invitation so they can decide if they want to participate in the Tender.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 1"})-[:HAS_INVITEES]->()-[:HAS]->(v)-[:HAS_CHAT]->(c:ConversatioN)  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "You have been Invited to participate on a tender (Tender 1)."})-[:SENT_BY]->(e);


// Publish Tender 3
// Let's move Tender 3 to the PublishedTenderS Collection by the Publisher (Cloe) and delete the relationship from the ApprovedTenderS Collection.
// Now that we are publishing the Tender, we will also create the Tender's "InvitedVenrorS" collection to place the Vendors that will be invited and the TenderBidS collection
MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 3"}), (p:Employee {Name: "Cloe"})<-[:HAS]-(:Role {Name: "Publisher"}), (pt:PublishedTenderS {Name: "PublishedTenderS"})
CREATE (t)-[:HAS_PUBLISHER_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved for Publishing"}]->(p),
       (t)-[:HAS_INVITEES]->(:InvitedVendorS {Name: "InvitedVendorS"}),
       (t)-[:HAS_BIDS]->(:TenderBidS {Name: "TenderBidS"}),
       (pt)-[:HAS]->(t)
DELETE r1;    

// As this Tender 3 is Type "Negotiated", we will invite a single Approved Vendor to it. In this case, we will invite the Vendor 7.
MATCH (t:Tender {Title: "Tender 3"})-[:HAS_INVITEES]->(iv:InvitedVendorS {Name: "InvitedVendorS"})
MATCH (v:Vendor {ShortName: "Vendor 7"})<-[:HAS]-(:ApprovedVendorS)
        CREATE (iv)-[:HAS {Date: localdatetime.transaction()}]->(v);


// Now we must communicate all the Tender 3 invitees about their invitation so they can decide if they want to participat in the Tender.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 3"})-[:HAS_INVITEES]->()-[:HAS]->(v)-[:HAS_CHAT]->(c:ConversatioN)  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "You have been Invited to participate on a tender (Tender 3)."})-[:SENT_BY]->(e);


// Publish Tender 4
// Let's move Tender 4 to the PublishedTenderS Collection by the Publisher (Cloe) and delete the relationship from the ApprovedTenderS Collection.
// Now that we are publishing the Tender, we will also create the Tender's "InvitedVenrorS" collection to place the Vendors that will be invited and the TenderBidS collection
MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 4"}), (p:Employee {Name: "Cloe"})<-[:HAS]-(:Role {Name: "Publisher"}), (pt:PublishedTenderS {Name: "PublishedTenderS"})
CREATE (t)-[:HAS_PUBLISHER_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved for Publishing"}]->(p),
       (t)-[:HAS_INVITEES]->(:InvitedVendorS {Name: "InvitedVendorS"}),
       (t)-[:HAS_BIDS]->(:TenderBidS {Name: "TenderBidS"}),
       (pt)-[:HAS]->(t)
DELETE r1;

// As this Tender 4 is Type "Open", we can invite all the Approved Vendors to it. This time around, we will retrieve the Tender using the Employee Name "Donald" as the Tender Requester.
MATCH (:Employee {Name: "Donald"})<-[:HAS_REQUESTER]-(t:Tender)-[:HAS_INVITEES]->(iv:InvitedVendorS {Name: "InvitedVendorS"})
UNWIND COLLECT {MATCH (v:Vendor)<-[:HAS]-(:ApprovedVendorS) RETURN v} AS vendor
        CREATE (iv)-[:HAS {Date: localdatetime.transaction()}]->(vendor);


// Now we must communicate all the Tender 4 invitees about their invitation so they can decide if they want to participat in the Tender.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 4"})-[:HAS_INVITEES]->()-[:HAS]->(v)-[:HAS_CHAT]->(c:ConversatioN)  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "You have been Invited to participate on a tender (Tender 4)."})-[:SENT_BY]->(e);



// Publish Tender 5
// Let's move Tender 5 to the PublishedTenderS Collection by the Publisher (Cloe) and delete the relationship from the ApprovedTenderS Collection.
// Now that we are publishing the Tender, we will also create the Tender's "InvitedVenrorS" collection to place the Vendors that will be invited and the TenderBidS collection
MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 5"}), (p:Employee {Name: "Cloe"})<-[:HAS]-(:Role {Name: "Publisher"}), (pt:PublishedTenderS {Name: "PublishedTenderS"})
CREATE (t)-[:HAS_PUBLISHER_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved for Publishing"}]->(p),
       (t)-[:HAS_INVITEES]->(:InvitedVendorS {Name: "InvitedVendorS"}),
       (t)-[:HAS_BIDS]->(:TenderBidS {Name: "TenderBidS"}),
       (pt)-[:HAS]->(t)
DELETE r1;

// As Tender "Tender 5" is Type "Selective", we will invite a subset of the Approved Vendors to it. In this case, we will invite two Approved Vendors.
MATCH (t:Tender {Title: "Tender 5"})-[:HAS_INVITEES]->(iv:InvitedVendorS {Name: "InvitedVendorS"})
UNWIND COLLECT {MATCH (v:Vendor)<-[:HAS]-(:ApprovedVendorS) ORDER BY v.ShortName DESC RETURN v LIMIT 2} AS vendor
        CREATE (iv)-[:HAS {Date: localdatetime.transaction()}]->(vendor);


// Now we must communicate all the Tender 4 invitees about their invitation so they can decide if they want to participat in the Tender.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 5"})-[:HAS_INVITEES]->()-[:HAS]->(v)-[:HAS_CHAT]->(c:ConversatioN)  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "You have been Invited to participate on a tender (Tender 5)."})-[:SENT_BY]->(e);





// The Publisher (Cloe) will not publish the Tender 8 for now. It will remain on ApprovedTenderS so we can query it in the Demo. 




// -------------- Vendor's Tender Acceptance Workflow --------------------

// Let's now have the Vendors 7 accept the Tender Invitation so they can submit their Bids. 
// First, the Vendor 7 will check what Tenders are published and they have been invited to bid.
MATCH (v:Vendor {ShortName: "Vendor 7"})<-[:HAS]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender)<-[:HAS]-(:PublishedTenderS), (t)-[:HAS_TYPE]-(ty:TenderType) RETURN t.TenderCode, t.Title, t.Description, t.SubmissionDate, t.Budget, ty.Name;


// Now, Vendor 7 will accept the Tender Invitations for Tender 1 (Open) and connect the selected tender to its Tender Invitation Collection (AcceptedInvitationS).
MATCH (ti:AcceptedInvitationS {Name: "AcceptedInvitationS"})<-[:HAS_ACCEPTED_INVITATONS]-(v:Vendor {ShortName: "Vendor 7"})<-[:HAS]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender {Title: "Tender 1"})
CREATE (ti)-[:HAS {Date: localdatetime.transaction()}]->(t);

// Now, Vendor 7 will accept the Tender Invitation for Tender 3 (Negotiated) and connect the selected tender to its Tender Invitation Collection (AcceptedInvitationS).      
MATCH (ti:AcceptedInvitationS {Name: "AcceptedInvitationS"})<-[:HAS_ACCEPTED_INVITATONS]-(v:Vendor {ShortName: "Vendor 7"})<-[:HAS]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender {Title: "Tender 3"})
CREATE (ti)-[:HAS {Date: localdatetime.transaction()}]->(t);


// UI Query—First, Vendor 4 will check what Tenders have been published and whether they have been invited to bid.
MATCH (v:Vendor {ShortName: "Vendor 4"})<-[:HAS]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender)<-[:HAS]-(:PublishedTenderS), (t)-[:HAS_TYPE]-(ty:TenderType) RETURN t.TenderCode, t.Title, t.Description, t.SubmissionDate, t.Budget, ty.Name;

// Now we will have Vendor 4 accept the Tender 1 (Open) and 7 Invitation. Vendor 4 will connect the selected tender to its Tender Invitation Collection (AcceptedInvitationS).
MATCH (ti:AcceptedInvitationS {Name: "AcceptedInvitationS"})<-[:HAS_ACCEPTED_INVITATONS]-(v:Vendor {ShortName: "Vendor 4"})<-[:HAS]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender {Title: "Tender 1"})    
CREATE (ti)-[:HAS {Date: localdatetime.transaction()}]->(t);


// UI Query—First, Vendor 3 will check what Tenders have been published and whether they have been invited to bid.
MATCH (v:Vendor {ShortName: "Vendor 3"})<-[:HAS]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender)<-[:HAS]-(:PublishedTenderS), (t)-[:HAS_TYPE]-(ty:TenderType) RETURN t.TenderCode, t.Title, t.Description, t.SubmissionDate, t.Budget, ty.Name;

// Now we will have Vendor 3 accept the Tender 4 (Open) invitation. Vendor 4 will connect the selected tender to its Tender Invitation Collection (AcceptedInvitationS).
MATCH (ti:AcceptedInvitationS {Name: "AcceptedInvitationS"})<-[:HAS_ACCEPTED_INVITATONS]-(v:Vendor {ShortName: "Vendor 3"})<-[:HAS]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender {Title: "Tender 4"})    
CREATE (ti)-[:HAS {Date: localdatetime.transaction()}]->(t);

//UI Query—First, Vendor 8 will check what Tenders have been published and whether they have been invited to bid.
MATCH (v:Vendor {ShortName: "Vendor 8"})<-[:HAS]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender)<-[:HAS]-(:PublishedTenderS), (t)-[:HAS_TYPE]-(ty:TenderType) RETURN t.TenderCode, t.Title, t.Description, t.SubmissionDate, t.Budget, ty.Name;

// Now we will have Vendor 8 accept the Tender 4 (Open) invitation. Vendor 8 will connect the selected tender to its Tender Invitation Collection (AcceptedInvitationS).
MATCH (ti:AcceptedInvitationS {Name: "AcceptedInvitationS"})<-[:HAS_ACCEPTED_INVITATONS]-(v:Vendor {ShortName: "Vendor 8"})<-[:HAS]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender {Title: "Tender 4"})    
CREATE (ti)-[:HAS {Date: localdatetime.transaction()}]->(t);


 
// ------------- Vendor Bidding --------------------

CREATE CONSTRAINT unique_Bid IF NOT EXISTS
FOR (b:Bid)
REQUIRE b.BidCode IS UNIQUE;

// Each Bid will have a unique BidCode, and we should always use it to retrieve the Bid. 
// As I don't have a mechanism of storing the auto-generated BidCode in the script, I will set a few manually so we can retrieve them later


// The Vendor 7 will query their AcceptedInvitationS collection to fetch the Tender and their respective Documentations in order to Submit the Bids:
MATCH (v:Vendor {ShortName: "Vendor 7"})-[:HAS_ACCEPTED_INVITATONS]->()-[:HAS]->(t)-[:HAS_DOCS]->()-[:HAS]->(d), (t)-[:HAS_TYPE]->(y) RETURN  t.TenderCode, t.Description, t.Budget, y.Name, d.URL;

// Create a Bid from Vendor 7 for Tender 1. We will use the Bid Code "B79c69d9843ff" for the Bid of Tender 1 for demonstration purposes, so that we can use it later.
MATCH (vb:ActiveBidS)<-[:HAS_ACTIVE_BIDS]-(v:Vendor {ShortName: "Vendor 7"})-[:HAS_ACCEPTED_INVITATONS]->()-[:HAS]->(t:Tender {Title: "Tender 1"})-[:HAS_BIDS]->(tb:TenderBidS {Name: "TenderBidS"})
CREATE (vb)-[:HAS {Date: localdatetime.transaction()}]->(b:Bid {BidCode: "B79c69d9843ff", Title: "Title of Bid for Tender 1 from Vendor 7", Description: "Description of Bid for Tender 1 from Vendor 7", Scope: "Scope of Bid for Tender 1 from Vendor 7", Deliverables: "List of deliverables of Bid for Tender 1 from Vendor 7", CompletitionDate:  localdatetime.transaction() + duration({days: 90}), Price: 80000, Conditions: "Vendor 7 Conditions for Bid of Tender 1", Qualifications: "Vendor 7 qualifications for Tender 1",  SubmissionDate: localdatetime.transaction()})<-[:HAS {Date: localdatetime.transaction()}]-(tb),
       (b)-[:HAS_VENDOR]->(v),
       (b)-[:HAS_TENDER]->(t),
       (b)-[:HAS_DOCS]->(:BidDocS {Name: "BidDocS"})-[:HAS]->(d:Doc {DocName: "BidDoc T1-V7", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor7/Tender1/Bid_RFPDocT1_V7_01.pdf", Description: "This is the description of the RFP Document", Date: localdatetime.transaction()}),
       (b)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// Create Bid from the Vendor 7 for Tender 3 (this time we will let the system generate the Bid Code; this will be the default behaviour)
MATCH  (vb:ActiveBidS)<-[:HAS_ACTIVE_BIDS]-(v:Vendor {ShortName: "Vendor 7"})-[:HAS_ACCEPTED_INVITATONS]->()-[:HAS]->(t:Tender {Title: "Tender 3"})-[:HAS_BIDS]->(tb:TenderBidS {Name: "TenderBidS"})
CREATE (vb)-[:HAS {Date: localdatetime.transaction()}]->(b:Bid {BidCode: "B"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Title of Bid for Tender 3 from Vendor 7", Description: "Description of Bid for Tender 3 from Vendor 7", Scope: "Scope of Bid for Tender 3 from Vendor 7", Deliverables: "List of deliverables of Bid for Tender 3 from Vendor 7", CompletitionDate:  localdatetime.transaction() + duration({days: 160}), Price: 290000, Conditions: "Vendor 7 Conditions for Bid of Tender 3", Qualifications: "Vendor 7 qualifications for Tender 3", SubmissionDate: localdatetime.transaction()})<-[:HAS {Date: localdatetime.transaction()}]-(tb),
       (b)-[:HAS_VENDOR]->(v),
       (b)-[:HAS_TENDER]->(t),
       (b)-[:HAS_DOCS]->(:BidDocS {Name: "BidDocS"})-[:HAS]->(d:Doc {DocName: "BidDoc T3-V7", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor7/Tender1/Bid_RFPDocT3_V7_01.pdf", Description: "This is the description of the RFP Document", Date: localdatetime.transaction()}),
       (b)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});                                 
 

// The Vendor 4 will query their AcceptedInvitationS collection to fetch the Tender and their respective Documentations to Submit the Bids:
MATCH (v:Vendor {ShortName: "Vendor 4"})-[:HAS_ACCEPTED_INVITATONS]->()-[:HAS]->(t)-[:HAS_DOCS]->()-[:HAS]->(d), (t)-[:HAS_TYPE]->(y) RETURN  t.TenderCode, t.Description, t.Budget, y.Name, d.URL;

// Create Bid from the Vendor 4 for Tender 1 (this time we will let the system generate the Bid Code; this will be the default behaviour)
MATCH (vb:ActiveBidS)<-[:HAS_ACTIVE_BIDS]-(v:Vendor {ShortName: "Vendor 4"})-[:HAS_ACCEPTED_INVITATONS]->()-[:HAS]->(t:Tender {Title: "Tender 1"})-[:HAS_BIDS]->(tb:TenderBidS {Name: "TenderBidS"})
CREATE (vb)-[:HAS {Date: localdatetime.transaction()}]->(b:Bid {BidCode: "B"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Title of Bid for Tender 1 from Vendor 4", Description: "Description of Bid for Tender 1 from Vendor 4", Scope: "Scope of Bid for Tender 1 from Vendor 4", Deliverables: "List of deliverables of Bid for Tender 1 from Vendor 4", CompletitionDate:  localdatetime.transaction() + duration({days: 75}), Price: 75000, Conditions: "Vendor 4 Conditions for Bid of Tender 1", Qualifications: "Vendor 4 qualifications for Tender 1", SubmissionDate: localdatetime.transaction()})<-[:HAS {Date: localdatetime.transaction()}]-(tb),
       (b)-[:HAS_VENDOR]->(v),
       (b)-[:HAS_TENDER]->(t),
       (b)-[:HAS_DOCS]->(:BidDocS {Name: "BidDocS"})-[:HAS]->(d:Doc {DocName: "BidDoc T1-V4", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor7/Tender1/Bid_RFPDocT1_V4_01.pdf", Description: "This is the description of the RFP Document", Date: localdatetime.transaction()}),
       (b)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// The Vendor 3 will query their AcceptedInvitationS collection to fetch the Tender and their respective Documentations in order to Submit the Bids:
MATCH (v:Vendor {ShortName: "Vendor 3"})-[:HAS_ACCEPTED_INVITATONS]->()-[:HAS]->(t)-[:HAS_DOCS]->()-[:HAS]->(d), (t)-[:HAS_TYPE]->(y) RETURN  t.TenderCode, t.Description, t.Budget, y.Name, d.URL;

// Create Bid from the Vendor 3 for Tender 4 (this time we will let the system generate the Bid Code; this will be the default behaviour)
MATCH (vb:ActiveBidS)<-[:HAS_ACTIVE_BIDS]-(v:Vendor {ShortName: "Vendor 3"})-[:HAS_ACCEPTED_INVITATONS]->()-[:HAS]->(t:Tender {Title: "Tender 4"})-[:HAS_BIDS]->(tb:TenderBidS {Name: "TenderBidS"})
CREATE (vb)-[:HAS {Date: localdatetime.transaction()}]->(b:Bid {BidCode: "B"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Title of Bid for Tender 4 from Vendor 3", Description: "Description of Bid for Tender 4 from Vendor 3", Scope: "Scope of Bid for Tender 4 from Vendor 3", Deliverables: "List of deliverables of Bid for Tender 4 from Vendor 3", CompletitionDate:  localdatetime.transaction() + duration({days: 75}), Price: 75000, Conditions: "Vendor 3 Conditions for Bid of Tender 4", Qualifications: "Vendor 3 qualifications for Tender 4", SubmissionDate: localdatetime.transaction()})<-[:HAS {Date: localdatetime.transaction()}]-(tb),
       (b)-[:HAS_VENDOR]->(v),
       (b)-[:HAS_TENDER]->(t),
       (b)-[:HAS_DOCS]->(:BidDocS {Name: "BidDocS"})-[:HAS]->(d:Doc {DocName: "BidDoc T4-V3", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor7/Tender1/Bid_RFQDocT4_V3_01.pdf", Description: "This is the description of the Bid RFQ Document", Date: localdatetime.transaction()}),
       (b)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});

// The Vendor 8 will query their AcceptedInvitationS collection to fetch the Tender and their respective Documentations in order to Submit the Bids:
MATCH (v:Vendor {ShortName: "Vendor 8"})-[:HAS_ACCEPTED_INVITATONS]->()-[:HAS]->(t)-[:HAS_DOCS]->()-[:HAS]->(d), (t)-[:HAS_TYPE]->(y) RETURN  t.TenderCode, t.Description, t.Budget, y.Name, d.URL;

// Create Bid from the Vendor 8 for Tender 4  - We will use the Bid Code "B784981c5b0cc" manually for this Bid for demonstration purposes, so that we can use it later. "B784981c5b0cc" 
MATCH (vb:ActiveBidS)<-[:HAS_ACTIVE_BIDS]-(v:Vendor {ShortName: "Vendor 8"})-[:HAS_ACCEPTED_INVITATONS]->()-[:HAS]->(t:Tender {Title: "Tender 4"})-[:HAS_BIDS]->(tb:TenderBidS {Name: "TenderBidS"})
CREATE (vb)-[:HAS {Date: localdatetime.transaction()}]->(b:Bid {BidCode: "B784981c5b0cc", Title: "Title of Bid for Tender 4 from Vendor 8", Description: "Description of Bid for Tender 4 from Vendor 8", Scope: "Scope of Bid for Tender 4 from Vendor 8", Deliverables: "List of deliverables of Bid for Tender 4 from Vendor 8", CompletitionDate:  localdatetime.transaction() + duration({days: 75}), Price: 75000, Conditions: "Vendor 8 Conditions for Bid of Tender 4", Qualifications: "Vendor 8 qualifications for Tender 4", SubmissionDate: localdatetime.transaction()})<-[:HAS {Date: localdatetime.transaction()}]-(tb),
       (b)-[:HAS_VENDOR]->(v),
       (b)-[:HAS_TENDER]->(t),
       (b)-[:HAS_DOCS]->(:BidDocS {Name: "BidDocS"})-[:HAS]->(d:Doc {DocName: "BidDoc T4-V8", Type: "PDF", URL: "https://docs.google.com/document/d/Vendor7/Tender1/Bid_RFQDocT4_V8_01.pdf", Description: "This is the description of the Bid RFQ Document", Date: localdatetime.transaction()}),
       (b)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// The Bidding is closed 

// Now, we must communicate to all the Tender 1 bidders (the ones who accepted the invitation) that the Bidding is officially closed.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 1"})<-[:HAS]-(:AcceptedInvitationS)-[:HAS_ACCEPTED_INVITATONS]-(v)-[:HAS_CHAT]->(c:ConversatioN)  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "Tender 4 is now officially Closed for bidding. We will communicate the results as soon as we have an awarded bid. Thanks for participating."})-[:SENT_BY]->(e);


// Now, we must communicate to all the Tender 3 bidders (the ones who accepted the invitation) that the Bidding is officially closed.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 3"})<-[:HAS]-(:AcceptedInvitationS)-[:HAS_ACCEPTED_INVITATONS]-(v)-[:HAS_CHAT]->(c:ConversatioN)  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "Tender 4 is now officially Closed for bidding. We will communicate the results as soon as we have an awarded bid. Thanks for participating."})-[:SENT_BY]->(e);


// Now, we must communicate to all the Tender 4 bidders (the ones who accepted the invitation) that the Bidding is officially closed.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 4"})<-[:HAS]-(:AcceptedInvitationS)-[:HAS_ACCEPTED_INVITATONS]-(v)-[:HAS_CHAT]->(c:ConversatioN)  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "Tender 4 is now officially Closed for bidding. We will communicate the results as soon as we have an awarded bid. Thanks for participating."})-[:SENT_BY]->(e);




// -------------- Bid Vetting Workflow --------------------

// --------- Bid Chat 

// We will now create the Bid Approval Workflow for Bid 1 of Tender 1 submitted by Vendor 7
// Let's have a chat about the Bid between the Bid Requester and the Vendor 7's Bid of Tender 1 

// UI Query - First, we will get the Bids submitted by all Vendors for all Published (Active) Tenders. 
// We will retrieve the Tender Code, Title, Vendor Short Name, Bid Code, Bid Title, Bid Description, Bid Scope, Bid Deliverables, Bid Completion Date, Bid Price, Bid Conditions, Bid Qualifications, Bid Submission Date, and the Bid Document Name and URL.
// We will select the Bid we want to evaluate and have a chat with the Vendor.
MATCH (:PublishedTenderS)-[:HAS]->(t:Tender)<-[:HAS_TENDER]-(b:Bid)-[:HAS_VENDOR]->(v), (b)-[:HAS_DOCS]->(:BidDocS)-[:HAS]->(d:Doc)
RETURN t.TenderCode, t.Title, v.ShortName, b.BidCode, b.Title, b.Description, b.Scope, b.Deliverables, b.CompletitionDate, b.Price, b.Conditions, b.Qualifications, b.SubmissionDate, d.DocName, d.URL;



// We will select the Bid from Vendor 7 for Tender 1 with Bid Code "B79c69d9843ff" 
// Chat UI - Now that we have the Bid Code (B79c69d9843ff), we use it as an anchor Node to have a chat about it.
MATCH (b:Bid {BidCode: "B79c69d9843ff"})-[:HAS_CHAT]->(c), (e:Employee {Name: "Albert"})
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m1:Message {Text: "Hi, I have a question about the bid. Can you please justify the price and delivery dates?"})-[:SENT_BY]->(e);

MATCH (vc:VendorContact)<-[:HAS_CONTACT]-(v:Vendor)<-[:HAS_VENDOR]-(b:Bid {BidCode: "B79c69d9843ff"})-[:HAS_CHAT]->(c)
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m2:Message {Text: "Hi Albert. Sure, the price is 80000 given the complexity of the project. As we will need to bring extra resources and might have to hire a few new resources, the timeframe might be a bit longer than usual. Is there anything else you need?"})-[:SENT_BY]->(vc);

MATCH (b:Bid {BidCode: "B79c69d9843ff"})-[:HAS_CHAT]->(c), (e:Employee {Name: "Albert"})  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m3:Message {Text: "Thanks, Herbert. No, that will be all. Thank you!"})-[:SENT_BY]->(e);

// Now, Gloria (the L1 Approver) will also ask a question about the Bid 1 of Tender 1 
MATCH (b:Bid {BidCode: "B79c69d9843ff"})-[:HAS_CHAT]->(c), (l1:Employee {Name: "Gloria"})
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m4:Message {Text: "Hi Herbert, this is Gloria from the Approval team and I would like to know how committed you are for delivering on the proposed time?"})-[:SENT_BY]->(l1);

// The Vendor 7 contact person will reply to Gloria's question
MATCH (vc:VendorContact)<-[:HAS_CONTACT]-(v:Vendor)<-[:HAS_VENDOR]-(b:Bid {BidCode: "B79c69d9843ff"})-[:HAS_CHAT]->(c)
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m5:Message {Text: "Hi Gloria, we are fully committed to delivering on the proposed time. We have the resources and the expertise to deliver on time. Is there anything else you need?"})-[:SENT_BY]->(vc);

// Gloria thanks the Vendor 7 contact person for the reply
MATCH (b:Bid {BidCode: "B79c69d9843ff"})-[:HAS_CHAT]->(c), (l1:Employee {Name: "Gloria"})  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m6:Message {Text: "Thanks Herbert, that will be all from my side. Thanks!"})-[:SENT_BY]->(l1);



// -------- Bid Approval 
// Once the Tender Bidding process is completed and closed (no more Bids accepted), we will start the Bid Approval Workflow.


//--------- AI Agent Bid Assessment

// Before we enter the Bid Approval workflow, we can have an AI Agent review the RFQs and RFPs submitted and do a pre-assessment to help the Bid Approvers, just as we did with the Vendor Approval 
// So, we get the RFP or RFQ Documents URLs of all the Bids, plus all the Chat conversations (if any), and the AI Agent can make an assessment

// AI Agent Queries to fetch the RFP or RFQ documents and their vendor responses, and the Chat conversations in the order in which they were created: 
// The Tender FRQ, FRP, and other Tender Documentations for the AI Agent to understand the Tender requirements  
MATCH (:PublishedTenderS)-[:HAS]->(t)-[:HAS_DOCS]->()-[:HAS]-(d) RETURN t.TenderCode, d.URL;

// The Vendor bid documents (RFQ/RFP templates filled) and any other documents submitted by the Vendor with the bid  
MATCH (:PublishedTenderS)-[:HAS]->(t)-[:HAS_BIDS]->()-[:HAS]->(b)-[:HAS_DOCS]->()-[:HAS]-(d), (b)-[:HAS_VENDOR]-(v) RETURN t.TenderCode, v.VendorCode, b.BidCode, d.URL;

// All communications regarding the bid between the Tender team and the Vendor.
MATCH (:PublishedTenderS)-[:HAS]->(t)-[:HAS_BIDS]->()-[:HAS]->(b)-[:HAS_CHAT]->()-[r:HAS]->(c)-[:SENT_BY]-(p) RETURN t.TenderCode, b.BidCode, p.Name, c.Text ORDER by r.Date; 

// With all this information, the AI Agent can now make a proper assessment of the Bids, compare them, and rate their adherence to the Tender requirements and other factors 
// The AI Agent will then assess the Documents and conversations and create an output node for each Vendor.


// For demo purposes, we will simulate the AI Agent response and create random ratings for each Vendor Bid and some Lorem ipsum assessments.
MATCH (:PublishedTenderS)-[:HAS]->(t)-[:HAS_BIDS]->()-[:HAS]->(b)
WITH b 
CREATE (b)-[:HAS_AI_AGENT_ASSESMENT {Date: localdatetime.transaction()}]->(:AIBidAssesment {Rating: rand(), 
AssessmentSummary: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Morbi ornare id justo ac varius. Aliquam in dui consequat, pulvinar lorem quis, rhoncus ipsum. Aenean mi dolor, dapibus ac urna eget, condimentum facilisis urna. Sed vulputate fermentum odio, ut mattis magna rhoncus sit amet. Morbi vestibulum tortor et diam placerat, et tristique mauris porta. Sed tellus diam, aliquam ac ullamcorper malesuada, iaculis nec sem. Mauris felis risus, fringilla in pellentesque a, porta eget arcu. Proin id leo eu tortor dapibus pellentesque at eget justo. Nunc quis euismod erat. Nullam non interdum nibh. Sed ipsum erat, feugiat quis mauris et, tempor laoreet nulla. Duis tincidunt dolor a tortor accumsan, vitae eleifend est efficitur. Suspendisse efficitur, justo non malesuada feugiat, leo enim tincidunt tortor, non tempor nunc magna at purus.", 
Advantages: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer blandit auctor sem, ut pharetra erat mollis id. Vestibulum eu mi venenatis, lacinia orci nec, laoreet diam. Maecenas auctor ac ante eu vestibulum. Sed vitae placerat ex, sed pharetra ex. Donec pharetra mi lacus. Etiam et dapibus erat, a mattis diam. Pellentesque rhoncus tellus ac sem pellentesque laoreet. Sed accumsan maximus odio sed molestie.", 
Disadvantages: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla bibendum elementum tristique. Fusce neque nisl, fermentum eget tellus elementum, semper consectetur dui. Morbi eros arcu, vehicula ac magna ut, lacinia ornare felis. Integer tincidunt mi vel dolor convallis pharetra. Cras viverra congue nisi et imperdiet. In posuere vehicula commodo. Ut viverra sapien arcu, vel maximus leo feugiat non."});

// Each Bid Approver will fetch the Bid + the respective RFP/RFQ Documents and the AI Agent Assessment and decide. 



// Bid Approval Workflow for Bid 1 of Tender 1 - The Bid Requester and the Approvers will approve the Bid in sequence
// First, we will get the Bid Requester (Albert) and the Bid Approvers (Gloria, Sara, and Christine) for Bid 1 of Tender 1  
// Once all the approvals have been granted, the Tender will be moved to the AwardedTenderS Collection and the Bid will be moved to the AwarderBidS Collection of the Vendor.  

// Albert (the Tender 1 Requester) will approve Bid 1 from Vendor 7 for Tender 1. The Requester is the person who created the Tender and is responsible for the Tender and the first approver of the Bid.
MATCH (:PublishedTenderS)-[:HAS]->(t:Tender {Title: "Tender 1"})<-[:HAS_TENDER]-(b:Bid {BidCode: "B79c69d9843ff"}), (t)-[:HAS_REQUESTER]->(e)<-[:HAS]-(:Role {Name: "Requester"})
CREATE (b)-[:HAS_BID_REQUESTER_APPROVAL {Date: localdatetime.transaction(), Comment: "This bid is approved"}]->(e);

// Donald (the Tender 4 Requester) will approve Bid from Vendor 8 of Tender 4. The Requester is the person who created the Tendrr and is responsible for the Tender and the first approver of the Bid.
MATCH (:PublishedTenderS)-[:HAS]->(t:Tender {Title: "Tender 4"})<-[:HAS_TENDER]-(b:Bid {BidCode: "B784981c5b0cc"}), (t)-[:HAS_REQUESTER]->(e)<-[:HAS]-(:Role {Name: "Requester"})
CREATE (b)-[:HAS_BID_REQUESTER_APPROVAL {Date: localdatetime.transaction(), Comment: "This bid is approved"}]->(e);

//However, Gloria (the L1 Approver) will reject the Bid from Bid from Vendor 8 of Tender 4.
MATCH (:PublishedTenderS)-[:HAS]->(t:Tender {Title: "Tender 4"})<-[:HAS_TENDER]-(b:Bid {BidCode: "B784981c5b0cc"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"})
CREATE (b)-[:HAS_L1_REJECTION {Date: localdatetime.transaction(), Comment: "This bid is rejected by L1"}]->(l1);
 

// Gloria (the L1 Approver) will approve the Bid 1 from Vendor 7 for Tender 1 
MATCH (:PublishedTenderS)-[:HAS]->(t:Tender {Title: "Tender 1"})<-[:HAS_TENDER]-(b:Bid {BidCode: "B79c69d9843ff"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"})
CREATE (b)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This bid is approved"}]->(l1);

// Sara (the L2 Approver) will approve the Bid 1 from Vendor 7 for Tender 1  
MATCH (:PublishedTenderS)-[:HAS]->(t:Tender {Title: "Tender 1"})<-[:HAS_TENDER]-(b:Bid {BidCode: "B79c69d9843ff"}), (l2:Employee {Name: "Sara"})<-[:HAS]-(:Role {Name: "Level2Approver"})     
CREATE (b)-[:HAS_L2_APPROVAL {Date: localdatetime.transaction(), Comment: "This bid is approved"}]->(l2);


// Christine (the L3 Approver) will approve the Bid 1 from Vendor 7 for Tender 1, and as the L3 is the final approver, let’s move the Tender to the AwardedTenders Collection and remove it from the PublishedTenderS Collection 
MATCH (:PublishedTenderS)-[r1:HAS]->(t:Tender {Title: "Tender 1"})<-[:HAS_TENDER]-(b:Bid {BidCode: "B79c69d9843ff"})-[:HAS_VENDOR]->(v), (l3:Employee {Name: "Christine"})<-[:HAS]-(:Role {Name: "Level3Approver"}), (aw:AwardedTenderS {Name: "AwardedTenderS"})
CREATE  (b)-[:HAS_L3_APPROVAL {Date: localdatetime.transaction(), Comment: "This bid is approved"}]->(l3),
        (aw)-[:HAS]->(t),
        (t)-[:HAS_AWARDED_VENDOR {Date: localdatetime.transaction()}]->(v), // This relationship is redundant (optional), as the Bid already has a relationship with the Vendor, but it is kept for clarity and future reference.
        (t)-[:HAS_AWARDED_BID {Date: localdatetime.transaction()}] ->(b)
 DELETE r1;

// Note that as we remove the Awarded Tender from the PublishedTenderS Domain Collection, it will not be available for further processing in the Tender Approval Workflow.
// That is, Tender 1 will not be available for further Tender Approvals, as it is now in the AwardedTenderS Domain Collection.


// Finally, let’s move Tender 1 to the AwardedTenders Domain Collection so that it can be used for further processing, like creating a contract or invoicing, and perhaps the start of a new Supply Chain Workflow (Graph). 
// We will also remove Bid 1 from the ActiveBids Collection of Vendor 7 and move it to the AwardedBids Collection of Vendor 7
MATCH  (aw:AwardedTenderS {Name: "AwardedTenderS"})-[HAS]->(t)<-[:HAS_TENDER]-(b:Bid {BidCode: "B79c69d9843ff"})<-[r1:HAS]-(:ActiveBidS)<-[:HAS_ACTIVE_BIDS]-(v)-[:HAS_AWARDED_BIDS]->(ab)
CREATE (ab)-[:HAS]->(b)
DELETE r1; // Remove the Bid from the ActiveBids Collection of the Vendor 7

// We will also communicate with the Vendor that was awarded
MATCH  (e:Employee {Name: "System"}), (aw:AwardedTenderS {Name: "AwardedTenderS"})-[HAS]->(t)<-[:HAS_TENDER]-(b:Bid {BidCode: "B79c69d9843ff"})-[:HAS_VENDOR]->(v)-[HAS_CHAT]->(c:ConversatioN)
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "Congratulations! The Bid for Tender 1 has been awarded to you! We look forward for to starting the Project as soon as possible."})-[:SENT_BY]->(e);

// Now we must communicate all the Tender 1 Bidders that were not awarded to the Vendors, so they can take the necessary actions.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 1"})-[:HAS_BIDS]->(:TenderBidS)-[:HAS]->(b)<-[:HAS_VENDOR]-(v)-[:HAS_CHAT]->(c:ConversatioN) WHERE NOT (t)-[:HAS_AWARDED_BID]->(b)
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "The Bid for Tender 1 has not been awarded to you. We thank you for your participation and look forward to working with you in the future."})-[:SENT_BY]->(e);

// We will also move the Bids from these vendors to ActiveBids to their respective PastBids Collection so that they can have them on record.
// The Vendor can traverse from the Bids to get the Tender Info of previous Tenders in which they participated
// We will also remove the Tender from their Accepted Invitations, so only the active Tenders remain there. 
MATCH (t:Tender {Title: "Tender 1"})-[:HAS_BIDS]->(:TenderBidS)-[:HAS]->(b)<-[r1:HAS]-(ab)<-[:HAS_ACTIVE_BIDS]-(v)-[:HAS_PAST_BIDS]->(pb) WHERE NOT (t)-[:HAS_AWARDED_BID]->(b)
WITH t , v , r1 , b, pb
MATCH (v)-[:HAS_ACCEPTED_INVITATONS]->(ai)-[r2:HAS]-(t) 
CREATE (pb)-[:HAS]->(b) 
DELETE r1, r2;

// This concludes a full Tender workflow for Tender 1. 
// I will intentionally leave other Tenders in different stages/states so you can query the Graph and see where they are in the Workflow
// The tender will remain on the AwardedTendrS until the termination/full delivery of the Tender product/service. We can then move it to the ClosedTenderS Domain collection. 
// Or... move it to another Domain Model (Graph) that will manage the Delivery (Supply Chain, Project Management, etc.)





// Now that we have the complete cycle, with all schemas in place, we will create some additional Tenders and run some additional workflows to create more Data for us to query. 

// -------- Tender #10

// The Requester Employee will log in, and the UI will gather all the information and execute the following Cypher command to create the Tender and supporting schema Nodes 
// Create the Tender 10 + Schema and let the system generate the Tender Code 
MATCH (em:Employee {Name: "Albert"}), (nt:NewTenderS {Name: "NewTenderS"}), (ty:TenderType {Name: "Open"}) 
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 10", Description: "This is the tenth tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 20}) , Budget: 100000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_10_RFP", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Albert/Tender1/RFPDocument_t10.pdf", Description: "This is the Tender 10 RFP Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_10_RFP_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Albert/Tender10/RFPResponseTemplate-t10.pdf", Description: "This is the Tender 10 RFP mandatory response template", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_10_RFP_Presentation", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Albert/Tender10/RFPPresentation_t10.pdf", Description: "This is the Tender 10 RFP Presentation", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender #11

// Create the Tender 11 + Schema and let the system generate the Tender Code
MATCH (em:Employee {Name: "Brandon"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Selective"}) 
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 11", Description: "This is the eleventh tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 500000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_11_RFP", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Brandon/Tender11/RFPDocument_t11.pdf", Description: "This is the Tender 11 RFP Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_11_RFP_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Brndon/Tender11/RFPResponseTemplate-t11.pdf", Description: "This is the Tender 11 RFP mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender #12

// Create Tender 12 + Schema and let the system generate the Tender Code. This will be a "Negotiated" Tender Type, and we will only invite Vendor 7 to it.
MATCH (em:Employee {Name: "Charles"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Negotiated"}) 
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 12", Description: "This is the twelvth tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 45}) , Budget: 1300000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_12_RFP", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Charles/Tender12/RFPDocument_t12.pdf", Description: "This is the Tender 12 RFP Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_12_RFP_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Charles/Tender12/RFPResponseTemplate-t12.pdf", Description: "This is the Tender 12 RFP mandatory response template", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_12_RFP_Presentation", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Charles/Tender12/RFPPresentation_t12.pdf", Description: "This is the Tender 12 RFP Presentation", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender #13

// Create the Tender 13 + Schema and let the system generate the Tender Code  
MATCH (em:Employee {Name: "Donald"}), (nt:NewTenderS {Name: "NewTenderS"}) , (ty:TenderType {Name: "Open"}) 
CREATE (t1:Tender {TenderCode: "T"+left(randomUUID(),8)+right(randomUUID(),4), Title: "Tender 13", Description: "This is the thirteenth tender for testing purposes", SubmissionDate: localdatetime.transaction(), EndBidingDate: localdatetime.transaction() + duration({days: 30}) , Budget: 70000 })<-[:HAS]-(nt),
         (t1)-[:HAS_DOCS]->(d:TenderDocS {Name: "TenderDocS"})-[:HAS]->(:Doc {DocName: "Tender_13_RFQ", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Donald/Tender13/RFQDocument_t13.pdf", Description: "This is the Tender 13 RFQ Document", Date: localdatetime.transaction()}),
         (d)-[:HAS]->(:Doc {DocName: "Tender_13_RFQ_ResponseTemplate", Type: "PDF", URL: "https://company-my.sharepoint.com/personal/Donald/Tender13/RFQResponseTemplate-t13.pdf", Description: "This is the Tender 13 RFQ mandatory response template", Date: localdatetime.transaction()}),
         (t1)-[:HAS_REQUESTER]->(em),
         (t1)-[:HAS_TYPE]->(ty),
         (t1)-[:HAS_CHAT]->(:ConversatioN {Name: "ConversatioN"});


// -------- Tender vetting 

// ------ Tender #10 Approval
// Let's have the L1 approver (Gloria) approve Tender 10. 
// As Tender 10 Budget is less than $200000, we will not have a L2 or L3 approver for it.
// The Tender 10 will be approved by the L1 approver (Gloria) and moved to the ApprovedTenderS Collection.     
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 10"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"}),  (at:ApprovedTenderS {Name: "ApprovedTenderS"})
CREATE (t)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l1),
       (at)-[:HAS]->(t)
DELETE r1;  


// ------ Tender #12 Approval
// Tender 12 budget is $1,300,000 so all three Levels need to Approve it
// Let's have the L1 approver (Gloria) approve the Tender 12 
MATCH (t:Tender {Title: "Tender 12"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"})
CREATE (t)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l1);

// Let’s have the L2 approver (Sara) approve the Tender 12
MATCH (t:Tender {Title: "Tender 12"}), (l2:Employee {Name: "Sara"})<-[:HAS]-(:Role {Name: "Level2Approver"})
CREATE (t)-[:HAS_L2_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l2);


// Let's have the L3 approver (Christine) approve the Tender 12, and as the 12 is the final approver, let's move the Tender to the ApprovedTenderS Collection and remove it from the NewTenderS Collection
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 12"}), (l3:Employee {Name: "Christine"})<-[:HAS]-(:Role {Name: "Level3Approver"}), (at:ApprovedTenderS {Name: "ApprovedTenderS"})
CREATE (t)-[:HAS_L3_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l3),
       (at)-[:HAS]->(t)
DELETE r1;



// ------ Tender #13 Approval
// Let's have the L1 approver (Gloria) approve Tender 13. 
// As Tender 13 Budget is less than $200000, we will not have a L2 or L3 approver for it.
// The Tender 13 will be approved by the L1 approver (Gloria) and moved to the ApprovedTenderS Collection.     
MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 13"}), (l1:Employee {Name: "Gloria"})<-[:HAS]-(:Role {Name: "Level1Approver"}),  (at:ApprovedTenderS {Name: "ApprovedTenderS"})
CREATE (t)-[:HAS_L1_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved"}]->(l1),
       (at)-[:HAS]->(t)
DELETE r1;  



// ---------   Tender Publishing


// Publish Tender 10

// Let's move Tender 10 to the PublishedTenderS Collection by the Publisher (Cloe) and delete the relationship from the ApprovedTenderS Collection.
// Now that we are publishing the Tender, we will also create the Tender's "InvitedVenrorS" collection to place the Vendors that will be invited and the TenderBidS collection
MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 10"}), (p:Employee {Name: "Cloe"})<-[:HAS]-(:Role {Name: "Publisher"}), (pt:PublishedTenderS {Name: "PublishedTenderS"})
CREATE (t)-[:HAS_PUBLISHER_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved for Publishing"}]->(p),
       (t)-[:HAS_INVITEES]->(:InvitedVendorS {Name: "InvitedVendorS"}),
       (t)-[:HAS_BIDS]->(:TenderBidS {Name: "TenderBidS"}),
       (pt)-[:HAS]->(t)
DELETE r1;       

// As Tender 10 is Type "Open", we can invite all the Approved Vendors to it. The UI will do this.
// In a real scenario, there would be more criteria to select the Vendors (type, size, etc.), and the Cypher query would need to be tailored, but for this demo, we will just invite all of them.
MATCH (t:Tender {Title: "Tender 10"})-[:HAS_INVITEES]->(iv:InvitedVendorS {Name: "InvitedVendorS"})
UNWIND COLLECT {MATCH (v:Vendor)<-[:HAS]-(:ApprovedVendorS) RETURN v} AS vendor
        CREATE (iv)-[:HAS {Date: localdatetime.transaction()}]->(vendor);

// Now we must communicate all the Tender 1 invitees about their invitation so they can decide if they want to participate in the Tender.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 10"})-[:HAS_INVITEES]->()-[:HAS]->(v)-[:HAS_CHAT]->(c:ConversatioN)  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "You have been Invited to participate on a tender (Tender 10)."})-[:SENT_BY]->(e);

// Publish Tender 12

// Let's move Tender 12 to the PublishedTenderS Collection by the Publisher (Cloe) and delete the relationship from the ApprovedTenderS Collection.
// Now that we are publishing the Tender, we will also create the Tender's "InvitedVenrorS" collection to place the Vendors that will be invited and the TenderBidS collection
MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[r1:HAS]->(t:Tender {Title: "Tender 12"}), (p:Employee {Name: "Cloe"})<-[:HAS]-(:Role {Name: "Publisher"}), (pt:PublishedTenderS {Name: "PublishedTenderS"})
CREATE (t)-[:HAS_PUBLISHER_APPROVAL {Date: localdatetime.transaction(), Comment: "This tender is approved for Publishing"}]->(p),
       (t)-[:HAS_INVITEES]->(:InvitedVendorS {Name: "InvitedVendorS"}),
       (t)-[:HAS_BIDS]->(:TenderBidS {Name: "TenderBidS"}),
       (pt)-[:HAS]->(t)
DELETE r1;    

// As this Tender 12 is Type "Negotiated", we will invite a single Approved Vendor to it. In this case, we will invite Vendor 10.
MATCH (t:Tender {Title: "Tender 12"})-[:HAS_INVITEES]->(iv:InvitedVendorS {Name: "InvitedVendorS"})
MATCH (v:Vendor {ShortName: "Vendor 10"})<-[:HAS]-(:ApprovedVendorS)
        CREATE (iv)-[:HAS {Date: localdatetime.transaction()}]->(v);

// Now we must communicate all the Tender 12 invitees about their invitation so they can decide if they want to participate in the Tender.
MATCH (e:Employee {Name: "System"}), (t:Tender {Title: "Tender 12"})-[:HAS_INVITEES]->()-[:HAS]->(v)-[:HAS_CHAT]->(c:ConversatioN)  
CREATE (c)-[:HAS {Date: localdatetime.transaction()}]->(m:Message {Text: "You have been Invited to participate on a tender (Tender 12)."})-[:SENT_BY]->(e);

// End of Script!
// This script has created a complete Tender Workflow with all the necessary schema and data to query and test the Tender Management System. 
// Now you can query the Graph to see the Tenders, Bids, Vendors, and all the related information. 
// Spend some time exploring the Graph and the data, traverse the Graph Database, understand the logic, and how the data is connected.
// Learn how this approach can be used to build any Workflow Application in a Graph Database.
