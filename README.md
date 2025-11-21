# A new approach to application development using Cypher/GQL (Graphs)
 
After decades of working with RDBMS and SQL, I dedicated five years to building and exploring Graph Databases, discovering innovative ways to leverage them beyond conventional approaches. My deep dive into Graphs turned me into a passionate advocate, unwilling to see their potential confined to Data Science, Knowledge Graphs, or Graph RAG for LLMs — currently a mere 2% of the entire database market. Graphs aren’t just specialized tools but the ideal foundation for almost any application. Data should be born in the Graph, not created elsewhere and then imported. By doing so, we unlock the full power of Data Science and Knowledge Graphs from the start. Most importantly, graph-native systems are Agentic AI-ready, as they gather all the information + context/semantics needed for reasoning.

This repository is part of my Articles on developing applications using a Graph Database, using an alternative approach:

 1. **The Concept:**  https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3
 2. **The App Explainer:** https://medium.com/@marcospinedo/ride-hailing-graph-app-prototype-explainer-071a89543a90
 3. **How to use Graphs to build Business Processes/Workflows:** https://medium.com/@marcospinedo/how-graphs-simplify-business-processes-and-workflows-like-moving-balls-between-baskets-c9606c9e973f
 4. **A video presentation of the Concepts + Demo:** https://youtu.be/ExupBmmH1Rs 


It comprises a few Cypher scripts that I used to demonstrate concepts applied to a Ride-Hailing scenario, along with the Prototype (POC) Application code. It also includes the Tender Workflow script, illustrating how a Workflow application can be developed using Graphs. If I build a UI for the Tender Workflow in the future, I will place it in this repo as well.

The files are:

 1. **RideHailing.cypher** — This script can be executed in full to create the initial nodes (Passengers, Drivers, Cars, and Bookings) in different states so you can familiarize yourself with the Model.
 2. **neo4j-RideHailingDB.backup** — Alternatively, instead of creating the initial nodes from scratch (script), you can use this Neo4j backup to restore a database with all the initial nodes and some bookings already made. 
 3. **RideHailing_Queries.cypher** — This script contains a few Cypher queries that you can execute against the Database. I will add more queries over time.
 4. **RideHailing_Templates.cypher** — This script contains Cypher commands you can use to build a mockup application as they appear in the Article. You must parse the script by replacing it with the proper variable.
 5. In the **RideHailingGraphApp** directory, you will find the code for a Prototype App built with React+TypeScript that uses the RideHailing data model to run. Download it and try it out!!
 6. **The RideHailingGraphModel.png** - The Ride Hailing Graph database model for your reference.
 7. **TenderWorkflow v5.cypher** - A Tendering System Proof of Concept (POC) simulation script. This script simulates a Tender system running on a Graph, where the Graph acts as both the Data and Logic layer. (Neo4j Compatible)
 8. **TenderWorkflow v6.cypher** - The Tendering System Proof of Concept (POC) simulation script with the RelType property on the ":HAS" collection relationships. (Neo4j Compatible)
 9. **TenderWorkflow v6 - MemGraph.cypher - ** - The Tendering System Proof of Concept (POC) simulation script adapted to work on MemGraph (MemGraph Compatible)
 10. **TenderWorkflow Graph Model.png** - The Tender Workflow model for you to have a look at.

You can try it with Neo4j Aura or Neo4j Desktop. If you don't have an Aura account yet, get one here: https://neo4j.com/cloud/aura-free/. If you are new to Cypher, you can get started at Neo4j's GraphAcademy: https://graphacademy.neo4j.com/

I used Neo4j Cypher on my scripts and the code above. With the standardization of GQL and the widespread adoption of OpenCypher, the portability of Cypher-based scripts across various graph databases is becoming increasingly feasible. However, it is always subject to nuances in graph implementation.  

"Alea iacta est"—crossing the Rubicon of Graph adoption! 🚀

Enjoy! 

