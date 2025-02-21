# A new approach to application development using Cypher/GQL (Graphs)
 
After decades of working with RDBMS and SQL, I spent five years building and exploring Graph Databases. As a passionate Graph enthusiast, I refuse to see their use limited to Data Science, Knowledge Graphs, or Graph RAG for LLMs. Graphs are the ideal data repository for almost any type of application. Data should be born in the Graph, not created elsewhere, and then imported.

This repository is part of my Articles on developing applications using a Graph Database:

 1. **The Concept:**  https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3
 2. **The App Explainer:** https://medium.com/@marcospinedo/ride-hailing-graph-app-prototype-explainer-071a89543a90


It comprises a few Cypher scripts that I used to demonstrate concepts applied to a Ride-Hailing scenario and the Prototype (POC) Application code.

The files are:

 1. **RideHailing.cypher** — This script can be executed in full to create the initial nodes (Passengers, Drivers, Cars, and Bookings) in different states so you can familiarize yourself with the Model.
 2. **RideHailing_Queries.cypher** — This script contains a few Cypher queries that you can execute against the Database. I will add more queries over time.
 3. **RideHailing_Templates.cypher** — This script contains Cypher commands you can use to build a mockup application as they appear in the Article. You must parse the script by replacing it with the proper variable.
 4. In the **RideHailingGraphApp** directory, you will find the code for a Prototype App built with React+TypeScript that uses the RideHailing data model to run. Download it and try it out!!
 5. **The RideHailingGraphModel.png** - The Ride Hailing Graph database model for your reference.

You can try it with Neo4j Aura. If you don't have an Aura account yet, get one here: https://neo4j.com/cloud/aura-free/ If you are new to Cypher, you can get started at Neo4j's GraphAcademy: https://graphacademy.neo4j.com/

I used Neo4j Cypher on my scripts and the code above. Given their close compatibility with GQL (ISO/IEC 39075:2024), they should work with any Graph Database that supports GQL with minimal amendments for compatibility. 

"Alea iacta est"

Enjoy! 

