// -- NorthWind PLUS Graph Data Model: upgrade an existing v2.3.1 database to v2.3.2 (Neo4j Aura) --//
//
// Use this on a database that already has the v2.3.1 model (and possibly a running simulation) instead of
// re-running the full import script. Safe to run more than once: every statement uses MERGE.
// You can run it while the Python loops are running -- none of the loops touch these nodes.
//
// What v2.3.2 adds:
//   1. RolE "ProcurementPolicyAdmin" -- the only role allowed to change the L1/L2/L3 approval bands.
//   2. One Employee holding that role: Olivia Bennett, EmployeeID "25".
//   3. The PolicyChange node type (created later by the **Approval Policy Change** command in the import script).
//      No data is created for it here; step 3 below only updates the GRAPH TYPE.
//
// Steps:
//   1. Run the two statements below.
//   2. Check the result with the verification query at the end.
//   3. Run NorthwindPlusGraphType_v2.3.2.cypher so the GRAPH TYPE declares PolicyChange, REQUESTED_BY and CHANGED_ROLE.

// 1a. The new role, connected to the RoleS collection.
MATCH (r:RoleS {Name:"RoleS"})
MERGE (pp:RolE {Title:"ProcurementPolicyAdmin"})
  ON CREATE SET pp.Description = "Procurement Policy Administrator",
                pp.Rules = "Maintains the procurement approval policy: the only role allowed to change the Level 1/2/3 PO approval bands (ApprovalBase/ApprovalLimit). Every change is recorded as a PolicyChange."
MERGE (r)-[:HAS_ROLE_TITLE]->(pp);

// 1b. The new Employee, in the Employee Directory, holding the new role.
MATCH (ed:EmployeeDirectorY {Name:"EmployeeDirectorY"}), (pp:RolE {Title:"ProcurementPolicyAdmin"})
MERGE (e:Employee {EmployeeID:"25", Email:"Olivia.Bennett@northwind.com"})
  ON CREATE SET e.Extension = "1254"
MERGE (e)-[:HAS_PERSON]->(p:Person {FirstName:"Olivia", LastName:"Bennett"})
  ON CREATE SET p.BirthDate = "1982-04-18 00:00:00.000", p.PersonalPhone = "95712874", p.PersonalEmail = "Olivia.Bennett@email.com"
MERGE (ed)-[ae:HAS_ACTIVE_EMPLOYEE]->(e)
  ON CREATE SET ae.StartDate = datetime()
MERGE (pp)-[ar:IS_ACTIVE_ROLE]->(e)
  ON CREATE SET ar.StartDate = datetime();

// 2. Verification -- expect one row: ProcurementPolicyAdmin, 25, Olivia Bennett.
MATCH (:RoleS {Name:"RoleS"})-[:HAS_ROLE_TITLE]->(pp:RolE {Title:"ProcurementPolicyAdmin"})-[:IS_ACTIVE_ROLE]->(e:Employee)-[:HAS_PERSON]->(p:Person)
RETURN pp.Title AS Role, e.EmployeeID AS EmployeeID, p.FirstName + " " + p.LastName AS Name;
