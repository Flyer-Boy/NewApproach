// Every call goes to the Python API (../api/main.py). The browser holds no database credentials and computes no
// business numbers: costs, approval levels, demand and suggestions all come from the API, which runs the same
// governed Cypher as the AI agent and the simulation loops.

export type Item = { productId: string; qty: number };

export type User = { employeeId: string; name: string; roles: string[] };

export type DemandRow = {
  ProductID: string; Product: string; Orders: number; UnitsOrdered: number; DaysObserved: number;
  UnitsPerDay: number; EffectiveStock: number; PlannedQt: number; UnitCost: number;
  DaysOfCoverAfterPO: number | null; SuggestedQt: number | null;
};

export type Demand = {
  rows: DemandRow[]; windowDays: number; coverDays: number;
  po: { estimatedCost: number; approvalLevel: string; anySuggestion: boolean;
        estimatedCostWithSuggestions: number; approvalLevelWithSuggestions: string };
};

export type RestockLine = {
  ProductID: string; Product: string; UnitsInStock: number; OnActivePOs: number; OpenOrderQty: number;
  StockThreshold: number; RecommendedQt: number; UnitCost: number; LineCost: number;
};

export type RestockRow = {
  SupplierID: string; Supplier: string; Lines: RestockLine[]; EstimatedCost: number;
  ApprovalLevelNeeded: string; demand: Demand | null;
};

export type ResubLine = RestockLine & { RejectedQt: number; Orderable: boolean };

export type ResubRow = {
  RejectedPO: string; RejectedOn: string; SupplierID: string; Supplier: string;
  RaisedBy: { EmployeeID: string; Name: string; Source: string | null } | null;
  Rejection: { Level: string; RejectedBy: string; Comment: string | null } | null;
  Lines: ResubLine[]; EstimatedCost: number; ApprovalLevelNeeded: string; demand: Demand | null;
};

export type Recommendation<R> = { rows: R[]; warning?: string; summary?: unknown };

export type ReviewEntry = {
  title: string; cost: number | null; level: string; justification: string; flags: string[];
  lines: { productId: string; product: string; qty: number; recommendedQt: number | null }[];
};

export type Review = { previewId: string; header: string; entries: ReviewEntry[] };

export type Status = {
  user: User; mode: string; access: string | null;
  limits: { l1: number; l2: number; l3: number }; loops: { created: number; resubmitted: number };
};

export type Audit = {
  hours: number;
  activity: { Source: string; Action: string; POs: number }[];
  decisions: { PONumber: string; Source: string; Action: string; ResubmittedFrom: string | null; By: string;
               Date: string; Justification: string | null;
               ChangedLines: { Product: string; Ordered: number; Recommended: number | null }[] }[];
};

export type StuckOrder = {
  OrderID: string; Customer: string | null; OrderDate: string; PastRequiredDate: boolean; WaitingHours: number;
  MedianShipHours: number; StuckAfterHours: number; Value: number; LineCount: number; ShortLines: number;
  Lines: { ProductID: string; Product: string; Ordered: number; InStock: number; Short: boolean }[];
};

export type Pace = {
  Shipped: number; Received: number; PODelivered: number; ShippedPerHour: number; ReceivedPerHour: number;
  MedianShipMinutes: number | null; POLeadMinutes: number | null;
};

export type ShipStats = { shippedInRuns: number; runs: number; medianMinutes: number | null };

export type UnblockLine = {
  productId: string; product: string; supplierId: string; supplier: string; available: boolean; unitCost: number;
  stuckQty: number; stockNow: number; onOrder: number; stockAtDeliveryMedian: number; naiveExtra: number;
  simulatedExtra: number; extra: number;
  tolerance3Days: number; overTolerance: boolean; unblocks: string[];
};

export type Unblock = {
  message?: string;
  pace: Pace;
  assumptions?: { runs: number; tickMinutes: number; deliveryMinute: number; horizonMinutes: number; comparisonMinutes: number;
                  shippedPerHour: number; receivedPerHour: number; medianShipMinutes: number; poLeadMinutes: number;
                  poLeadMeasured: boolean; safetyPercent: number };
  history?: { shippedOwn: number | null; observedHours: number | null; poDelivered: number | null; notes: string[] };
  orders: { OrderID: string; Customer: string | null; WaitingHours: number; PastRequiredDate: boolean; Value: number;
            status: string; withoutExtra: ShipStats; withExtra: ShipStats | null; withNaiveExtra: ShipStats | null;
            withReservation: ShipStats }[];
  lines: UnblockLine[];
  proposals: { supplierId: string; supplier: string; lines: UnblockLine[]; unblocks: string[]; estimatedCost: number;
               approvalLevel: string; priorityLine: string }[];
  reservation?: { otherOrdersShippedWithout: number; otherOrdersShippedWith: number; otherOrdersDelayed: number;
                  stuckFreed: number; stuckTotal: number };
  source?: { method: string; pulled_at: string };
};

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method,
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin",
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, typeof data.detail === "string" ? data.detail : res.statusText);
  return data as T;
}

export const api = {
  config: () => call<{ mode: string; drafts: boolean; database: string | null }>("GET", "/api/config"),
  employees: () => call<{ employeeId: string; name: string }[]>("GET", "/api/employees"),
  signIn: (employeeId: string) =>
    call<{ user: User; mode: string; canUseProcurement: boolean; reason: string | null }>("POST", "/api/session", { employeeId }),
  signOut: () => call("DELETE", "/api/session"),
  status: () => call<Status>("GET", "/api/status"),
  restock: () => call<Recommendation<RestockRow>>("GET", "/api/restock"),
  resubmissions: () => call<Recommendation<ResubRow>>("GET", "/api/resubmissions"),
  demand: (items: Item[]) => call<Demand>("POST", "/api/demand", { items }),
  draft: (body: { kind: "create" | "resubmit" | "cancel" | "unblock"; supplierId?: string; rejectedPO?: string; items?: Item[] }) =>
    call<{ draft: string; model: string }>("POST", "/api/justification-draft", body),
  previewCreate: (pos: { supplierId: string; items: Item[]; justification: string }[]) =>
    call<Review>("POST", "/api/purchase-orders/preview", pos),
  commitCreate: (previewId: string) =>
    call<{ created: { PONumber: string; supplierId: string; EstimatedCost: number; approvalLevel: string }[];
           left_out: { product: string; reason: string }[] }>("POST", "/api/purchase-orders", { previewId }),
  previewResubmit: (subs: { rejectedPO: string; items: Item[]; justification: string }[]) =>
    call<Review>("POST", "/api/resubmissions/preview", subs),
  commitResubmit: (previewId: string) =>
    call<{ resubmitted: { PONumber: string; ResubmittedFrom: string; EstimatedCost: number; approvalLevel: string }[];
           left_out: { product: string; reason: string }[];
           not_resubmitted: { rejectedPO: string; reason: string }[] }>("POST", "/api/resubmissions", { previewId }),
  previewCancel: (cancels: { rejectedPO: string; justification: string }[]) =>
    call<Review>("POST", "/api/cancellations/preview", cancels),
  commitCancel: (previewId: string) =>
    call<{ cancelled: string[]; not_cancelled: { rejectedPO: string; reason: string }[] }>("POST", "/api/cancellations", { previewId }),
  audit: (hours: number) => call<Audit>("GET", `/api/audit?hours=${hours}`),
  stuckOrders: () => call<{ rows: StuckOrder[]; pace: Pace; windowDays: number; stuckFactor: number; maxOrders: number;
                            orderIdPrefix: string }>("GET", "/api/stuck-orders"),
  simulateUnblock: () => call<Unblock>("POST", "/api/stuck-orders/simulate"),
  previewUnblock: (pos: { supplierId: string; items: Item[]; justification: string }[]) =>
    call<Review>("POST", "/api/stuck-orders/preview", pos),
  commitUnblock: (previewId: string) =>
    call<{ created: { PONumber: string; supplierId: string; EstimatedCost: number; approvalLevel: string; unblocks: string[] }[];
           left_out: { product: string; reason: string }[] }>("POST", "/api/stuck-orders/commit", { previewId }),
};

export const money = (n: number | null | undefined) =>
  n == null ? "–" : n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** After any write, every screen's data is stale (a new PO changes what's still needed on rejected POs, and vice
 *  versa): reload them all from the graph, and bring the result message into view. */
export function refreshAfterWrite(qc: { invalidateQueries: (f: { queryKey: string[] }) => unknown }) {
  for (const key of ["restock", "resubmissions", "audit", "status", "stuck"]) qc.invalidateQueries({ queryKey: [key] });
  window.scrollTo({ top: 0, behavior: "smooth" });
}
