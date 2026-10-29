# Quine ingest graph analysis

Ingests analyzed: `customer-order`, `order-fulfillment`, `po-creation`, `rfq-submission`, `rfq-resubmission`, `rfq-fulfillment`, `threshold-recalibration`

Standing queries: `nw-po-vetting-l1` [DistinctId], `nw-po-vetting-l2` [DistinctId], `nw-po-vetting-l3` [DistinctId], `nw-low-stock-after-reject` [DistinctId], `nw-buyer-submission` [DistinctId], `nw-rfq-vetting` [DistinctId], `nw-rfq-approved-on-order` [DistinctId], `nw-finance-closure` [DistinctId], `nw-low-stock-on-new-order` [DistinctId], `nw-log-po-created` [DistinctId], `nw-log-shipped` [DistinctId]

## Node types

| node type | labels | cardinality | supernode risk | deleted? | layers |
|---|---|---|---|---|---|
| Customer |  | high | none |  | ingest, sq |
| Employee |  | high | none |  | ingest, sq |
| FinancePayment |  | high | none |  | sq |
| InventoryLevel |  | high | none |  | ingest, sq |
| Order |  | high | none |  | ingest, sq |
| OrderItem |  | high | none |  | ingest, sq |
| POItem |  | high | none |  | ingest, sq |
| PoNewRFQ |  | high | none |  | sq |
| Product |  | high | none |  | ingest, sq |
| PurchaseOrder |  | high | none |  | ingest, sq |
| RFQ |  | high | none |  | ingest, sq |
| RFQItem |  | high | none |  | ingest, sq |
| ReorderLevel |  | high | none |  | ingest, sq |
| ResubmissionNote |  | high | none |  | ingest |
| ShipInfo |  | high | none |  | ingest |
| Shipper |  | high | none |  | ingest |
| Supplier |  | high | none |  | ingest, sq |
| SupplierOpenPoS |  | high | none |  | sq |
| VettingDecision |  | high | none |  | sq |
| WarehouseDelivery |  | high | none |  | ingest, sq |
| WarehouseFulfillment |  | high | none |  | ingest, sq |
| ApprovedPoS |  | singleton | high |  | sq |
| ApprovedSupplierS |  | singleton | none |  | ingest, sq |
| CustomerS |  | singleton | none |  | ingest |
| LowStocK |  | singleton | high |  | ingest, sq |
| NewPoS |  | singleton | high |  | ingest, sq |
| OrderStatusFulfilleD |  | singleton | high |  | ingest, sq |
| OrderStatusOpeN |  | singleton | high |  | ingest, sq |
| PoS |  | singleton | none |  | sq |
| ProductStatusAvailablE |  | singleton | none |  | ingest, sq |
| RejectedPoS |  | singleton | high |  | ingest, sq |
| RolE |  | singleton | none |  | ingest, sq |
| ShipperS |  | singleton | none |  | ingest |
| Simulation |  | singleton | none |  | ingest, sq |
| SubmittedPoS |  | singleton | high |  | ingest, sq |

## Relationships

| from | relationship | to | created by | notes |
|---|---|---|---|---|
| WarehouseFulfillment | :FULFILLED_BY | Employee | order-fulfillment |  |
| PurchaseOrder | :HAS_APPROVED_RFQ | RFQ | SQ nw-rfq-vetting › act |  |
| PurchaseOrder | :HAS_BUYER_PO_APPROVAL | VettingDecision | SQ nw-buyer-submission › act | standing-query layer |
| RFQ | :HAS_BUYER_RFQ_APPROVAL | VettingDecision | SQ nw-rfq-vetting › act | standing-query layer |
| RFQ | :HAS_BUYER_RFQ_REJECTION | VettingDecision | SQ nw-rfq-vetting › act | standing-query layer |
| PurchaseOrder | :HAS_FINANCE_PAYMENT | FinancePayment | SQ nw-finance-closure › act | standing-query layer |
| Product | :HAS_INVENTORY_LEVEL | InventoryLevel |  | matched only, never created |
| PurchaseOrder | :HAS_L1_PO_APPROVAL | VettingDecision | SQ nw-po-vetting-l1 › act | standing-query layer |
| PurchaseOrder | :HAS_L1_PO_REJECTION | VettingDecision | SQ nw-po-vetting-l1 › act | standing-query layer |
| PurchaseOrder | :HAS_L2_PO_APPROVAL | VettingDecision | SQ nw-po-vetting-l2 › act | standing-query layer |
| PurchaseOrder | :HAS_L2_PO_REJECTION | VettingDecision | SQ nw-po-vetting-l2 › act | standing-query layer |
| PurchaseOrder | :HAS_L3_PO_APPROVAL | VettingDecision | SQ nw-po-vetting-l3 › act | standing-query layer |
| PurchaseOrder | :HAS_L3_PO_REJECTION | VettingDecision | SQ nw-po-vetting-l3 › act | standing-query layer |
| Order | :HAS_ORDER_CUSTOMER | Customer | customer-order |  |
| Order | :HAS_ORDER_ITEM | OrderItem | customer-order |  |
| PurchaseOrder | :HAS_PO_ITEM | POItem | po-creation |  |
| PurchaseOrder | :HAS_PREVIOUS_PO | PurchaseOrder | po-creation |  |
| RFQ | :HAS_PREVIOUS_RFQ | RFQ | rfq-resubmission |  |
| Product | :HAS_REORDER_LEVEL | ReorderLevel |  | matched only, never created |
| PurchaseOrder | :HAS_RESUBMISSION_NOTE | ResubmissionNote | po-creation |  |
| RFQ | :HAS_RESUBMISSION_NOTE | ResubmissionNote | rfq-resubmission |  |
| RFQ | :HAS_RFQ_ITEM | RFQItem | rfq-submission, rfq-resubmission |  |
| Order | :HAS_SHIPMENT_INFO | ShipInfo | order-fulfillment |  |
| ShipInfo | :HAS_SHIPPER | Shipper | order-fulfillment |  |
| PoS | :HAS_SUBMITTED_PO_STATE | SubmittedPoS |  | matched only, never created; standing-query layer |
| PurchaseOrder | :HAS_SUPPLIER_NEW_RFQ | PoNewRFQ |  | traversed only between these node types (created between others); standing-query layer |
| PurchaseOrder | :HAS_SUPPLIER_NEW_RFQ | VettingDecision | SQ nw-buyer-submission › act | standing-query layer |
| Supplier | :HAS_SUPPLIER_OPEN_POS | SupplierOpenPoS |  | matched only, never created; standing-query layer |
| PurchaseOrder | :HAS_SUPPLIER_REJECTED_RFQ | VettingDecision | SQ nw-buyer-submission › act | standing-query layer |
| PurchaseOrder | :HAS_WAREHOUSE_DELIVERY | WarehouseDelivery | rfq-fulfillment |  |
| Order | :HAS_WAREHOUSE_FULFILLMENT | WarehouseFulfillment | order-fulfillment |  |
| RolE | :IS_ACTIVE_ROLE | Employee |  | matched only, never created |
| ApprovedPoS | :IS_APPROVED_PO_STATE | PurchaseOrder | SQ nw-po-vetting-l1 › act, SQ nw-po-vetting-l2 › act, SQ nw-po-vetting-l3 › act | deleted on some events; standing-query layer; risk: high |
| ProductStatusAvailablE | :IS_AVAILABLE_PRODUCT | Product |  | matched only, never created |
| CustomerS | :IS_CUSTOMER | Customer |  | matched only, never created |
| OrderStatusFulfilleD | :IS_FULFILLED_ORDER_STATE | Order | order-fulfillment | risk: high |
| LowStocK | :IS_LOW_STOCK_PRODUCT | Product | threshold-recalibration, SQ nw-low-stock-after-reject › act, SQ nw-low-stock-on-new-order › act | risk: high |
| NewPoS | :IS_NEW_PO_STATE | PurchaseOrder | po-creation | risk: high |
| OrderStatusOpeN | :IS_OPEN_ORDER_STATE | Order | customer-order | deleted on some events; risk: high |
| RejectedPoS | :IS_REJECTED_PO_STATE | PurchaseOrder | SQ nw-po-vetting-l1 › act, SQ nw-po-vetting-l2 › act, SQ nw-po-vetting-l3 › act | risk: high |
| RFQ | :IS_RFQ_FOR_PO | PurchaseOrder | rfq-submission, rfq-resubmission |  |
| ShipperS | :IS_SHIPPER | Shipper |  | matched only, never created |
| SubmittedPoS | :IS_SUBMITTED_PO_STATE | PurchaseOrder | SQ nw-buyer-submission › act | deleted on some events; risk: high |
| ApprovedSupplierS | :IS_SUPPLIER_APPROVED_STATE | Supplier |  | matched only, never created |
| PoNewRFQ | :IS_SUPPLIER_NEW_RFQ | RFQ |  | matched only, never created; standing-query layer |
| SupplierOpenPoS | :IS_SUPPLIER_OPEN_PO_STATE | PurchaseOrder |  | matched only, never created; deleted on some events; standing-query layer |
| VettingDecision | :IS_SUPPLIER_REJECTED_RFQ_STATE | RFQ | SQ nw-rfq-vetting › act | standing-query layer |
| OrderItem | :ORDER_ITEM_PRODUCT | Product | customer-order |  |
| FinancePayment | :PAID_BY | Employee | SQ nw-finance-closure › act | standing-query layer |
| PurchaseOrder | :PO_CREATED_BY | Employee | po-creation |  |
| PurchaseOrder | :PO_FOR_SUPPLIER | Supplier | po-creation |  |
| POItem | :PO_ITEM_PRODUCT | Product | po-creation |  |
| WarehouseDelivery | :RECEIVED_BY | Employee | rfq-fulfillment |  |
| RFQ | :RFQ_FROM_SUPPLIER | Supplier | rfq-submission, rfq-resubmission |  |
| RFQItem | :RFQ_ITEM_PRODUCT | Product | rfq-submission, rfq-resubmission |  |
| Order | :SOLD_BY | Employee | customer-order |  |
| Supplier | :SUPPLIES | Product |  | matched only, never created |
| VettingDecision | :VETTED_BY | Employee | SQ nw-po-vetting-l1 › act, SQ nw-po-vetting-l2 › act, SQ nw-po-vetting-l3 › act, SQ nw-buyer-submission › act, SQ nw-rfq-vetting › act | standing-query layer |

## Cross-stream join keys

- **RolE**
  - `idFrom('RolE', 'Sales Representative')` in customer-order
  - `idFrom('RolE', 'WarehouseClerk')` in order-fulfillment
  - `idFrom('RolE', 'Procurement Assistant')` in po-creation
  - `idFrom('RolE', 'Level1Approver')` in SQ nw-po-vetting-l1 › act
  - `idFrom('RolE', 'Level2Approver')` in SQ nw-po-vetting-l2 › act
  - `idFrom('RolE', 'Level3Approver')` in SQ nw-po-vetting-l3 › act
  - `idFrom('RolE', 'Buyer')` in SQ nw-buyer-submission › act
  - `idFrom('RolE', 'Finance')` in SQ nw-finance-closure › act

## Findings

### WARN: CREATE node with inline properties
*customer-order:10*

In Quine, `CREATE (o {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties
*customer-order:16*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: Property condition on id-anchored node
*customer-order:2*

`sim.Ready = true` filters node `sim` by a property. Ingests run in parallel: if the property is not yet set (or set differently), the MATCH silently drops the record for the rest of this step.

### WARN: CREATE node with inline properties
*order-fulfillment:19*

In Quine, `CREATE (i {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties
*order-fulfillment:22*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: Edge endpoint could not be resolved
*order-fulfillment:21*

CREATE (i)-[:HAS_SHIPMENT_ADDRESS]->(a): one endpoint has no idFrom anchor or label in scope; the tool cannot tell which node it is.

### WARN: Property condition on id-anchored node
*order-fulfillment:2*

`sim.Ready = true` filters node `sim` by a property. Ingests run in parallel: if the property is not yet set (or set differently), the MATCH silently drops the record for the rest of this step.

### WARN: CREATE node with inline properties
*po-creation:25*

In Quine, `CREATE (po {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties
*po-creation:30*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties
*po-creation:34*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: Property condition on id-anchored node
*po-creation:2*

`sim.Ready = true` filters node `sim` by a property. Ingests run in parallel: if the property is not yet set (or set differently), the MATCH silently drops the record for the rest of this step.

### WARN: CREATE node with inline properties
*rfq-submission:10*

In Quine, `CREATE (rfq {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties
*rfq-submission:17*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: Edge endpoint could not be resolved
*rfq-submission:12*

CREATE (sop)-[:IS_SUPPLIER_OPEN_PO_STATE]->(po): one endpoint has no idFrom anchor or label in scope; the tool cannot tell which node it is.

### WARN: Edge endpoint could not be resolved
*rfq-submission:19*

CREATE (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq): one endpoint has no idFrom anchor or label in scope; the tool cannot tell which node it is.

### WARN: Property condition on id-anchored node
*rfq-submission:2*

`sim.Ready = true` filters node `sim` by a property. Ingests run in parallel: if the property is not yet set (or set differently), the MATCH silently drops the record for the rest of this step.

### WARN: CREATE node with inline properties
*rfq-resubmission:11*

In Quine, `CREATE (rfq {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties
*rfq-resubmission:15*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties
*rfq-resubmission:19*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: Edge endpoint could not be resolved
*rfq-resubmission:21*

CREATE (snr)-[:IS_SUPPLIER_NEW_RFQ]->(rfq): one endpoint has no idFrom anchor or label in scope; the tool cannot tell which node it is.

### WARN: Property condition on id-anchored node
*rfq-resubmission:2*

`sim.Ready = true` filters node `sim` by a property. Ingests run in parallel: if the property is not yet set (or set differently), the MATCH silently drops the record for the rest of this step.

### WARN: CREATE node with inline properties
*rfq-fulfillment:13*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: Property condition on id-anchored node
*rfq-fulfillment:2*

`sim.Ready = true` filters node `sim` by a property. Ingests run in parallel: if the property is not yet set (or set differently), the MATCH silently drops the record for the rest of this step.

### WARN: Property condition on id-anchored node
*threshold-recalibration:2*

`sim.Ready = true` filters node `sim` by a property. Ingests run in parallel: if the property is not yet set (or set differently), the MATCH silently drops the record for the rest of this step.

### WARN: CREATE node with inline properties [standing query]
*SQ nw-po-vetting-l1 › act:20*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-po-vetting-l1 › act:24*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-po-vetting-l1 › act:27*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-po-vetting-l2 › act:20*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-po-vetting-l2 › act:24*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-po-vetting-l2 › act:27*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-po-vetting-l3 › act:19*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-po-vetting-l3 › act:23*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-buyer-submission › act:8*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-buyer-submission › act:9*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-buyer-submission › act:10*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: Edge endpoint could not be resolved [standing query]
*SQ nw-buyer-submission › act:14*

CREATE (snp)-[:IS_SUPPLIER_NEW_PO_STATE]->(po): one endpoint has no idFrom anchor or label in scope; the tool cannot tell which node it is.

### WARN: CREATE node with inline properties [standing query]
*SQ nw-rfq-vetting › act:18*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-rfq-vetting › act:22*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: CREATE node with inline properties [standing query]
*SQ nw-finance-closure › act:9*

In Quine, `CREATE ( {…})` addresses a node at a generated ID rather than an idFrom-derived one. Usually you want MATCH … WHERE id(n) = idFrom(…) SET …

### WARN: Edge endpoint could not be resolved [standing query]
*SQ nw-finance-closure › act:10*

CREATE (cpo)-[:IS_CLOSED_PO_STATE]->(po): one endpoint has no idFrom anchor or label in scope; the tool cannot tell which node it is.

### WARN: Edge endpoint could not be resolved [standing query]
*SQ nw-finance-closure › act:11*

CREATE (scp)-[:HAS_SUPPLIER_CLOSED_PO_STATE]->(po): one endpoint has no idFrom anchor or label in scope; the tool cannot tell which node it is.

### WARN: Property condition on id-anchored node [standing query]
*SQ nw-low-stock-on-new-order › act:2*

`sim.Ready = true` filters node `sim` by a property. Ingests run in parallel: if the property is not yet set (or set differently), the MATCH silently drops the record for the rest of this step.

### WARN: Label `Employee` is matched but never SET
*customer-order:6*

Some query filters on `:Employee` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `Customer` is matched but never SET
*customer-order:8*

Some query filters on `:Customer` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `Product` is matched but never SET
*customer-order:14*

Some query filters on `:Product` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `Shipper` is matched but never SET
*order-fulfillment:6*

Some query filters on `:Shipper` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `ShipInfo` is matched but never SET
*order-fulfillment:6*

Some query filters on `:ShipInfo` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `Order` is matched but never SET
*order-fulfillment:8*

Some query filters on `:Order` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `OrderItem` is matched but never SET
*order-fulfillment:8*

Some query filters on `:OrderItem` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `InventoryLevel` is matched but never SET
*order-fulfillment:8*

Some query filters on `:InventoryLevel` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `ReorderLevel` is matched but never SET
*po-creation:8*

Some query filters on `:ReorderLevel` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `PurchaseOrder` is matched but never SET
*po-creation:9*

Some query filters on `:PurchaseOrder` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `POItem` is matched but never SET
*po-creation:9*

Some query filters on `:POItem` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `Supplier` is matched but never SET
*po-creation:16*

Some query filters on `:Supplier` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `RFQ` is matched but never SET
*rfq-resubmission:4*

Some query filters on `:RFQ` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `RFQItem` is matched but never SET
*rfq-fulfillment:6*

Some query filters on `:RFQItem` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `NewPoS` is matched but never SET [standing query]
*SQ nw-po-vetting-l1 › pattern:1*

Some query filters on `:NewPoS` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `VettingDecision` is matched but never SET [standing query]
*SQ nw-po-vetting-l2 › pattern:1*

Some query filters on `:VettingDecision` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `RejectedPoS` is matched but never SET [standing query]
*SQ nw-low-stock-after-reject › pattern:1*

Some query filters on `:RejectedPoS` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `ApprovedPoS` is matched but never SET [standing query]
*SQ nw-buyer-submission › pattern:1*

Some query filters on `:ApprovedPoS` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `SubmittedPoS` is matched but never SET [standing query]
*SQ nw-rfq-vetting › pattern:1*

Some query filters on `:SubmittedPoS` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `PoNewRFQ` is matched but never SET [standing query]
*SQ nw-rfq-vetting › pattern:1*

Some query filters on `:PoNewRFQ` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `WarehouseDelivery` is matched but never SET [standing query]
*SQ nw-finance-closure › pattern:1*

Some query filters on `:WarehouseDelivery` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `SupplierOpenPoS` is matched but never SET [standing query]
*SQ nw-finance-closure › act:4*

Some query filters on `:SupplierOpenPoS` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `OrderStatusOpeN` is matched but never SET [standing query]
*SQ nw-low-stock-on-new-order › pattern:1*

Some query filters on `:OrderStatusOpeN` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `OrderStatusFulfilleD` is matched but never SET [standing query]
*SQ nw-log-shipped › pattern:1*

Some query filters on `:OrderStatusFulfilleD` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Label `WarehouseFulfillment` is matched but never SET [standing query]
*SQ nw-log-shipped › pattern:1*

Some query filters on `:WarehouseFulfillment` but no provided ingest ever assigns that label. Unless another system sets it, those MATCHes will never succeed (silently).

### WARN: Relationship `IS_ACTIVE_ROLE` is matched but never created
*customer-order:6*

A query traverses/tests `[:IS_ACTIVE_ROLE]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `IS_CUSTOMER` is matched but never created
*customer-order:8*

A query traverses/tests `[:IS_CUSTOMER]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `IS_AVAILABLE_PRODUCT` is matched but never created
*customer-order:14*

A query traverses/tests `[:IS_AVAILABLE_PRODUCT]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `IS_SHIPPER` is matched but never created
*order-fulfillment:6*

A query traverses/tests `[:IS_SHIPPER]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `HAS_INVENTORY_LEVEL` is matched but never created
*order-fulfillment:8*

A query traverses/tests `[:HAS_INVENTORY_LEVEL]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `HAS_CUSTOMER_ADDRESS` is matched but never created
*order-fulfillment:18*

A query traverses/tests `[:HAS_CUSTOMER_ADDRESS]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `HAS_REORDER_LEVEL` is matched but never created
*po-creation:8*

A query traverses/tests `[:HAS_REORDER_LEVEL]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `SUPPLIES` is matched but never created
*po-creation:16*

A query traverses/tests `[:SUPPLIES]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `IS_SUPPLIER_APPROVED_STATE` is matched but never created
*po-creation:16*

A query traverses/tests `[:IS_SUPPLIER_APPROVED_STATE]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `HAS_SUPPLIER_NEW_PENDING_POS` is matched but never created
*rfq-submission:4*

A query traverses/tests `[:HAS_SUPPLIER_NEW_PENDING_POS]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `HAS_SUPPLIER_OPEN_POS` is matched but never created
*rfq-submission:7*

A query traverses/tests `[:HAS_SUPPLIER_OPEN_POS]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `HAS_SUPPLY_ORDER` is matched but never created
*rfq-fulfillment:17*

A query traverses/tests `[:HAS_SUPPLY_ORDER]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `HAS_CLOSED_PO_STATE` is matched but never created [standing query]
*SQ nw-finance-closure › act:3*

A query traverses/tests `[:HAS_CLOSED_PO_STATE]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `HAS_SUBMITTED_PO_STATE` is matched but never created [standing query]
*SQ nw-finance-closure › act:3*

A query traverses/tests `[:HAS_SUBMITTED_PO_STATE]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### WARN: Relationship `HAS_SUPPLIER_CLOSED_POS` is matched but never created [standing query]
*SQ nw-finance-closure › act:4*

A query traverses/tests `[:HAS_SUPPLIER_CLOSED_POS]` but no provided ingest creates it. If nothing else creates it, dependent SET/CREATE steps never run.

### INFO: Node "RolE" is keyed from multiple sources

Several ingests derive this node's ID from different fields. That is how cross-source joining works in Quine, but verify the value spaces really match (case, whitespace, format):
  • idFrom('RolE', 'Sales Representative')  (customer-order)
  • idFrom('RolE', 'WarehouseClerk')  (order-fulfillment)
  • idFrom('RolE', 'Procurement Assistant')  (po-creation)
  • idFrom('RolE', 'Level1Approver')  (SQ nw-po-vetting-l1 › act)
  • idFrom('RolE', 'Level2Approver')  (SQ nw-po-vetting-l2 › act)
  • idFrom('RolE', 'Level3Approver')  (SQ nw-po-vetting-l3 › act)
  • idFrom('RolE', 'Buyer')  (SQ nw-buyer-submission › act)
  • idFrom('RolE', 'Finance')  (SQ nw-finance-closure › act)

### WARN: Likely supernode: OrderStatusOpeN
*customer-order*

• [:IS_OPEN_ORDER_STATE] outgoing from Order: single fixed node receives one outgoing edge per distinct target (high cardinality)
This is a single fixed node (constant idFrom arguments), which is a classic hub. Consider storing this as a property on the other nodes, or partitioning the hub (e.g. by time period or hash bucket).

### WARN: Likely supernode: OrderStatusFulfilleD
*order-fulfillment*

• [:IS_FULFILLED_ORDER_STATE] outgoing from Order: single fixed node receives one outgoing edge per distinct target (high cardinality)
This is a single fixed node (constant idFrom arguments), which is a classic hub. Consider storing this as a property on the other nodes, or partitioning the hub (e.g. by time period or hash bucket).

### WARN: Likely supernode: LowStocK
*po-creation*

• [:IS_LOW_STOCK_PRODUCT] outgoing from Product: single fixed node receives one outgoing edge per distinct target (high cardinality)
This is a single fixed node (constant idFrom arguments), which is a classic hub. Consider storing this as a property on the other nodes, or partitioning the hub (e.g. by time period or hash bucket).

### WARN: Likely supernode: RejectedPoS
*po-creation*

• [:IS_REJECTED_PO_STATE] outgoing from PurchaseOrder: single fixed node receives one outgoing edge per distinct target (high cardinality)
This is a single fixed node (constant idFrom arguments), which is a classic hub. Consider storing this as a property on the other nodes, or partitioning the hub (e.g. by time period or hash bucket).

### WARN: Likely supernode: NewPoS
*po-creation*

• [:IS_NEW_PO_STATE] outgoing from PurchaseOrder: single fixed node receives one outgoing edge per distinct target (high cardinality)
This is a single fixed node (constant idFrom arguments), which is a classic hub. Consider storing this as a property on the other nodes, or partitioning the hub (e.g. by time period or hash bucket).

### WARN: Likely supernode: SubmittedPoS
*rfq-resubmission*

• [:IS_SUBMITTED_PO_STATE] outgoing from PurchaseOrder: single fixed node receives one outgoing edge per distinct target (high cardinality)
This is a single fixed node (constant idFrom arguments), which is a classic hub. Consider storing this as a property on the other nodes, or partitioning the hub (e.g. by time period or hash bucket).

### WARN: Likely supernode: ApprovedPoS [standing query]
*SQ nw-po-vetting-l1 › act*

• [:IS_APPROVED_PO_STATE] outgoing from PurchaseOrder: single fixed node receives one outgoing edge per distinct target (high cardinality)
This is a single fixed node (constant idFrom arguments), which is a classic hub. Consider storing this as a property on the other nodes, or partitioning the hub (e.g. by time period or hash bucket).
