// This Cypher script v1 uses Neo4j new GRAPH TYPE to defines a Graph Govenance template for the Tender the TenderWorkflow v7.1 Schema. 
// It defines the Graph Type, its Nodes, Relationships, and Constraints to ensure data integrity and enforce business rules.

ALTER CURRENT GRAPH TYPE SET {

// *******   Entity - GRAPH TYPE Definitions   *******

// AcceptedInvitationS
// Define AcceptedInvitationS supertype with its properties and a unique Name key.
(:AcceptedInvitationS => {    
    Name :: STRING NOT NULL
     }),

// ActiveBidS
// Define ActiveBidS supertype with its properties and a unique Name key.
(:ActiveBidS => {
    Name :: STRING NOT NULL
     }),

// AIBidAssessment
// Define AIBidAssessment with its properties and a unique Name key.
(:AIBidAssessment => {   
    Advantages :: STRING NOT NULL,
    Disadvantages :: STRING NOT NULL,
    AssessmentSummary :: STRING NOT NULL,
    Rating :: FLOAT NOT NULL
     }),

// AIVendorAssessment
// Define AIVendorAssessment with its properties and a unique Name key.
(a:AIVendorAssessment => {   
    Advantages :: STRING NOT NULL,
    Disadvantages :: STRING NOT NULL,
    AssessmentSummary :: STRING NOT NULL,
    Rating :: FLOAT NOT NULL
     }),

// ApprovedTenderS
// Define ApprovedTenderS subtypes node with a unique Name property and key.
(t:ApprovedTenderS => {
    Name :: STRING NOT NULL
     }) REQUIRE (t.Name) IS UNIQUE,

// ApprovedVendorS
// Define ApprovedVendorS subtype with its properties and a unique Name key.
(v: ApprovedVendorS => {
    Name :: STRING NOT NULL
     }) REQUIRE (v.Name) IS UNIQUE,  

// AwardedBidS
// Define AwardedBidS supertype with its properties and a unique Name key.
(:AwardedBidS => {
    Name :: STRING NOT NULL
     }),

// AwardedTenderS
// Define AwardedTenderS subtypes with a unique Name property and key.
(t1:AwardedTenderS => {
    Name :: STRING NOT NULL
     }) REQUIRE (t1.Name) IS UNIQUE,

// Bid
// Define Bid and its properties with a unique BidCode key.
(b:Bid => {
    BidCode :: STRING NOT NULL,
    Description :: STRING NOT NULL,
    CompletionDate :: TIMESTAMP WITH TIME ZONE,
    Conditions :: STRING NOT NULL,
    Deliverables :: STRING NOT NULL,
    Price :: FLOAT NOT NULL,
    Qualifications :: STRING NOT NULL,
    Scope :: STRING NOT NULL,
    Title :: STRING NOT NULL
     }) REQUIRE (b.BidCode) IS KEY,

// BidDoc
// Define BidDoc and its properties with a unique DocName key.
(:BidDoc => {
    DocName :: STRING NOT NULL,
    Description :: STRING NOT NULL,
    Type :: STRING NOT NULL,
    Date :: TIMESTAMP WITH TIME ZONE,
    URL :: STRING NOT NULL
     }),

// BidDocS
// Define BidDocS supertype with its properties and a unique Name key.
(:BidDocS => {
    Name :: STRING NOT NULL
     }),  

// ClosedTenderS
// Define ClosedTenderS subtypes with a unique Name property and key.
(t2:ClosedTenderS => {
    Name :: STRING NOT NULL
     }) REQUIRE (t2.Name) IS UNIQUE,

// Conversation
// Define Conversation supertype and its properties with a unique ID key. 
(:ConversatioN => {
      Name :: STRING NOT NULL
         }),

// Employee
// Define Employee and its properties with a unique ID key.
(e:Employee => {
    Name :: STRING NOT NULL,
    ID :: STRING NOT NULL,
    Phone :: STRING,
    Email :: STRING NOT NULL,
    Photo :: STRING 
         }) REQUIRE (e.ID) IS KEY,

// EmployeeDirectorY
// Define EmployeeDirectorY and its Name property with a unique Name key.
(ey:EmployeeDirectorY => {
    Name :: STRING NOT NULL
     }) REQUIRE (ey.Name) IS UNIQUE,

// InvitedVendorS
// Define InvitedVendorS subtype with its properties and a unique Name key.
(:InvitedVendorS => {
    Name :: STRING NOT NULL
     }),

// Message
// Define Message and its properties with a unique ID key.
(:Message => { 
    Text :: STRING NOT NULL
         }),

// NewTenderS
// Define NewTenderS subtypes node with a unique Name property and key.
(t3:NewTenderS => {
    Name :: STRING NOT NULL
     }) REQUIRE (t3.Name) IS UNIQUE,

// PastBidS
// Define PastBidS supertype with its properties and a unique Name key.
(:PastBidS => {
    Name :: STRING NOT NULL
     }),

// PendingVendorS
// Define PendingVendorS subtype with its properties and a unique Name key.
(pv:PendingVendorS => {
    Name :: STRING NOT NULL
     }) REQUIRE (pv.Name) IS UNIQUE,

// PublishedTenderS
// Define PublishedTenderS subtypes with a unique Name property and key.
(pt:PublishedTenderS => {
    Name :: STRING NOT NULL
     }) REQUIRE (pt.Name) IS UNIQUE,

// RejectedTenderS
// Define RejectedTenderS subtypes node with a unique Name property and key.
(rt:RejectedTenderS => {
    Name :: STRING NOT NULL
     }) REQUIRE (rt.Name) IS UNIQUE,

// RejectedVendorS
// Define RejectedVendorS subtype with its properties and a unique Name key.
(rv:RejectedVendorS => {
    Name :: STRING NOT NULL
     }) REQUIRE (rv.Name) IS UNIQUE,

// RolE
// Define RolE subtype and its Name property with a unique Name key.
(ro:RolE => {
    Name :: STRING NOT NULL
     }) REQUIRE (ro.Name) IS UNIQUE,

// RoleS
// Define RoleS supertype and its Name property with a unique Name key.
(rs:RoleS => {
    Name :: STRING NOT NULL
     }) REQUIRE (rs.Name) IS UNIQUE,

// Tender
// Define Tender and its properties with a unique TenderCode key.
(t4:Tender => {  
    TenderCode :: STRING NOT NULL,
    Title :: STRING NOT NULL,
    Description :: STRING NOT NULL,
    SubmissionDate :: TIMESTAMP WITH TIME ZONE,
    EndBidingDate :: TIMESTAMP WITH TIME ZONE,
    Budget :: FLOAT NOT NULL
     }) REQUIRE (t4.TenderCode) IS KEY,

// TenderBidS
// Define TenderBidS supertype with its properties and a unique Name key.
(:TenderBidS => {
    Name :: STRING NOT NULL
     }),

// TenderDoc
// Define TenderDoc and its properties with a unique DocName key.
(:TenderDoc => {
    DocName :: STRING NOT NULL,
    Description :: STRING NOT NULL,
    Type :: STRING NOT NULL,
    Date :: TIMESTAMP WITH TIME ZONE,
    URL :: STRING NOT NULL
     }),

// TenderDocS
// Define TenderDocS supertype with its properties and a unique Name key.
(:TenderDocS => {
    Name :: STRING NOT NULL
     }),

// TenderS
// Define the TenderS supertype node with a unique Name property and key.
(t5:TenderS => {
    Name :: STRING NOT NULL
     }) REQUIRE (t5.Name) IS UNIQUE,

// TenderType
// Define TenderType and its Name property with a unique Name key.
(t6:TenderType => {
    Name :: STRING NOT NULL
     }) REQUIRE (t6.Name) IS UNIQUE,

// TenderTypeS
// Define TenderTypeS supertype and its Name property with a unique Name key.
(t7:TenderTypeS => {
    Name :: STRING NOT NULL
     }) REQUIRE (t7.Name) IS UNIQUE,

// Vendor
// Define the Vendor with its properties and a unique VendorCode key.
(v2:Vendor => {
    VendorCode :: STRING NOT NULL,
    ShortName :: STRING NOT NULL,
    LegalName :: STRING NOT NULL,
    RegistrartionNumber :: STRING NOT NULL,
    Logo :: STRING 
     }) REQUIRE (v2.VendorCode) IS KEY,    

// VendorContact
// Define the VendorContact with its properties and a unique Email key.
(:VendorContact => {
    Name :: STRING NOT NULL,
    Phone :: STRING NOT NULL,
    Email :: STRING NOT NULL,
    Photo :: STRING 
     }),

// VendorDoc
// Define the VendorDoc with its properties and a unique Name key.
(:VendorDoc => {
    DocName :: STRING NOT NULL,
    Description :: STRING NOT NULL,
    Type :: STRING NOT NULL,
    Date :: TIMESTAMP WITH TIME ZONE,
    URL :: STRING NOT NULL
     }),

// VendorDocS
// Define the VendorDocS supertype with its properties and a unique Name key.
(:VendorDocS => {
   Name :: STRING NOT NULL
     }),

// VendorS
// Define VendorS supertype with its properties and a unique Name key.
(v3:VendorS => {
    Name :: STRING NOT NULL
     }) REQUIRE (v3.Name) IS UNIQUE,

// ******* Relationships - GRAPH TYPE Definitions *******

// Define the EmployeeDirectorY relationship.
  (:EmployeeDirectorY)-[:HAS_ACTIVE_EMPLOYEE => {StartDate :: TIMESTAMP WITH TIME ZONE NOT NULL, EndDate :: TIMESTAMP WITH TIME ZONE}]->(:Employee),

// Define the RoleS relationship.
  (:RoleS)-[:HAS_ROLE_TYPE => {}]->(:RolE),

// Define the RolE relationship.
  (:RolE)-[:IS_ACTIVE_ROLE => {StartDate :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Employee),
  (:RolE)-[:WAS_PAST_ROLE => {StartDate :: TIMESTAMP WITH TIME ZONE NOT NULL, EndDate :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Employee),

// Define the VendorS relationship.
  (:VendorS)-[:HAS_VENDOR_PENDING_STATE => {}]->(:PendingVendorS),
  (:VendorS)-[:HAS_VENDOR_APPROVED_STATE => {}]->(:ApprovedVendorS), 
  (:VendorS)-[:HAS_VENDOR_REJECTED_STATE => {}]->(:RejectedVendorS),

// Define the Vendor subtypes relationships with Vendor 
  (:PendingVendorS)-[:IS_VENDOR_PENDING_STATE => {}]->(:Vendor),
  (:ApprovedVendorS)-[:IS_VENDOR_APPROVED_STATE => {}]->(:Vendor),
  (:RejectedVendorS)-[:IS_VENDOR_REJECTED_STATE => {}]->(:Vendor),

// Define the Generic Conversation relationship (used by Tender, Bid, and Vendor).
  (:ConversatioN)-[:HAS_MESSAGE => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Message),

// Define Message relationships.
  (:Message)-[:SENT_BY => {}]->(),

// Define the Vendor relationship.
  (:Vendor)-[:HAS_CONTACT => {}]->(:VendorContact),
  (:Vendor)-[:HAS_VENDOR_CHAT => {}]->(:ConversatioN),
  (:Vendor)-[:HAS_VENDOR_DOCS => {}]->(:VendorDocS),   
  (:VendorDocS)-[:HAS_VENDOR_DOCUMENT => {}]->(:VendorDoc),
  (:Vendor)-[:HAS_ACTIVE_BIDS => {}]->(:ActiveBidS),
    (:ActiveBidS)-[:HAS_ACTIVE_BID => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Bid),
  (:Vendor)-[:HAS_PAST_BIDS => {}]->(:PastBidS),
    (:PastBidS)-[:HAS_PAST_BID => {}]->(:Bid),
  (:Vendor)-[:HAS_AWARDED_BIDS => {}]->(:AwardedBidS),
    (:AwardedBidS)-[:HAS_AWARDED_TENDER_BID => {}]->(:Bid),
  (:Vendor)-[:HAS_ACCEPTED_INVITATIONS => {}]->(:AcceptedInvitationS),
    (:AcceptedInvitationS)-[:HAS_ACCEPTED_TENDER_INVITATION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Tender),
  (:Vendor)-[:HAS_L1_VENDOR_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL , Comment :: STRING NOT NULL }]->(:Employee),
  (:Vendor)-[:HAS_L1_VENDOR_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL , Comment :: STRING NOT NULL }]->(:Employee),
  (:Vendor)-[:HAS_AI_AGENT_VENDOR_ASSESSMENT => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:AIVendorAssessment),
 
// Define the TenderTypeS relationship.
  (:TenderTypeS)-[:HAS_TENDER_TYPE => {}]->(:TenderType),

// Define the TenderS relationship to its subtypes.
  (:TenderS)-[:HAS_NEW_TENDER_STATE => {}]->(:NewTenderS),
  (:TenderS)-[:HAS_APPROVED_TENDER_STATE => {}]->(:ApprovedTenderS),
  (:TenderS)-[:HAS_REJECTED_TENDER_STATE => {}]->(:RejectedTenderS),
  (:TenderS)-[:HAS_PUBLISHED_TENDER_STATE => {}]->(:PublishedTenderS),
  (:TenderS)-[:HAS_CLOSED_TENDER_STATE => {}]->(:ClosedTenderS),
  (:TenderS)-[:HAS_AWARDED_TENDER_STATE => {}]->(:AwardedTenderS), 

// Define the Tender subtypes relationships with Tender 
  (:NewTenderS)-[:IS_NEW_TENDER_STATE => {}]->(:Tender),
  (:ApprovedTenderS)-[:IS_APPROVED_TENDER_STATE => {}]->(:Tender),
  (:RejectedTenderS)-[:IS_REJECTED_TENDER_STATE => {}]->(:Tender),
  (:PublishedTenderS)-[:IS_PUBLISHED_TENDER_STATE => {}]->(:Tender),
  (:ClosedTenderS)-[:IS_CLOSED_TENDER_STATE => {}]->(:Tender),
  (:AwardedTenderS)-[:IS_AWARDED_TENDER_STATE => {}]->(:Tender),

// Define the Tender relationship.
  (:Tender)-[:IS_TENDER_TYPE => {}]->(:TenderType),
  (:Tender)-[:HAS_PREVIOUS_VERSION => {}]->(:Tender),
  (:Tender)-[:HAS_REQUESTER => {}]->(:Employee),
  (:Tender)-[:HAS_TENDER_CHAT => {}]->(:ConversatioN),
  (:Tender)-[:HAS_L1_TENDER_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Tender)-[:HAS_L2_TENDER_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL , Comment :: STRING NOT NULL }]->(:Employee),
  (:Tender)-[:HAS_L3_TENDER_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Tender)-[:HAS_PUBLISHER_TENDER_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Tender)-[:HAS_L1_TENDER_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Tender)-[:HAS_L2_TENDER_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Tender)-[:HAS_L3_TENDER_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Tender)-[:HAS_PUBLISHER_TENDER_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Tender)-[:HAS_TENDER_BIDS => {}]->(:TenderBidS),
    (:TenderBidS)-[:HAS_TENDER_BID => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Bid),
  (:Tender)-[:HAS_AWARDED_BID => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Bid),
  (:Tender)-[:HAS_AWARDED_VENDOR => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Vendor),
  (:Tender)-[:HAS_INVITEES => {}]->(:InvitedVendorS),
    (:InvitedVendorS)-[:HAS_INVITATION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:Vendor),
  (:Tender)-[:HAS_TENDER_DOCS => {}]->(:TenderDocS),
    (:TenderDocS)-[:HAS_TENDER_DOCUMENT => {}]->(:TenderDoc),

// Define Bid relationships.
  (:Bid)-[:HAS_BID_DOCS => {}]->(:BidDocS),
    (:BidDocS)-[:HAS_BID_DOCUMENT => {}]->(:BidDoc),
  (:Bid)-[:HAS_BID_CHAT => {}]->(:ConversatioN),
  (:Bid)-[:HAS_TENDER_REQUESTER_BID_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Bid)-[:HAS_TENDER_REQUESTER_BID_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Bid)-[:HAS_L1_BID_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Bid)-[:HAS_L2_BID_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Bid)-[:HAS_L3_BID_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Bid)-[:HAS_PUBLISHER_BID_APPROVAL => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Bid)-[:HAS_L1_BID_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Bid)-[:HAS_L2_BID_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Bid)-[:HAS_L3_BID_REJECTION => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL, Comment :: STRING NOT NULL}]->(:Employee),
  (:Bid)-[:HAS_AI_AGENT_BID_ASSESSMENT => {Date :: TIMESTAMP WITH TIME ZONE NOT NULL}]->(:AIBidAssessment),
  (:Bid)-[:HAS_VENDOR => {}]->(:Vendor),
  (:Bid)-[:HAS_TENDER => {}]->(:Tender)


}



