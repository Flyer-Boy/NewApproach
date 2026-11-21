"""
Unblocking stuck customer orders: plays the business forward on a copy of the live graph in relate.

The order-fulfillment loop ships the oldest open order whose every line is in stock, so a large order can wait while
smaller orders that arrive later ship first and use each delivery up. The question here is how much would have to
arrive so that the stuck orders actually ship. The naive answer ("order what's missing now") is wrong because orders
ahead in the queue and new orders still coming in consume stock before an extra delivery lands. Answering it means
replaying fulfillment forward (shipping orders, decrementing stock, adding arrivals and deliveries), which writes
constantly: it runs on a scratch relate store, never on Aura.

The key observation: the loop ships the oldest fully stocked order, and a stuck order is older than the small orders
that keep overtaking it. So once every line of a stuck order is in stock, it ships before them. Only older orders can
still get in first: ones that become fully stocked when the delivery lands (in practice the imported historical orders,
which are the oldest of all). The extra per product is what lifts the stock at delivery time above the stuck orders'
quantities plus whatever those older orders take first (`need_at_delivery`):

    start: extra[p] = (stuck quantities of p) + 1 - stock[p] at delivery time        (stock must be > qty)
    then:  let older fully stocked orders ship first; add what a stuck order is still short of; repeat

One baseline replay per run gives the stock and the queue at delivery time; a second replay with the extras, using the
loop's own Cypher, confirms the orders ship.

Steps:
  1. copy the relevant subgraph into a scratch store (relate pull, or the driver fallback: sandbox/pull.py);
  2. per run (random arrivals, seeded): baseline replay to a long horizon -> stock at delivery time, when each order
     shipped, how many other orders shipped;
  3. extras = 80th percentile of the per-run needs (so they work in at least 4 of 5 runs), then verify; bump and
     re-verify if needed (up to 3 rounds);
  4. the alternative rule: reserve stock for the stuck orders and replay without extras, to compare.

The fulfillment Cypher is the harness's own (model/NorthwindPlus_Stress_Test.py), minus the APOC locks. Time moves in
ticks of one minute (longer when the PO lead time is long, so a replay stays around 600 ticks at most); the pace (orders shipped and received per hour, PO lead time, median time to ship) and the shapes of
new orders come from the live graph's last few days ("Fulfillment pace" template). Results are estimates.
"""
from __future__ import annotations

import importlib.util
import math
import os
import random
import shutil
import statistics
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import relate

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "model" / "NorthwindPlus_Stress_Test.py"
SCRATCH = ROOT / "sandbox" / "scratch"

# Everything the fulfillment Cypher touches, plus suppliers, availability and the active POs.
PULL_QUERY = """
MATCH p = (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(:Order)-[:HAS_ORDER_PRODUCT]->(:Product)-[:HAS_INVENTORY_LEVEL]->(:InventoryLevel)
RETURN p
UNION ALL
MATCH p = (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(:Order)-[:HAS_ORDER_CUSTOMER]->(:Customer)-[:HAS_CUSTOMER_ADDRESS]->()
RETURN p
UNION ALL
MATCH p = ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(:PurchaseOrder)-[:HAS_PO_ITEM]->(:Product)
RETURN p
UNION ALL
MATCH p = (:Product)-[:HAS_INVENTORY_LEVEL]->(:InventoryLevel)
RETURN p
UNION ALL
MATCH p = (:Supplier)-[:SUPPLIES]->(:Product)
RETURN p
UNION ALL
MATCH p = (:ProductStatusAvailablE)-[:IS_AVAILABLE_PRODUCT]->(:Product)
RETURN p
UNION ALL
MATCH p = (:RolE {Title:"WarehouseClerk"})-[:IS_ACTIVE_ROLE]->(:Employee)
RETURN p
UNION ALL
MATCH p = (:ShipInfo)-[:HAS_SHIPPER]->(:Shipper)
RETURN p LIMIT 1
UNION ALL
MATCH p = (:OrderStatusFulfilleD)
RETURN p
"""

ACTIVE_PO_LINES = """
MATCH ()-[:IS_NEW_PO_STATE|IS_APPROVED_PO_STATE|IS_SUBMITTED_PO_STATE]->(po:PurchaseOrder)-[it:HAS_PO_ITEM]->(p:Product)
RETURN p.ProductID AS pid, it.POqt AS qty, duration.inSeconds(po.PODate, datetime()).seconds / 60.0 AS ageMinutes
"""

STOCK = "MATCH (p:Product)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel) WHERE p.ProductID IN $pids RETURN p.ProductID AS pid, i.UnitsInStock AS units"
ALL_STOCK = "MATCH (p:Product)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel) RETURN p.ProductID AS pid, i.UnitsInStock AS units"

# The open-order queue at a moment, oldest first, as the fulfillment loop sees it.
OPEN_QUEUE = """
MATCH (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(o:Order)-[d:HAS_ORDER_PRODUCT]->(p:Product)
WITH o, collect([p.ProductID, d.Quantity]) AS lines
RETURN o.OrderID AS id, lines ORDER BY o.OrderDate
"""

DELIVER = """
UNWIND $lines AS l
MATCH (:Product {ProductID: l.pid})-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
SET i.UnitsInStock = i.UnitsInStock + l.qty
"""

ARRIVE = """
MATCH (op:OrderStatusOpeN {Status:"Open"})
MATCH (c:Customer {CustomerID: $customerId})
CREATE (op)-[:IS_OPEN_ORDER_STATE]->(o:Order {OrderID: $orderId, OrderDate: datetime() + duration({minutes: $minute}),
                                               RequiredDate: datetime() + duration({days: 3})})-[:HAS_ORDER_CUSTOMER]->(c)
WITH o
UNWIND $lines AS l
MATCH (p:Product {ProductID: l.ProductID})
CREATE (o)-[:HAS_ORDER_PRODUCT {Quantity: l.Quantity, UnitPrice: coalesce(l.UnitPrice, p.UnitPrice), Discount: 0.0}]->(p)
"""

MARK_STUCK = "MATCH (o:Order) WHERE o.OrderID IN $ids SET o._Stuck = true"

# Reservation rule (the alternative): stock promised to open stuck orders can't be used by other orders.
SET_RESERVED = """
MATCH (i:InventoryLevel) SET i.Reserved = 0
WITH count(*) AS _
MATCH (:OrderStatusOpeN)-[:IS_OPEN_ORDER_STATE]->(o:Order {_Stuck: true})-[d:HAS_ORDER_PRODUCT]->(:Product)-[:HAS_INVENTORY_LEVEL]->(i:InventoryLevel)
WITH i, sum(d.Quantity) AS reserved
SET i.Reserved = reserved
"""

SUPPLIERS = """
MATCH (p:Product) WHERE p.ProductID IN $pids
OPTIONAL MATCH (s:Supplier)-[:SUPPLIES]->(p)
RETURN p.ProductID AS pid, p.ProductName AS product, p.UnitPrice AS unitPrice, s.SupplierID AS supplierId,
       s.CompanyName AS supplier, EXISTS { (:ProductStatusAvailablE)-[:IS_AVAILABLE_PRODUCT]->(p) } AS available
"""

CUSTOMERS = "MATCH (c:Customer) RETURN c.CustomerID AS id LIMIT 50"


def load_fulfillment() -> tuple[str, str]:
    """The harness's order-fulfillment Cypher without the APOC lock lines, and the reservation variant of it."""
    spec = importlib.util.spec_from_file_location("northwind_harness_unblock", HARNESS)
    harness = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = harness
    spec.loader.exec_module(harness)
    q = "\n".join(l for l in harness.ORDER_FULFILLMENT_QUERY.split("\n") if "apoc.lock" not in l)
    reserve_check = "inv.UnitsInStock - (CASE WHEN coalesce(o._Stuck, false) THEN 0 ELSE coalesce(inv.Reserved, 0) END) > details.Quantity"
    reserve_recheck = ("x.inv.UnitsInStock - (CASE WHEN coalesce(o._Stuck, false) THEN 0 ELSE coalesce(x.inv.Reserved, 0) END)"
                       " > x.details.Quantity")
    a, b = "inv.UnitsInStock > details.Quantity", "x.inv.UnitsInStock > x.details.Quantity"
    if q.count(a) != 1 or q.count(b) != 1:
        raise RuntimeError("The harness's fulfillment Cypher changed shape; update sandbox/unblock.py's reservation variant.")
    return q, q.replace(a, reserve_check).replace(b, reserve_recheck)


class Pace:
    """The business's pace, from the "Fulfillment pace" template row."""

    def __init__(self, row: dict):
        self.ship_per_min = (row.get("ShippedPerHour") or 0) / 60.0
        self.arrive_per_min = (row.get("ReceivedPerHour") or 0) / 60.0
        self.median_ship = row.get("MedianShipMinutes") or 30.0
        self.lead = row.get("POLeadMinutes")
        self.lead_measured = self.lead is not None
        if self.lead is None:          # no PO delivered in the window: assume a few times the time to ship
            self.lead = 4 * self.median_ship
        self.recent_orders = [o for o in (row.get("RecentOrders") or []) if o]
        self.units = {u["ProductID"]: u["Units"] for u in (row.get("ProductUnits") or [])}
        # One tick is one minute, or longer when the PO lead time is long, so the longest replay (3 horizons) stays
        # within about 600 ticks and a run takes seconds, not minutes.
        horizon_minutes = self.lead + max(1.0, self.median_ship)
        self.tick = max(1, math.ceil(3 * horizon_minutes / 600))

    @property
    def delivery_tick(self) -> int:
        return max(1, round(self.lead / self.tick))

    @property
    def horizon(self) -> int:
        return self.delivery_tick + max(1, round(self.median_ship / self.tick))

    @property
    def ship_per_tick(self) -> float:
        return self.ship_per_min * self.tick

    @property
    def arrive_per_tick(self) -> float:
        return self.arrive_per_min * self.tick


def _arrivals(rng: random.Random, rate: float) -> int:
    """Number of new orders this minute: Poisson with mean `rate` (small rates, so a simple Knuth draw)."""
    if rate <= 0:
        return 0
    k, p, limit = 0, 1.0, math.exp(-rate)
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1


def replay(store: Path, pace: Pace, fulfil: str, rng: random.Random, ticks: int, stuck_ids: list[str],
           deliveries: dict[int, list[dict]], record_at: int | None = None, record_pids: list[str] | None = None,
           reserve: bool = False, customers: list[str] | None = None) -> dict:
    """One run on one copy of the pulled store. deliveries: {tick: [{pid, qty}]}.
    Returns when each stuck order shipped (minute), how many other orders shipped, and stock at `record_at`
    (after that minute's existing deliveries, before any extras for that minute)."""
    conn = relate.connect(str(store))
    shipped: dict[str, int] = {}
    others = 0
    stock_at: dict[str, int] = {}
    queue_at: list[dict] = []
    capacity = 0.0
    try:
        conn.execute(MARK_STUCK, {"ids": stuck_ids})
        if reserve:
            conn.execute(SET_RESERVED)
        for t in range(1, ticks + 1):
            base = [d for d in deliveries.get(t, []) if not d.get("extra")]
            if base:
                conn.execute(DELIVER, {"lines": base})
            if record_at == t and record_pids:
                stock_at = {r["pid"]: r["units"] for r in conn.execute(ALL_STOCK)}
                queue_at = [{"id": r["id"], "lines": [(l[0], int(l[1])) for l in r["lines"]]} for r in conn.execute(OPEN_QUEUE)]
            extra = [d for d in deliveries.get(t, []) if d.get("extra")]
            if extra:
                conn.execute(DELIVER, {"lines": extra})
            for _ in range(_arrivals(rng, pace.arrive_per_tick)):
                if pace.recent_orders and customers:
                    conn.execute(ARRIVE, {"orderId": f"SIM-{t}-{uuid.uuid4().hex[:6]}", "minute": t * pace.tick,
                                          "customerId": rng.choice(customers), "lines": rng.choice(pace.recent_orders)})
            capacity += pace.ship_per_tick
            while capacity >= 1.0:
                capacity -= 1.0
                rows = list(conn.execute(fulfil))      # relate's .single() raises on no rows
                if not rows:
                    break
                oid = rows[0]["OrderID"]
                if oid in stuck_ids:
                    shipped.setdefault(oid, t)
                    if reserve:
                        conn.execute(SET_RESERVED)
                else:
                    others += 1
            if not reserve and record_at is not None and t >= record_at and len(shipped) == len(stuck_ids) and t >= ticks:
                break
    finally:
        conn.close()
    return {"shipped": shipped, "others": others, "stock_at": stock_at, "queue_at": queue_at}


def _copy(src: Path, dst: Path):
    for f in dst.parent.glob(dst.name + "*"):
        shutil.rmtree(f) if f.is_dir() else f.unlink()
    shutil.copy2(src, dst)


def _pct(values: list[float], q: float) -> float:
    v = sorted(values)
    return v[max(0, math.ceil(q * len(v)) - 1)]


def cascade(queue: list[dict], stock: dict[str, int], targets: set[str]) -> tuple[set[str], dict[str, int]]:
    """The moment a delivery lands: ship the oldest fully stocked order, again and again (the fulfillment loop's rule,
    without its pace), until every target has shipped or nothing more can ship. Older orders that become fully stocked
    ship first and take their share; that's why they count."""
    stock = dict(stock)
    shipped: set[str] = set()
    while not targets <= shipped:
        nxt = next((o for o in queue if o["id"] not in shipped
                    and all(stock.get(p, 0) > q for p, q in o["lines"])), None)
        if nxt is None:
            break
        for p, q in nxt["lines"]:
            stock[p] = stock.get(p, 0) - q
        shipped.add(nxt["id"])
    return shipped, stock


def need_at_delivery(queue: list[dict], stock: dict[str, int], targets: list[dict], cum: dict[str, int]) -> dict[str, int]:
    """The smallest extra per product that lets every target ship when the delivery lands, given the queue and stock
    at that moment (one replay). Starts from the stuck orders' own needs, then adds what older orders that become fully
    stocked would take first (for example imported historical orders, which are the oldest of all)."""
    ids = {t["OrderID"] for t in targets}
    extra = {p: max(0, cum[p] + 1 - stock.get(p, 0)) for p in cum}
    for _ in range(50):
        shipped, left = cascade(queue, {p: stock.get(p, 0) + extra.get(p, 0) for p in set(stock) | set(extra)}, ids)
        missing = [t for t in targets if t["OrderID"] not in shipped]
        if not missing:
            break
        for t in missing:
            for l in t["Lines"]:
                p, q = l["ProductID"], int(l["Ordered"])
                if p in extra and left.get(p, 0) <= q:
                    extra[p] += q + 1 - left.get(p, 0)
    return extra


def history_notes(pace_row: dict, pace: "Pace") -> list[str]:
    """Plain warnings when the pace rests on little history: the simulation projects the near future from the recent
    past, so a young database under-estimates the competition and the quantities come out low."""
    notes = []
    own = pace_row.get("ShippedOwn")
    if own is not None and own < 30:
        notes.append(f"only {own} of the simulation's own orders shipped in the window, so the time to ship and the "
                     f"pace of new orders are rough")
    hours = pace_row.get("ObservedHours")
    if hours is not None and hours < 6:
        notes.append(f"the history covers only {hours} hours")
    if not pace.lead_measured:
        notes.append(f"no PO was delivered in the window, so the PO lead time is estimated ({pace.lead:.0f} min); "
                     f"a longer real lead time means more competition and more stock needed")
    return notes


def simulate(stuck: list[dict], pace_row: dict, aura=None, runs: int = 5, method: str = "auto",
             source_store: Path | None = None, keep: bool = False, safety_percent: float | None = None) -> dict:
    """stuck: rows of the "Stuck customer orders" template (oldest first). pace_row: the "Fulfillment pace" row
    (with ProductUnits for the stuck orders' products). Copies the subgraph from `aura` (or uses `source_store`),
    plays it forward, and returns the proposal, the evidence and the reservation comparison."""
    from pull import pull     # sandbox/ is on sys.path when the agent or the API imports this module

    pace = Pace(pace_row)
    if safety_percent is None:
        safety_percent = float(os.environ.get("UNBLOCK_SAFETY_PERCENT") or 0)
    fulfil, fulfil_reserve = load_fulfillment()
    run_dir = SCRATCH / f"unblock-{uuid.uuid4().hex[:8]}"
    run_dir.mkdir(parents=True, exist_ok=True)
    try:
        baseline = run_dir / "pulled.rl"
        if source_store:
            shutil.copy2(source_store, baseline)
            source = {"method": "copy of a local store", "pulled_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}
        else:
            source = pull(baseline, aura=aura, method=method, query=PULL_QUERY)

        ids = [s["OrderID"] for s in stuck]
        pids = sorted({l["ProductID"] for s in stuck for l in s["Lines"]})
        conn = relate.connect(str(baseline))
        try:
            po_lines = [dict(r) for r in conn.execute(ACTIVE_PO_LINES)]
            stock_now = {r["pid"]: r["units"] for r in conn.execute(STOCK, {"pids": pids})}
            products = {r["pid"]: dict(r) for r in conn.execute(SUPPLIERS, {"pids": pids})}
            customers = [r["id"] for r in conn.execute(CUSTOMERS)]
        finally:
            conn.close()

        T, H = pace.delivery_tick, pace.horizon
        long_h = 3 * H
        existing: dict[int, list[dict]] = {}
        for l in po_lines:                      # POs already on their way land at created + lead time
            tick = max(1, round((pace.lead - float(l["ageMinutes"] or 0)) / pace.tick))
            existing.setdefault(tick, []).append({"pid": l["pid"], "qty": int(l["qty"])})
        on_order = {}
        for l in po_lines:
            on_order[l["pid"]] = on_order.get(l["pid"], 0) + int(l["qty"])

        def one(seed: int, deliveries, ticks, record=False, reserve=False):
            copy = run_dir / f"run-{seed}-{uuid.uuid4().hex[:6]}.rl"
            _copy(baseline, copy)
            try:
                return replay(copy, pace, fulfil_reserve if reserve else fulfil, random.Random(seed), ticks, ids,
                              deliveries, record_at=T if record else None, record_pids=pids if record else None,
                              reserve=reserve, customers=customers)
            finally:
                for f in run_dir.glob(copy.name + "*"):
                    shutil.rmtree(f) if f.is_dir() else f.unlink()

        seeds = list(range(1, runs + 1))
        base_runs = {s: one(s, existing, long_h, record=True) for s in seeds}

        # Orders that ship anyway within the horizon in most runs need nothing extra.
        frees_itself = [o for o in ids if sum(1 for s in seeds if base_runs[s]["shipped"].get(o, 10**9) <= H) >= math.ceil(0.8 * runs)]
        targets = [s for s in stuck if s["OrderID"] not in frees_itself]
        cum: dict[str, int] = {}
        for s in targets:                        # oldest first
            for l in s["Lines"]:
                cum[l["ProductID"]] = cum.get(l["ProductID"], 0) + int(l["Ordered"])

        per_run = [need_at_delivery(base_runs[s]["queue_at"], base_runs[s]["stock_at"], targets, cum) for s in seeds]
        simulated = {p: int(_pct([r[p] for r in per_run], 0.8)) for p in cum}
        # Optional safety margin on top (UNBLOCK_SAFETY_PERCENT), for a young database whose short history
        # under-estimates the competition. The replay below verifies the quantities with the margin included.
        extras = {p: (math.ceil(q * (1 + safety_percent / 100)) if q > 0 else 0) for p, q in simulated.items()}
        unbuyable = {p for p in extras if not products.get(p, {}).get("supplierId") or not products.get(p, {}).get("available")}

        verify, rounds = {}, 0
        while targets:
            rounds += 1
            deliveries = {k: list(v) for k, v in existing.items()}
            deliveries.setdefault(T, []).extend({"pid": p, "qty": q, "extra": True} for p, q in extras.items()
                                                if q > 0 and p not in unbuyable)
            verify = {s: one(s, deliveries, H) for s in seeds}
            failing = [o for o in targets if sum(1 for s in seeds if verify[s]["shipped"].get(o["OrderID"], 10**9) <= H)
                       < math.ceil(0.8 * runs)]
            if not failing or rounds >= 3:
                break
            for o in failing:
                for l in o["Lines"]:
                    p = l["ProductID"]
                    if p in extras and p not in unbuyable:
                        extras[p] += max(1, math.ceil(0.1 * max(extras[p], int(l["Ordered"]))))

        # The naive answer, for comparison: order only what's missing today (ignores the queue and new orders).
        naive_extra = {p: max(0, cum[p] + 1 - stock_now.get(p, 0)) for p in cum}
        naive_deliveries = {k: list(v) for k, v in existing.items()}
        naive_deliveries.setdefault(T, []).extend({"pid": p, "qty": q, "extra": True} for p, q in naive_extra.items()
                                                  if q > 0 and p not in unbuyable)
        naive_runs = {s: one(s, naive_deliveries, H) for s in seeds} if targets else {}

        reserve_runs = {s: one(s, existing, long_h, reserve=True) for s in seeds}
    finally:
        if not keep:
            shutil.rmtree(run_dir, ignore_errors=True)

    def ship_stats(runs_: dict, oid: str, horizon: int) -> dict:
        ticks = [r["shipped"].get(oid) for r in runs_.values()]
        within = [t for t in ticks if t is not None and t <= horizon]
        return {"shippedInRuns": len(within), "runs": len(ticks),
                "medianMinutes": statistics.median(within) * pace.tick if within else None}

    orders_out = []
    for s in stuck:
        oid = s["OrderID"]
        status = ("frees itself" if oid in frees_itself else
                  "can't be freed by buying" if any(l["ProductID"] in unbuyable and l["Short"] for l in s["Lines"]) else
                  "freed by the extra" if verify and sum(1 for r in verify.values() if r["shipped"].get(oid, 10**9) <= H)
                  >= math.ceil(0.8 * runs) else "not freed within the horizon")
        orders_out.append({
            "OrderID": oid, "Customer": s.get("Customer"), "WaitingHours": s.get("WaitingHours"),
            "PastRequiredDate": s.get("PastRequiredDate"), "Value": s.get("Value"), "status": status,
            "withoutExtra": ship_stats(base_runs, oid, long_h),
            "withExtra": ship_stats(verify, oid, H) if verify else None,
            "withNaiveExtra": ship_stats(naive_runs, oid, H) if naive_runs and oid not in frees_itself else None,
            "withReservation": ship_stats(reserve_runs, oid, long_h)})

    lines = []
    for p in sorted(extras):
        info = products.get(p, {})
        stuck_qty = cum.get(p, 0)
        naive = max(0, stuck_qty + 1 - stock_now.get(p, 0))
        tolerance = int(pace.units.get(p, 0))
        lines.append({
            "productId": p, "product": info.get("product"), "supplierId": info.get("supplierId"),
            "supplier": info.get("supplier"), "available": bool(info.get("available")),
            "unitCost": round((info.get("unitPrice") or 0) * 0.7, 2),
            "stuckQty": stuck_qty, "stockNow": stock_now.get(p, 0), "onOrder": on_order.get(p, 0),
            "stockAtDeliveryMedian": statistics.median(base_runs[s]["stock_at"].get(p, 0) for s in seeds),
            "naiveExtra": naive, "simulatedExtra": simulated.get(p, extras[p]), "extra": extras[p],
            "tolerance3Days": tolerance, "overTolerance": extras[p] > tolerance,
            "unblocks": [s["OrderID"] for s in targets if any(l["ProductID"] == p for l in s["Lines"])]})

    proposals: dict[str, dict] = {}
    for l in lines:
        if l["extra"] <= 0 or l["productId"] in unbuyable:
            continue
        pr = proposals.setdefault(l["supplierId"], {"supplierId": l["supplierId"], "supplier": l["supplier"],
                                                    "lines": [], "unblocks": set()})
        pr["lines"].append(l)
        pr["unblocks"].update(l["unblocks"])
    for pr in proposals.values():
        pr["estimatedCost"] = round(sum(l["extra"] * l["unitCost"] for l in pr["lines"]), 2)
        pr["unblocks"] = [o for o in ids if o in pr["unblocks"]]

    others_base = statistics.median(r["others"] for r in base_runs.values())
    others_reserve = statistics.median(r["others"] for r in reserve_runs.values())
    return {
        "source": source,
        "assumptions": {
            "runs": runs, "tickMinutes": pace.tick, "deliveryMinute": T * pace.tick, "horizonMinutes": H * pace.tick,
            "comparisonMinutes": long_h * pace.tick,
            "shippedPerHour": round(pace.ship_per_min * 60, 2), "receivedPerHour": round(pace.arrive_per_min * 60, 2),
            "medianShipMinutes": pace.median_ship, "poLeadMinutes": pace.lead, "poLeadMeasured": pace.lead_measured,
            "verifyRounds": rounds, "safetyPercent": safety_percent},
        "history": {"shippedOwn": pace_row.get("ShippedOwn"), "observedHours": pace_row.get("ObservedHours"),
                    "poDelivered": pace_row.get("PODelivered"), "notes": history_notes(pace_row, pace)},
        "orders": orders_out, "lines": lines, "proposals": list(proposals.values()),
        "reservation": {
            "otherOrdersShippedWithout": others_base, "otherOrdersShippedWith": others_reserve,
            "otherOrdersDelayed": max(0, others_base - others_reserve),
            "stuckFreed": sum(1 for o in orders_out if o["withReservation"]["shippedInRuns"] >= math.ceil(0.8 * runs)),
            "stuckTotal": len(orders_out)},
    }
