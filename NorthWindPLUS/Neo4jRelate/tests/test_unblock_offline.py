"""
Offline tests of unblocking stuck customer orders: the two read templates, the play-forward simulation in relate
(sandbox/unblock.py) and the governed template that writes the POs. No Anthropic API, no Neo4j Aura: a relate store
holding tests/toy_stuck.py stands in for Aura.

  python tests/test_unblock_offline.py
"""
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
for sub in ("agent", "kb", "tests", "sandbox"):
    sys.path.insert(0, str(ROOT / sub))

import relate  # noqa: E402

import unblock  # noqa: E402
from model_templates import ModelTemplates  # noqa: E402
from toy_stuck import TOY_STUCK  # noqa: E402

TMP = Path(tempfile.mkdtemp(prefix="unblock-test-"))
T = ModelTemplates()
STUCK = T.template_by_title("Stuck customer orders")["cypher"]
PACE = T.template_by_title("Fulfillment pace")["cypher"]
CREATE = "\n".join(l for l in T.template_by_title("Create a Purchase Order for stuck customer orders")["cypher"].split("\n")
                   if "apoc.lock" not in l)
_N = iter(range(1000))


class StandIn:
    """A relate store standing in for Aura: the pull's driver fallback reads it through `.conn`."""
    def __init__(self, extra: str | None = None):
        self.path = TMP / f"aura-{next(_N)}.rl"
        self.conn = relate.connect(str(self.path))
        self.conn.execute(TOY_STUCK)
        if extra:
            self.conn.execute(extra)

    def q(self, cypher, params=None):
        return [dict(r) for r in self.conn.execute(cypher, params or {})]

    def inputs(self):
        stuck = self.q(STUCK, {"windowDays": 3, "stuckFactor": 3, "maxOrders": 5, "orderIdPrefix": "CO-"})
        pids = sorted({l["ProductID"] for s in stuck for l in s["Lines"]})
        return stuck, self.q(PACE, {"windowDays": 3, "productIds": pids, "orderIdPrefix": "CO-"})[0]


def main():
    checks = []

    def check(name, cond):
        checks.append(bool(cond))
        print(f"{'PASS' if cond else 'FAIL'}  {name}")

    # 1. Finding stuck orders and measuring the pace
    a = StandIn()
    stuck, pace = a.inputs()
    check("the stuck-orders template finds CO-BIG-1 (waiting 10 h; stuck after 3 x the 30-min median = 1.5 h)",
          [s["OrderID"] for s in stuck] == ["CO-BIG-1"] and stuck[0]["MedianShipHours"] == 0.5 and stuck[0]["StuckAfterHours"] == 1.5)
    check("...with its customer, its value, that it's past its required date, and both lines short",
          stuck[0]["Customer"] == "Ernst Handel" and stuck[0]["Value"] == 1000.0 and stuck[0]["PastRequiredDate"]
          and stuck[0]["ShortLines"] == 2)
    check("the small orders (fully in stock) and the imported historical order (not 'CO-') aren't reported as stuck",
          all(not s["OrderID"].startswith("CO-SMALL") and s["OrderID"] != "10999" for s in stuck))
    unfiltered = a.q(STUCK, {"windowDays": 3, "stuckFactor": 3, "maxOrders": 5, "orderIdPrefix": ""})
    check("without the 'CO-' filter, the imported orders shipped decades late push the median to decades, so nothing counts as stuck",
          unfiltered == [])
    check("the pace: 54 shipped (the 30 imported orders count for capacity), median time to ship 30 min ('CO-' only), PO lead 60 min",
          (pace["Shipped"], pace["MedianShipMinutes"], pace["POLeadMinutes"]) == (54, 30.0, 60.0)
          and {u["ProductID"]: u["Units"] for u in pace["ProductUnits"]} == {"1": 120, "2": 30})
    check("recent orders come back as line lists, for the simulation's new arrivals",
          len(pace["RecentOrders"]) > 0 and all("ProductID" in l for o in pace["RecentOrders"] for l in o))

    # 2. The simulation
    r = unblock.simulate(stuck, pace, aura=a, method="driver")
    o = r["orders"][0]
    lines = {l["product"]: l for l in r["lines"]}
    check("the copy came from Aura through the pull (driver fallback)", r["source"]["method"].startswith("driver"))
    check("without an extra delivery, BIG-1 never ships (0 of 5 runs, over 3 horizons)",
          o["withoutExtra"]["shippedInRuns"] == 0)
    check("by delivery time Chai is lower than today: the small orders and new arrivals take more than the PO on its way brings",
          lines["Chai"]["stockAtDeliveryMedian"] < lines["Chai"]["stockNow"])
    check("so the simulated extra for Chai is above the naive 'what's missing today' (11)",
          lines["Chai"]["naiveExtra"] == 11 and lines["Chai"]["extra"] > lines["Chai"]["naiveExtra"])
    check("...and it covers the imported order 10999 that ships first when the extra lands (35 Chai): well above 40 + 1 - stock",
          lines["Chai"]["extra"] >= 41 - lines["Chai"]["stockAtDeliveryMedian"] + 35)
    check("Chang has no competition and nothing on order: simulated = naive = 6",
          lines["Chang"]["naiveExtra"] == lines["Chang"]["extra"] == 6)
    check("with the simulated extra, BIG-1 ships within the horizon in at least 4 of 5 runs",
          o["status"] == "freed by the extra" and o["withExtra"]["shippedInRuns"] >= 4
          and o["withExtra"]["medianMinutes"] <= r["assumptions"]["horizonMinutes"])
    check("with only the naive extra it doesn't (evidence the simulation is needed)", o["withNaiveExtra"]["shippedInRuns"] < 4)
    check("one proposal for Exotic Liquids, unblocking BIG-1, costed at the unit cost",
          [(p["supplier"], p["unblocks"]) for p in r["proposals"]] == [("Exotic Liquids", ["CO-BIG-1"])]
          and r["proposals"][0]["estimatedCost"] == round(sum(l["extra"] * l["unitCost"] for l in r["proposals"][0]["lines"]), 2))
    check("the 3-day tolerance (Chai 120, Chang 30) isn't exceeded", not any(l["overTolerance"] for l in r["lines"]))
    check("reserving stock instead frees nothing (nothing is coming for Chang) and delays other orders",
          r["reservation"]["stuckFreed"] == 0 and r["reservation"]["otherOrdersDelayed"] > 0
          and o["withReservation"]["shippedInRuns"] == 0)
    check("assumptions are reported: delivery at minute 60, horizon 90 min, measured lead time",
          (r["assumptions"]["deliveryMinute"], r["assumptions"]["horizonMinutes"], r["assumptions"]["poLeadMeasured"]) == (60, 90, True))
    check("the scratch stores are deleted afterwards", not any(unblock.SCRATCH.glob("unblock-*")))
    check("the live graph was not touched (BIG-1 still open, stock unchanged)",
          a.q("MATCH (:OrderStatusOpeN)-->(o:Order {OrderID:'CO-BIG-1'}) RETURN count(o) AS n")[0]["n"] == 1
          and a.q("MATCH (:Product {ProductID:'1'})-->(i:InventoryLevel) RETURN i.UnitsInStock AS u")[0]["u"] == 30)

    check("the pace says how much of the simulation's own history it rests on (24 'CO-' orders shipped, ~10 hours)",
          pace["ShippedOwn"] == 24 and 9.5 <= pace["ObservedHours"] <= 10.5)
    check("a thin history is reported in plain words (fewer than 30 own orders shipped)",
          any("only 24 of the simulation's own orders" in n for n in r["history"]["notes"]))
    check("no safety margin by default: the proposed extra is the simulated one",
          r["assumptions"]["safetyPercent"] == 0 and all(l["extra"] == l["simulatedExtra"] for l in r["lines"]))
    rm = unblock.simulate(stuck, pace, aura=a, method="driver", safety_percent=50)
    check("an optional safety margin (50%) is added on top of the simulated quantity, and reported",
          rm["assumptions"]["safetyPercent"] == 50
          and all(l["extra"] >= -(-l["simulatedExtra"] * 3 // 2) for l in rm["lines"] if l["simulatedExtra"] > 0))

    # 3. Edge cases
    tight = dict(pace, ProductUnits=[{"ProductID": "1", "Units": 120}, {"ProductID": "2", "Units": 2}])
    r2 = unblock.simulate(stuck, tight, aura=a, method="driver")
    check("an extra above what customers ordered in 3 days is flagged (Chang: 6 needed, tolerance 2)",
          {l["product"]: l["overTolerance"] for l in r2["lines"]} == {"Chai": False, "Chang": True})
    soon = StandIn("""MATCH (n:NewPoS), (s:Supplier {SupplierID:"1"}), (chai:Product {ProductID:"1"}), (chang:Product {ProductID:"2"})
                      CREATE (n)-[:IS_NEW_PO_STATE]->(po:PurchaseOrder {PONumber:"PO-SOON", PODate: datetime() - duration({minutes: 50})}),
                             (po)-[:HAS_PO_ITEM {POqt:200}]->(chai), (po)-[:HAS_PO_ITEM {POqt:200}]->(chang)""")
    r3 = unblock.simulate(*soon.inputs(), aura=soon, method="driver")
    check("an order a PO already on its way will free needs nothing: 'frees itself', no proposal",
          r3["orders"][0]["status"] == "frees itself" and r3["proposals"] == [])
    gone = StandIn("MATCH (:ProductStatusAvailablE)-[r:IS_AVAILABLE_PRODUCT]->(:Product {ProductID:'2'}) DELETE r")
    r4 = unblock.simulate(*gone.inputs(), aura=gone, method="driver")
    check("a short product that can't be bought (not available): 'can't be freed by buying', and no line for it",
          r4["orders"][0]["status"] == "can't be freed by buying"
          and all(l["productId"] != "2" for p in r4["proposals"] for l in p["lines"]))

    # 4. The governed template
    w = StandIn()
    base = {"requesterId": "16", "supplierId": "1", "stuckOrderIds": ["CO-BIG-1"], "windowDays": 3, "stuckFactor": 3, "orderIdPrefix": "CO-",
            "source": "ui", "items": [{"productId": "1", "qty": 21, "recommendedQt": 21}, {"productId": "2", "qty": 6, "recommendedQt": 6}],
            "justification": "PRIORITY: unblocks customer order CO-CO-BIG-1 (waiting 10.0 h)."}
    check("without 'PRIORITY:' at the start of the justification, nothing is written",
          w.q(CREATE, dict(base, justification="Unblocks CO-BIG-1.")) == [])
    check("an approver (not a Procurement Assistant) writes nothing", w.q(CREATE, dict(base, requesterId="12")) == [])
    check("an unknown source writes nothing", w.q(CREATE, dict(base, source="spreadsheet")) == [])
    check("a line for a product on no stuck order (Aniseed Syrup) isn't written",
          w.q(CREATE, dict(base, supplierId="2", items=[{"productId": "3", "qty": 5, "recommendedQt": 5}])) == [])
    check("the imported historical order 10999 can't be used as a stuck order (not 'CO-')",
          w.q(CREATE, dict(base, stuckOrderIds=["10999"], items=[{"productId": "1", "qty": 5, "recommendedQt": 5}])) == [])
    made = w.q(CREATE, base)
    po = made[0]["PONumber"] if made else None
    row = w.q("""MATCH (:NewPoS)-->(po:PurchaseOrder {PONumber:$n})-[c:PO_CREATED_BY]->(e:Employee), (po)-[it:HAS_PO_ITEM]->(p)
                 RETURN c.Source AS s, e.EmployeeID AS by, left(c.Justification, 9) AS j, collect([p.ProductID, it.POqt, it.RecommendedQt]) AS lines""",
              {"n": po})
    check("it writes the PO in NewPoS: Source 'ui', the assistant, the PRIORITY justification, simulated quantities as RecommendedQt",
          made and made[0]["EstimatedCost"] == 231.0 and row[0]["s"] == "ui" and row[0]["by"] == "16" and row[0]["j"] == "PRIORITY:"
          and sorted(row[0]["lines"]) == [["1", 21, 21], ["2", 6, 6]])
    w.q("""MATCH (op:OrderStatusOpeN)-[r:IS_OPEN_ORDER_STATE]->(o:Order {OrderID:'CO-BIG-1'}), (f:OrderStatusFulfilleD)
           CREATE (f)-[:IS_FULFILLED_ORDER_STATE {FulfillDate: datetime()}]->(o) DELETE r""")
    check("once the stuck order has shipped, the template writes nothing for it", w.q(CREATE, base) == [])

    for s in (a, soon, gone, w):
        s.conn.close()
    shutil.rmtree(TMP, ignore_errors=True)
    print(f"\n{sum(checks)}/{len(checks)} checks passed")
    return all(checks)


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
