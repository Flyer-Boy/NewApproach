# Ride-Hailing Graph App

The React + TypeScript (Vite) prototype for the Ride-Hailing proof of concept. It runs directly on the graph through `neo4j-driver` and the `use-neo4j` hooks.

**Full documentation, including the model, setup and limitations: see the [RideHailing README](../README.md).**

## Quick start

1. Load the model into Neo4j with [`../RideHailing.cypher`](../RideHailing.cypher), or restore `../neo4j-RideHailingDB.backup`. (`RideHailing.cypher` in this folder is a copy of the same script.)
2. Copy `.env.example` to `.env` and fill in your Neo4j connection.
3. Install and run:

   ```bash
   npm install
   npm run dev
   ```

   The dev server runs on port 3031 and opens your browser.

> 🔒 **Demo only.** Vite embeds `VITE_*` variables into the JavaScript sent to the browser, so the database credentials are visible to anyone using the app. A real deployment needs a backend or API layer in between. `.env` is ignored by git; never commit real credentials.

Released under the GNU GPL v3 (see `COPYING`).
