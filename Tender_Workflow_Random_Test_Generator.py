#!/usr/bin/env python3
"""
Tender Workflow Random Test Generator
======================================

Randomly exercises the Tender Workflow graph (v7.1) built by the
TenderWorkflow Cypher script: creates Tenders, runs them through the
multi-level approval chain, publishes and invites Vendors, collects
Bids, and vets those Bids through to an award.

This script assumes the base graph already exists (Employees, Roles,
Vendors, TenderTypes, and the Domain Collection hub nodes created by
the original TenderWorkflow script) and its GRAPH TYPE schema is in
place. It only *adds* new Tenders and Bids on top of that graph --
it does not create Employees, Vendors, or Roles.

Design choice worth calling out: the L1/L2/L3 approval thresholds
(ApprovalBase / ApprovalLimit) are read from the RolE nodes in the
graph at runtime rather than hardcoded here. That's deliberate --
the whole point of the Graph-Native approach is that business rules
live in the graph, not in application code, so the test harness
respects that rather than duplicating the $200,000 / $300,000
thresholds as Python constants.

Relationship names below are taken directly from the final
TenderWorkflow v7.1 script + GRAPH TYPE schema.  

Requirements:
    pip install neo4j

Usage:
    export NEO4J_URI="neo4j://localhost:7687"
    export NEO4J_USER="neo4j"
    export NEO4J_PASSWORD="your-password"
    python tender_workflow_test_generator.py --tenders 20 --seed 42
"""

from __future__ import annotations

import argparse
import os
import random
import uuid
from dataclasses import dataclass, field
from datetime import timedelta

from neo4j import GraphDatabase, Driver


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

TENDER_SUBJECTS = [
    "IT Infrastructure Upgrade", "Facility Maintenance Contract",
    "Office Fit-Out", "Cloud Migration Services", "Fleet Vehicle Leasing",
    "Security Systems Installation", "HR Software Implementation",
    "Catering Services Contract", "Marketing Campaign Production",
    "Warehouse Automation Equipment", "Legal Advisory Retainer",
    "Network Hardware Refresh", "Employee Training Program",
    "Data Center Cooling Upgrade", "Corporate Travel Management",
]

REJECTION_CHANCE = 0.15       # chance an approver rejects at any given level
VENDOR_ACCEPT_CHANCE = 0.7    # chance an invited vendor accepts the invitation


@dataclass
class ApproverLevels:
    """L1/L2/L3 approval thresholds, read live from the graph's RolE nodes."""
    level_bases: dict[int, float] = field(default_factory=dict)   # {1: 0, 2: 200001, 3: 300001}
    approvers: dict[int, list[str]] = field(default_factory=dict)  # {1: ["Gloria"], ...}


# ---------------------------------------------------------------------------
# Reference data lookups
# ---------------------------------------------------------------------------

def fetch_reference_data(driver: Driver) -> tuple[dict[str, list[str]], list[str], ApproverLevels]:
    """Pull Employees-by-role, Approved Vendor codes, and approval thresholds
    from the live graph, so this script never hardcodes business rules."""
    with driver.session() as session:
        roles = session.run(
            """
            MATCH (r:RolE)-[:IS_ACTIVE_ROLE]->(e:Employee)
            RETURN r.Name AS role, r.ApprovalBase AS base, e.Name AS employee
            """
        ).data()

        vendors = session.run(
            """
            MATCH (:ApprovedVendorS)-[:IS_VENDOR_APPROVED_STATE]->(v:Vendor)
            RETURN v.VendorCode AS code
            """
        ).data()

        requesters = session.run(
            """
            MATCH (:RolE {Name: "Requester"})-[:IS_ACTIVE_ROLE]->(e:Employee)
            RETURN e.Name AS employee
            """
        ).data()

        publishers = session.run(
            """
            MATCH (:RolE {Name: "Publisher"})-[:IS_ACTIVE_ROLE]->(e:Employee)
            RETURN e.Name AS employee
            """
        ).data()

        tender_types = session.run("MATCH (t:TenderType) RETURN t.Name AS name").data()

    employees_by_role: dict[str, list[str]] = {}
    approver_levels = ApproverLevels()
    for row in roles:
        role = row["role"]
        employees_by_role.setdefault(role, []).append(row["employee"])
        if role.startswith("Level") and role.endswith("Approver"):
            level = int(role[len("Level")])
            approver_levels.level_bases[level] = row["base"]
            approver_levels.approvers.setdefault(level, []).append(row["employee"])

    employees_by_role["Requester"] = [r["employee"] for r in requesters]
    employees_by_role["Publisher"] = [p["employee"] for p in publishers]

    approved_vendor_codes = [v["code"] for v in vendors]
    tender_type_names = [t["name"] for t in tender_types]

    if not employees_by_role.get("Requester"):
        raise RuntimeError("No Requester employees found -- run the base TenderWorkflow script first.")
    if not approved_vendor_codes:
        raise RuntimeError("No Approved Vendors found -- run the base TenderWorkflow script first.")
    if not tender_type_names:
        raise RuntimeError("No TenderType nodes found -- run the base TenderWorkflow script first.")

    return employees_by_role, approved_vendor_codes, approver_levels, tender_type_names


def required_levels_for(budget: float, approver_levels: ApproverLevels) -> list[int]:
    """L1 is always required; L2/L3 kick in once the budget crosses that
    role's ApprovalBase, exactly mirroring the original script's logic."""
    levels = [1]
    for level in (2, 3):
        base = approver_levels.level_bases.get(level)
        if base is not None and budget >= base:
            levels.append(level)
    return levels


def new_code(prefix: str) -> str:
    """Approximates the script's 'T'/'B' + left(randomUUID(),8) + right(randomUUID(),4) pattern."""
    return f"{prefix}{uuid.uuid4().hex[:8]}{uuid.uuid4().hex[-4:]}"


# ---------------------------------------------------------------------------
# Tender creation
# ---------------------------------------------------------------------------

def create_random_tender(driver: Driver, requesters: list[str], tender_type_names: list[str]) -> tuple[str, str, float]:
    """CREATE a new Tender in the NewTenderS state, matching the pattern of
    every '-------- Tender #N' block in the original script."""
    tender_code = new_code("T")
    requester = random.choice(requesters)
    tender_type = random.choice(tender_type_names)
    subject = random.choice(TENDER_SUBJECTS)
    budget = round(random.choice([
        random.uniform(20_000, 199_999),      # L1-only tier
        random.uniform(200_001, 299_999),     # L1+L2 tier
        random.uniform(300_001, 1_500_000),   # L1+L2+L3 tier
    ]), 2)
    days_to_bid = random.randint(14, 45)

    with driver.session() as session:
        session.run(
            """
            MATCH (em:Employee {Name: $requester}), (nt:NewTenderS {Name: "NewTenderS"}),
                  (ty:TenderType {Name: $tender_type})
            CREATE (t1:Tender {
                        TenderCode: $tender_code, Title: $title,
                        Description: $description, SubmissionDate: datetime(),
                        EndBidingDate: datetime() + duration({days: $days_to_bid}),
                        Budget: $budget
                    })<-[:IS_NEW_TENDER_STATE]-(nt),
                   (t1)-[:HAS_TENDER_DOCS]->(:TenderDocS {Name: "TenderDocS"})
                        -[:HAS_TENDER_DOCUMENT]->(:TenderDoc {
                            DocName: $tender_code + "_RFP", Type: "PDF",
                            URL: "https://example.com/" + $tender_code + "/RFP.pdf",
                            Description: "Auto-generated test RFP document"
                        }),
                   (t1)-[:HAS_REQUESTER]->(em),
                   (t1)-[:IS_TENDER_TYPE]->(ty),
                   (t1)-[:HAS_TENDER_CHAT]->(:ConversatioN {Name: "ConversatioN"})
            """,
            requester=requester, tender_type=tender_type, tender_code=tender_code,
            title=f"{subject} ({tender_code})",
            description=f"Auto-generated test tender for {subject}",
            days_to_bid=days_to_bid, budget=budget,
        )
    print(f"  [+] Created Tender {tender_code} | {subject} | {tender_type} | budget ${budget:,.2f}")
    return tender_code, tender_type, budget


# ---------------------------------------------------------------------------
# Tender vetting (L1 -> L2 -> L3, with a chance of rejection at each level)
# ---------------------------------------------------------------------------

def vet_tender(driver: Driver, tender_code: str, budget: float, approver_levels: ApproverLevels) -> bool:
    """Runs the tender through its required approval chain. Returns True if
    the tender ends up Approved, False if it was Rejected along the way."""
    levels = required_levels_for(budget, approver_levels)

    with driver.session() as session:
        for i, level in enumerate(levels):
            approver = random.choice(approver_levels.approvers[level])
            is_last_required_level = (i == len(levels) - 1)

            if random.random() < REJECTION_CHANCE:
                session.run(
                    """
                    MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:IS_NEW_TENDER_STATE]->(t:Tender {TenderCode: $code}),
                          (l:Employee {Name: $approver})<-[:IS_ACTIVE_ROLE]-(:RolE {Name: $role}),
                          (rv:RejectedTenderS {Name: "RejectedTenderS"})
                    CREATE (t)-[:HAS_L%d_TENDER_REJECTION {Date: datetime(), Comment: "Auto-generated test rejection"}]->(l),
                           (rv)-[:IS_REJECTED_TENDER_STATE]->(t)
                    DELETE r1
                    """ % level,
                    code=tender_code, approver=approver, role=f"Level{level}Approver",
                )
                print(f"      L{level} approver {approver} REJECTED Tender {tender_code}")
                return False

            if is_last_required_level:
                session.run(
                    """
                    MATCH (nt:NewTenderS {Name: "NewTenderS"})-[r1:IS_NEW_TENDER_STATE]->(t:Tender {TenderCode: $code}),
                          (l:Employee {Name: $approver})<-[:IS_ACTIVE_ROLE]-(:RolE {Name: $role}),
                          (at:ApprovedTenderS {Name: "ApprovedTenderS"})
                    CREATE (t)-[:HAS_L%d_TENDER_APPROVAL {Date: datetime(), Comment: "Auto-generated test approval"}]->(l),
                           (at)-[:IS_APPROVED_TENDER_STATE]->(t)
                    DELETE r1
                    """ % level,
                    code=tender_code, approver=approver, role=f"Level{level}Approver",
                )
            else:
                session.run(
                    """
                    MATCH (t:Tender {TenderCode: $code}),
                          (l:Employee {Name: $approver})<-[:IS_ACTIVE_ROLE]-(:RolE {Name: $role})
                    CREATE (t)-[:HAS_L%d_TENDER_APPROVAL {Date: datetime(), Comment: "Auto-generated test approval"}]->(l)
                    """ % level,
                    code=tender_code, approver=approver, role=f"Level{level}Approver",
                )
            print(f"      L{level} approver {approver} approved Tender {tender_code}")

    print(f"  [\u2713] Tender {tender_code} fully APPROVED")
    return True


# ---------------------------------------------------------------------------
# Publishing + vendor invitations
# ---------------------------------------------------------------------------

def publish_and_invite(driver: Driver, tender_code: str, tender_type: str,
                        publishers: list[str], approved_vendor_codes: list[str]) -> list[str]:
    """Moves an Approved Tender to Published and invites Vendors according
    to its TenderType, mirroring the Open/Selective/Negotiated logic used
    throughout the original script's 'Publish Tender #N' blocks."""
    publisher = random.choice(publishers)

    if tender_type == "Open":
        invitees = approved_vendor_codes
    elif tender_type == "Selective":
        k = min(len(approved_vendor_codes), random.randint(2, 4))
        invitees = random.sample(approved_vendor_codes, k)
    else:  # Negotiated / Framework / DirectAward -> single vendor
        invitees = [random.choice(approved_vendor_codes)]

    with driver.session() as session:
        session.run(
            """
            MATCH (at:ApprovedTenderS {Name: "ApprovedTenderS"})-[r1:IS_APPROVED_TENDER_STATE]->(t:Tender {TenderCode: $code}),
                  (p:Employee {Name: $publisher})<-[:IS_ACTIVE_ROLE]-(:RolE {Name: "Publisher"}),
                  (pt:PublishedTenderS {Name: "PublishedTenderS"})
            CREATE (t)-[:HAS_PUBLISHER_TENDER_APPROVAL {Date: datetime(), Comment: "Auto-generated test publish"}]->(p),
                   (t)-[:HAS_INVITEES]->(iv:InvitedVendorS {Name: "InvitedVendorS"}),
                   (t)-[:HAS_TENDER_BIDS]->(:TenderBidS {Name: "TenderBidS"}),
                   (pt)-[:IS_PUBLISHED_TENDER_STATE]->(t)
            DELETE r1
            WITH iv
            UNWIND $invitees AS vendor_code
            MATCH (v:Vendor {VendorCode: vendor_code})
            CREATE (iv)-[:HAS_INVITATION {Date: datetime()}]->(v)
            """,
            code=tender_code, publisher=publisher, invitees=invitees,
        )
    print(f"  [+] Published {tender_code} by {publisher} | invited {len(invitees)} vendor(s)")
    return invitees


def vendors_accept_invitations(driver: Driver, tender_code: str, invited_codes: list[str]) -> list[str]:
    """Each invited Vendor randomly decides whether to accept."""
    accepted: list[str] = [c for c in invited_codes if random.random() < VENDOR_ACCEPT_CHANCE]
    if not accepted and invited_codes:
        accepted = [random.choice(invited_codes)]  # ensure at least one bidder where possible

    with driver.session() as session:
        for vendor_code in accepted:
            session.run(
                """
                MATCH (ti:AcceptedInvitationS {Name: "AcceptedInvitationS"})<-[:HAS_ACCEPTED_INVITATIONS]-(v:Vendor {VendorCode: $vendor_code})
                      <-[:HAS_INVITATION]-(:InvitedVendorS)<-[:HAS_INVITEES]-(t:Tender {TenderCode: $code})
                CREATE (ti)-[:HAS_ACCEPTED_TENDER_INVITATION {Date: datetime()}]->(t)
                """,
                vendor_code=vendor_code, code=tender_code,
            )
    print(f"  [+] {len(accepted)}/{len(invited_codes)} invited vendor(s) accepted for {tender_code}")
    return accepted


# ---------------------------------------------------------------------------
# Bid creation
# ---------------------------------------------------------------------------

def create_bids(driver: Driver, tender_code: str, budget: float, accepted_vendor_codes: list[str]) -> list[tuple[str, float]]:
    """Each Vendor that accepted submits one Bid, priced somewhere near the
    Tender's budget (a mix of under- and over-bidding)."""
    bids: list[tuple[str, float]] = []
    with driver.session() as session:
        for vendor_code in accepted_vendor_codes:
            bid_code = new_code("B")
            price = round(budget * random.uniform(0.75, 1.15), 2)
            completion_days = random.randint(30, 180)

            session.run(
                """
                MATCH (vb:ActiveBidS)<-[:HAS_ACTIVE_BIDS]-(v:Vendor {VendorCode: $vendor_code})
                      -[:HAS_ACCEPTED_INVITATIONS]->()-[:HAS_ACCEPTED_TENDER_INVITATION]->(t:Tender {TenderCode: $code})
                      -[:HAS_TENDER_BIDS]->(tb:TenderBidS {Name: "TenderBidS"})
                CREATE (vb)-[:HAS_ACTIVE_BID {Date: datetime()}]->
                       (b:Bid {
                            BidCode: $bid_code, Title: "Bid for " + $code + " from " + v.ShortName,
                            Description: "Auto-generated test bid",
                            Scope: "Auto-generated scope of work",
                            Deliverables: "Auto-generated deliverables list",
                            CompletionDate: datetime() + duration({days: $completion_days}),
                            Price: $price,
                            Conditions: "Standard terms and conditions",
                            Qualifications: v.ShortName + " qualifications on file",
                            SubmissionDate: datetime()
                       })<-[:HAS_TENDER_BID {Date: datetime()}]-(tb),
                       (b)-[:HAS_VENDOR]->(v),
                       (b)-[:HAS_TENDER]->(t),
                       (b)-[:HAS_BID_DOCS]->(:BidDocS {Name: "BidDocS"})
                            -[:HAS_BID_DOCUMENT]->(:BidDoc {
                                DocName: "BidDoc-" + $bid_code, Type: "PDF",
                                URL: "https://example.com/" + $bid_code + ".pdf",
                                Description: "Auto-generated test bid document"
                            }),
                       (b)-[:HAS_BID_CHAT]->(:ConversatioN {Name: "ConversatioN"})
                """,
                vendor_code=vendor_code, code=tender_code, bid_code=bid_code,
                price=price, completion_days=completion_days,
            )
            bids.append((bid_code, price))
            print(f"      Vendor {vendor_code} submitted Bid {bid_code} (${price:,.2f})")
    return bids


def assess_bids_with_ai_agent(driver: Driver, tender_code: str) -> None:
    """Attaches an AI Agent Bid Assessment node to every Bid on this Tender,
    matching the '--------- AI Agent Bid Assessment' block in the original
    script. Scoped to $code (rather than matching every Published Tender's
    Bids, as the original one-shot script does) so repeated calls across
    lifecycle iterations don't keep re-creating assessment nodes on Bids
    that were already assessed in an earlier iteration."""
    with driver.session() as session:
        session.run(
            """
            MATCH (:PublishedTenderS)-[:IS_PUBLISHED_TENDER_STATE]->(t:Tender {TenderCode: $code})
                  -[:HAS_TENDER_BIDS]->()-[:HAS_TENDER_BID]->(b)
            WITH b
            CREATE (b)-[:HAS_AI_AGENT_BID_ASSESSMENT {Date: datetime()}]->(:AIBidAssessment {
                Rating: rand(),
                AssessmentSummary: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Morbi ornare id justo ac varius. Aliquam in dui consequat, pulvinar lorem quis, rhoncus ipsum. Aenean mi dolor, dapibus ac urna eget, condimentum facilisis urna. Sed vulputate fermentum odio, ut mattis magna rhoncus sit amet. Morbi vestibulum tortor et diam placerat, et tristique mauris porta. Sed tellus diam, aliquam ac ullamcorper malesuada, iaculis nec sem. Mauris felis risus, fringilla in pellentesque a, porta eget arcu. Proin id leo eu tortor dapibus pellentesque at eget justo. Nunc quis euismod erat. Nullam non interdum nibh. Sed ipsum erat, feugiat quis mauris et, tempor laoreet nulla. Duis tincidunt dolor a tortor accumsan, vitae eleifend est efficitur. Suspendisse efficitur, justo non malesuada feugiat, leo enim tincidunt tortor, non tempor nunc magna at purus.",
                Advantages: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer blandit auctor sem, ut pharetra erat mollis id. Vestibulum eu mi venenatis, lacinia orci nec, laoreet diam. Maecenas auctor ac ante eu vestibulum. Sed vitae placerat ex, sed pharetra ex. Donec pharetra mi lacus. Etiam et dapibus erat, a mattis diam. Pellentesque rhoncus tellus ac sem pellentesque laoreet. Sed accumsan maximus odio sed molestie.",
                Disadvantages: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla bibendum elementum tristique. Fusce neque nisl, fermentum eget tellus elementum, semper consectetur dui. Morbi eros arcu, vehicula ac magna ut, lacinia ornare felis. Integer tincidunt mi vel dolor convallis pharetra. Cras viverra congue nisi et imperdiet. In posuere vehicula commodo. Ut viverra sapien arcu, vel maximus leo feugiat non."
            })
            """,
            code=tender_code,
        )
    print(f"  [+] AI Agent bid assessments created for Tender {tender_code}")


# ---------------------------------------------------------------------------
# Bid vetting: Tender Requester -> L1 -> L2 -> L3, then award
# ---------------------------------------------------------------------------

def vet_bid(driver: Driver, tender_code: str, bid_code: str, price: float,
            requester: str, approver_levels: ApproverLevels) -> bool:
    """Runs one Bid through requester + level approvals. Returns True if
    the bid ends fully approved (i.e. eligible for award)."""
    levels = required_levels_for(price, approver_levels)

    with driver.session() as session:
        session.run(
            """
            MATCH (:PublishedTenderS)-[:IS_PUBLISHED_TENDER_STATE]->(:Tender {TenderCode: $code})
                  <-[:HAS_TENDER]-(b:Bid {BidCode: $bid_code}),
                  (e:Employee {Name: $requester})<-[:IS_ACTIVE_ROLE]-(:RolE {Name: "Requester"})
            CREATE (b)-[:HAS_TENDER_REQUESTER_APPROVAL {Date: datetime(), Comment: "Auto-generated test approval"}]->(e)
            """,
            code=tender_code, bid_code=bid_code, requester=requester,
        )

        for level in levels:
            approver = random.choice(approver_levels.approvers[level])
            if random.random() < REJECTION_CHANCE:
                session.run(
                    """
                    MATCH (b:Bid {BidCode: $bid_code}),
                          (l:Employee {Name: $approver})<-[:IS_ACTIVE_ROLE]-(:RolE {Name: $role})
                    CREATE (b)-[:HAS_L%d_BID_REJECTION {Date: datetime(), Comment: "Auto-generated test rejection"}]->(l)
                    """ % level,
                    bid_code=bid_code, approver=approver, role=f"Level{level}Approver",
                )
                print(f"      L{level} approver {approver} REJECTED Bid {bid_code}")
                return False

            session.run(
                """
                MATCH (b:Bid {BidCode: $bid_code}),
                      (l:Employee {Name: $approver})<-[:IS_ACTIVE_ROLE]-(:RolE {Name: $role})
                CREATE (b)-[:HAS_L%d_BID_APPROVAL {Date: datetime(), Comment: "Auto-generated test approval"}]->(l)
                """ % level,
                bid_code=bid_code, approver=approver, role=f"Level{level}Approver",
            )
            print(f"      L{level} approver {approver} approved Bid {bid_code}")

    return True


def award_bid(driver: Driver, tender_code: str, winning_bid_code: str, all_bid_codes: list[str]) -> None:
    """Awards the winning Bid, moving the Tender to AwardedTenderS and every
    Bid's Vendor collection membership accordingly -- mirroring the
    'Christine will approve... move the Tender to the AwardedTenders
    Collection' block in the original script."""
    with driver.session() as session:
        session.run(
            """
            MATCH (:PublishedTenderS)-[r1:IS_PUBLISHED_TENDER_STATE]->(t:Tender {TenderCode: $code})
                  <-[:HAS_TENDER]-(b:Bid {BidCode: $bid_code})-[:HAS_VENDOR]->(v),
                  (aw:AwardedTenderS {Name: "AwardedTenderS"})
            CREATE (aw)-[:IS_AWARDED_TENDER_STATE]->(t),
                   (t)-[:HAS_AWARDED_VENDOR {Date: datetime()}]->(v),
                   (t)-[:HAS_AWARDED_BID {Date: datetime()}]->(b)
            DELETE r1
            """,
            code=tender_code, bid_code=winning_bid_code,
        )
        session.run(
            """
            MATCH (t:Tender {TenderCode: $code})<-[:HAS_TENDER]-(b:Bid {BidCode: $bid_code})
                  <-[r1:HAS_ACTIVE_BID]-(:ActiveBidS)<-[:HAS_ACTIVE_BIDS]-(v)-[:HAS_AWARDED_BIDS]->(ab)
            CREATE (ab)-[:HAS_AWARDED_TENDER_BID]->(b)
            DELETE r1
            """,
            code=tender_code, bid_code=winning_bid_code,
        )

        losing_codes = [c for c in all_bid_codes if c != winning_bid_code]
        for losing_code in losing_codes:
            session.run(
                """
                MATCH (t:Tender {TenderCode: $code})<-[:HAS_TENDER]-(b:Bid {BidCode: $bid_code})
                      <-[r1:HAS_ACTIVE_BID]-(ab:ActiveBidS)<-[:HAS_ACTIVE_BIDS]-(v)-[:HAS_PAST_BIDS]->(pb)
                CREATE (pb)-[:HAS_PAST_BID]->(b)
                DELETE r1
                WITH v, t
                MATCH (v)-[:HAS_ACCEPTED_INVITATIONS]->(:AcceptedInvitationS)-[r2:HAS_ACCEPTED_TENDER_INVITATION]->(t)
                DELETE r2
                """,
                code=tender_code, bid_code=losing_code,
            )

    print(f"  [\u2713] Bid {winning_bid_code} AWARDED for Tender {tender_code} "
          f"({len(losing_codes)} losing bid(s) archived)")


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def run_one_tender_lifecycle(driver: Driver, requesters: list[str], publishers: list[str],
                              approved_vendor_codes: list[str], approver_levels: ApproverLevels,
                              tender_type_names: list[str]) -> None:
    tender_code, tender_type, budget = create_random_tender(driver, requesters, tender_type_names)

    if not vet_tender(driver, tender_code, budget, approver_levels):
        return  # rejected -- lifecycle ends here, matching the original script's behavior

    invited = publish_and_invite(driver, tender_code, tender_type, publishers, approved_vendor_codes)
    accepted = vendors_accept_invitations(driver, tender_code, invited)
    if not accepted:
        print(f"  [!] No vendors accepted for {tender_code} -- no bids possible")
        return

    bids = create_bids(driver, tender_code, budget, accepted)

    assess_bids_with_ai_agent(driver, tender_code)

    requester = requesters[0]  # the Tender's own requester approves first, as in the original script
    approved_bids = []
    for bid_code, price in bids:
        if vet_bid(driver, tender_code, bid_code, price, requester, approver_levels):
            approved_bids.append((bid_code, price))

    if not approved_bids:
        print(f"  [!] No bids approved for {tender_code} -- Tender remains unawarded")
        return

    winning_bid_code, _ = min(approved_bids, key=lambda b: b[1])  # lowest approved price wins
    award_bid(driver, tender_code, winning_bid_code, [c for c, _ in bids])


def main() -> None:
    parser = argparse.ArgumentParser(description="Randomly exercise the Tender Workflow graph.")
    parser.add_argument("--tenders", type=int, default=10, help="Number of Tenders to generate")
    parser.add_argument("--seed", type=int, default=None, help="Random seed for reproducibility")
    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    uri = os.environ.get("NEO4J_URI", "neo4j://localhost:7687")
    user = os.environ.get("NEO4J_USER", "neo4j")
    password = os.environ.get("NEO4J_PASSWORD")
    if not password:
        raise SystemExit("Set the NEO4J_PASSWORD environment variable before running.")

    driver = GraphDatabase.driver(uri, auth=(user, password))
    try:
        driver.verify_connectivity()
        employees_by_role, approved_vendor_codes, approver_levels, tender_type_names = fetch_reference_data(driver)
        requesters = employees_by_role["Requester"]
        publishers = employees_by_role["Publisher"]

        print(f"Loaded {len(requesters)} requester(s), {len(publishers)} publisher(s), "
              f"{len(approved_vendor_codes)} approved vendor(s), {len(tender_type_names)} tender type(s)\n")

        for i in range(1, args.tenders + 1):
            print(f"--- Tender lifecycle {i}/{args.tenders} ---")
            try:
                run_one_tender_lifecycle(
                    driver, requesters, publishers, approved_vendor_codes,
                    approver_levels, tender_type_names,
                )
            except Exception as exc:  # keep the run going even if one lifecycle fails
                print(f"  [ERROR] lifecycle {i} failed: {exc}")
            print()
    finally:
        driver.close()


if __name__ == "__main__":
    main()