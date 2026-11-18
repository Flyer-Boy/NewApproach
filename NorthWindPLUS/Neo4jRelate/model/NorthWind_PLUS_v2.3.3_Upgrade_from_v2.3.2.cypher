// -- NorthWind PLUS Graph Data Model: upgrade an existing v2.3.2 database to v2.3.3 (Neo4j Aura) --//
//
// Use this on a database that already has the v2.3.2 model (and possibly a running simulation) instead of
// re-running the full import script. Safe to run more than once: every statement uses MERGE or sets fixed values.
//
// What v2.3.3 adds (see the header of NorthWind_PLUS_Graph_Data_Model_Import_v2.3.3.cypher for the full list):
//   1. The CancelledPoS state (a rejected PO the Procurement Assistant decided not to resubmit).
//   2. Contiguous approval bands: each level's ApprovalBase equals the previous level's ApprovalLimit (no more 0.01 gap).
//      The limits themselves are kept as they are, including any change made through the governed Approval Policy Change.
//   3. In the GRAPH TYPE only: Date/Justification/Source on PO_CREATED_BY, RecommendedQt on HAS_PO_ITEM, Date/Source on
//      HAS_PREVIOUS_PO, Source on every decision relationship, and PO_CANCELLED_BY. All optional, so existing data stays valid.
//
// Steps -- in this order:
//   1. Stop the Python loops (Ctrl+C in each window). The v2.3.3 harness writes Source on every decision, which the
//      v2.3.2 GRAPH TYPE doesn't declare, so the new harness must not run before step 3.
//   2. Run the two statements below, then the verification query.
//   3. Run NorthwindPlusGraphType_v2.3.3.cypher (it replaces the whole GRAPH TYPE).
//   4. Start the loops again, in one of the two modes (set SIMULATION_MODE in .env to match):
//      run_loops_full.bat   -- all six loops; the agent answers questions, runs what-ifs and changes approval limits.
//      run_loops_agents.bat -- five loops (no PO Creation, PO Vetting with --no-resubmit); a Procurement Assistant
//                              creates and resubmits POs through the agent.
//   5. Rebuild the agent's knowledge store: python kb/build_kb.py (the Colab notebook does this when the model files change;
//      set REBUILD = True to be sure). What the agent learned is kept.

// 1. The new state collection, connected to the PoS superset.
MATCH (t:PoS {Name:"PoS"})
MERGE (c:CancelledPoS {Name:"CancelledPoS"})
MERGE (t)-[:HAS_CANCELLED_PO_STATE]->(c);

// 2. Contiguous approval bands: L2 starts at L1's limit, L3 at L2's limit. The Rules text follows the values.
//    This changes no limit, only removes the 0.01 gap, so it isn't recorded as a PolicyChange: it's part of the model upgrade.
MATCH (l1:RolE {Title:"Level1Approver"}), (l2:RolE {Title:"Level2Approver"}), (l3:RolE {Title:"Level3Approver"})
SET l2.ApprovalBase = l1.ApprovalLimit,
    l3.ApprovalBase = l2.ApprovalLimit,
    l1.Rules = "Approves PO with a Budget above 0.00 and up to " + toString(l1.ApprovalLimit),
    l2.Rules = "Approves PO with a Budget above " + toString(l1.ApprovalLimit) + " and up to " + toString(l2.ApprovalLimit),
    l3.Rules = "Approves PO with a Budget above " + toString(l2.ApprovalLimit) + " and up to " + toString(l3.ApprovalLimit)
RETURN l1.ApprovalLimit AS L1Limit, l2.ApprovalBase AS L2Base, l2.ApprovalLimit AS L2Limit, l3.ApprovalBase AS L3Base, l3.ApprovalLimit AS L3Limit;

// Verification -- expect one row: CancelledPoS present, bands contiguous, and the Procurement Assistants who will use the agent.
MATCH (:PoS {Name:"PoS"})-[:HAS_CANCELLED_PO_STATE]->(c:CancelledPoS)
MATCH (l1:RolE {Title:"Level1Approver"}), (l2:RolE {Title:"Level2Approver"}), (l3:RolE {Title:"Level3Approver"})
OPTIONAL MATCH (:RolE {Title:"Procurement Assistant"})-[:IS_ACTIVE_ROLE]->(e:Employee)-[:HAS_PERSON]->(p:Person)
RETURN c.Name AS NewState,
       (abs(l2.ApprovalBase - l1.ApprovalLimit) < 0.001 AND abs(l3.ApprovalBase - l2.ApprovalLimit) < 0.001) AS BandsAreContiguous,
       collect(e.EmployeeID + " " + p.FirstName + " " + p.LastName) AS ProcurementAssistants;
