# A new approach to application development using Cypher/GQL (Graphs)
 
After decades of working with RDBMS/SQL and enterprise software development, I dedicated eight years—and counting—to exploring and developing new ways to build Line of Business applications using Graph Databases, discovering innovative ways to leverage Graphs far beyond their conventional use cases.

This journey began in 2013, after 17 years at Microsoft, where I worked in its Consulting division and later led Developer and Platform Evangelism across Brazil and Asia Pacific. I invested in and joined a startup to build what I believed could become a revolutionary Graph-Native Platform, where I helped develop many of the concepts, principles, and methodologies I continue to enhance, adapt, and advocate today.

Unfortunately, the startup did not survive. We were too ambitious and, arguably, ahead of our time in a very conservative market. Nevertheless, I believe those concepts and ideas are even more relevant today as we enter the AI era.

My deep dive into Graphs turned me into a passionate advocate, and I have become increasingly unwilling to see their potential confined to Data Science, Knowledge Graphs, or Graph RAG for LLMs—which together represent only a small fraction of the broader database market.

Graphs are not merely specialized tools for specialized use cases. I believe they can become the ideal foundation for almost any Line of Business application.

Data should be conceived and created in the Graph—not created elsewhere in tables and subsequently imported into a Graph. When the Graph becomes the native data substrate, we can unlock the full potential of relationships, semantics, ontology, context, and ultimately Data Science and Knowledge Graph capabilities from the very beginning.

Most importantly, Graph-Native systems are inherently **Agentic AI-ready**. They can gather, connect, and expose the information, context, semantics, ontology, and even embeddings that AI agents need to reason about data in real time—without relying on expensive, complex ETL pipelines or repeated data ingestion from disconnected tables.

This is the fundamental shift I am advocating: **don't put Graphs around your applications. Build the applications around the Graph.**

**This has evolved far beyond a side project. It is now a life mission—one I will pursue for as long as it takes, until I see it become reality in one form or another.**

This repository is an extension of my Articles on developing applications using a Graph Database, using an alternative approach; here are a few:

1) **The Concept:**  https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3

   In a nutshell/key principles:

* **Proper Noun Nodes:**

    Nodes should only store properties that define the uniqueness of the entity (the "Thing") they represent. Any property that represents a state or an entity’s contextual relevance to another entity should be modeled as a relationship, not a property of the entity. This makes the model semantically explicit. Nothing is hidden inside entity properties. You (and AI) can understand and reason on the entire model at any state without reading its properties. 

* **Never Delete Nodes:**

    Nodes are never deleted, ensuring full traceability of all entities over time. Time flows in one direction. What is done cannot be undone. If the model is a faithful representation of the real world, this principle should be respected. In this model, entities are archived and timestamped so they can be looked up later.    

* **Read-Only Nodes:**

    Once created, node properties should remain unchanged. The SET command is strictly reserved for value corrections or certain edge cases/exceptions, but not the norm. This approach significantly simplifies transaction concurrency and consistency management, which is a major differentiator from traditional RDBMS models, where property updates are common and often introduce complexity. If your domain model requires/demands constant property updates across multiple entities (e.g., ledger systems), you might stick to the traditional RDBMS/table-based architecture rather than the one being proposed here.   

* **Relationships Drive the System (workflow):**

    The system relies on creating new nodes and then creating/deleting their relationships according to the model workflow rules/state changes. This might sound odd at first, but think of it…this is how everything you know, from the micro to macro universe, including yourself, works. There are 118 stable elements in the periodic table (that we know of) that create everything we know just by altering their relationships. Not by changing their properties, except for isotopes (the edge cases I mention earlier, the exceptions but not the norm). Nature is showing us the way. This is biomimicry applied to software architecture.  

*  **Lean Nodes:**

    Outgoing relationships are minimized. For one-to-many connections, we use some nodes as Collections. Collections can represent domain States as well as Context (i.e, virtual aggregation). While relational algebra relies on implicit set operations (Union, Intersection, Difference, Cartesian product), I will use explicit ones (Superset, Subset, Element of), aligning with how nature and humans intuitively organize reality into sets. This aligns the Graph with the domain expert mental model. While this introduces an additional traversal cost, the structure scales better as the database grows. There are deeper considerations behind this, involving how the Graph is stored (how Node properties and its adjacency table are stored) and the implications for indexing, query optimization, and performance, as well as Node digital rights management (DRM) considerations. Still, I won’t go down that rabbit hole here. However, they are highly relevant and taken into consideration. I’m aware that current Graph Databases are not fully optimized for this, but they will at some point. I witnessed and worked with the first RDBMS and saw how they evolved in the past decades; Graph Databases will too.

2) **The Ride Hailing POC App Explainer:** https://medium.com/@marcospinedo/ride-hailing-graph-app-prototype-explainer-071a89543a90

3) **How to use Graphs to build Business Processes/Workflows**: https://medium.com/@marcospinedo/how-graphs-simplify-business-processes-and-workflows-like-moving-balls-between-baskets-c9606c9e973f

4) **A video presentation of the Concepts + POC Demo:** https://youtu.be/ExupBmmH1Rs - I also recommend the companion article with the slides and extended transcripts: https://medium.com/@marcospinedo/rethinking-line-of-business-applications-graphs-cypher-as-an-alternative-to-rdbms-sql-fd1d204f99b7

In this repo, you will find a few Cypher scripts I used to demonstrate concepts in a Ride-Hailing POC, along with the Prototype (POC) Application code. It also includes the Tender Workflow script, illustrating how a Workflow application can be developed using Graphs. 

I will keep adding content and prototypes on using Graphs to build line-of-business applications, fusing this New Approach.   

The files are:
The files are:

1. **/RideHailing/RideHailing.cypher** — This script can be executed in full to create the initial nodes (Passengers, Drivers, Cars, and Bookings) in different states so that you can familiarize yourself with the Model.
2. **/RideHailing/neo4j-RideHailingDB.backup** — Alternatively, instead of creating the initial nodes from scratch (script), you can use this Neo4j backup to restore a database with all the initial nodes and some bookings already made.
3. **/RideHailing/RideHailing_Queries.cypher** — This script contains a few Cypher queries that you can execute against the Database. I will add more queries over time.
4. **/RideHailing/RideHailing_Templates.cypher** — This script contains Cypher commands you can use to build a mockup application as they appear in the Article. You must parse the script by replacing it with the proper variable.
5. In the **/RideHailing/RideHailingGraphApp** directory, you will find the code for a Prototype App built with React+TypeScript that uses the RideHailing data model to run. Download it and try it out!!
6. **/RideHailing/The RideHailingGraphModel.png** - The Ride Hailing Graph database model for your reference.
7. **/TenderWorkflow/TenderWorkflow v5.cypher** - A Tendering System Proof of Concept (POC) simulation script. This script simulates a Tender system running on a Graph, where the Graph acts as both the Data and Logic layer. (Neo4j Compatible)
8. **/TenderWorkflow/TenderWorkflow v6.cypher** - The Tendering System Proof of Concept (POC) simulation script with the RelType property on the “:HAS” collection relationships. (Neo4j Compatible)
9. **/TenderWorkflow/TenderWorkflow v6 - MemGraph.cypher** - The Tendering System Proof of Concept (POC) simulation script adapted to work on MemGraph (MemGraph Compatible)
10. **/TenderWorkflow/TenderWorkflow Graph Model.png** - The Tender Workflow model for you to have a look at.
11. The NEW **/TenderWorkflow/TenderWorkflow v7.1.cypher** - Now with full ontology implementation
12. The NEW **/TenderWorkflow/TenderGraphType v1.cypher** - TenderWorkflow v7.1 companion script that implements Cypher 25/Neo4j 2026.02 GRAPH TYPE, adding an extra layer of ontology compliance to the Tender Workflow. (requires Neo4j Aura with Cypher 25)
13. The **/TenderWorkflow/Tender_Workflow_Random_Test_Generator.py** is a parameterized Python application that serves as a Tender Workflow Random Test Generator (Thanks, Claude, for your help). It randomly creates new Tenders, vets them, invites vendors, accepts Bids, vets the bids, and awards (or not) the Tenders strictly following the Workflow rules, showcasing this Approach of using graphs to run any workflow Business Application, with full Ontology and Context built in from inception. I invite you to play with it and stress test the Graph!
14. The **/NorthWind** - The good old NorthWind database model adapted to the Graph Model according to the concepts/key principles. You will find the Cypher script and the import files (fixed, as the original ones provided by Neo4j ([neo4j-graph-examples/northwind](https://github.com/neo4j-graph-examples/northwind): From RDBMS to Graph, using a classic dataset) are not properly cleaned up, as I reported: Some CSV files have misplaced fields due to comas · Issue #53 · neo4j-graph-examples/northwind) 
15. The **/NorthWindPLUS** - This is still “work in progress” (WIP). It is an ambitious project in which I am adding a full ontology to this old model and making it a 360/full-cycle process with everything I can add. When the Graph model is completed, I will create the Python loop applications that will simulate each part of the model separately (Random Customer Orders, PO generation for low inventory, PO vetting with 3+ vetting levels, Supplier RFQ submission for incoming PO’s, RFQ vetting, Inventory update as PO’s are fulfilled, Customer Order fulfillment, Inventory update, Customer order shipping, recomendation engine update, etc.. ) so you can run them in paralell and see if the Graph holds the load.

Most of the Cypher scripts are documented, and they explain what is going on at each block, so you can learn how the concepts/principles are being applied to the model. They are a good learning resource. 

To try these scripts out and get to understand the concepts, you will need a Neo4j Database.     

You can try it with Neo4j Aura or Neo4j Desktop. If you don’t have an Aura account yet, get one here: https://neo4j.com/cloud/aura-free/. If you are new to Cypher, you can get started at Neo4j’s GraphAcademy: https://graphacademy.neo4j.com/

I used Neo4j Cypher in my scripts and the code above. With the standardization of GQL and the widespread adoption of OpenCypher, the portability of Cypher-based scripts across various graph databases is becoming increasingly feasible. However, it is always subject to nuances in graph implementation.

I am constantly testing my model with different Graph Databases, and when they work, I will place the scripts adapted to the Graph's Cipher/GQL implementation. 


**“Alea iacta est”—crossing the Rubicon of Graph adoption!** 🚀

Enjoy!



*(If you are curious about the repo name “Flyer-Boy”, well...that is a long, long story, and it happens to be my XBOX Gametag “Flyerboy”, Instagram name, Discord tag, etc… it now follows me everywhere, so bear with it. Sorry)*
