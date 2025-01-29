# A new approach to application development using Cypher/GQL (Graphs)
 

This repository is part of my Articles on developing applications using a Graph Database.  

- https://medium.com/@marcospinedo/a-new-approach-to-application-development-using-cypher-gql-graphs-7d191e0c55d3
- (TBD)

It is comprised of a few Cypher scripts that I used to demonstrate some concepts applied to a Ride-Hailing scenario. 

The files are:

RideHailing.cypher — This script can be executed in full to create the initial nodes (Passengers, Drivers, Cars, and Bookings) that will be in different states so you can familiarize yourself with the Model. 
   
RideHailing_Queries. cipher —  This script contains a few Cypher queries that you can execute against the Database. I will add more queries over time.

RideHailing_Templates.cypher  — This script contains Cypher commands that you can use to build a mockup application as they appear in the Article. You will need to pars the script by replacing the <field name> with the proper variable.  

In the #RideHailingGraphApp directory you will find the code for a Prototype App built with React+TypeScript that uses the RideHailing data model to run. Download it and try it out. 

You can try it with Neo4j Aura. If you don't have an Aura account yet, get one here: https://neo4j.com/cloud/aura-free/ 
If you are new to Cypher, you can get started at Neo4j's GraphAcademy: https://graphacademy.neo4j.com/
