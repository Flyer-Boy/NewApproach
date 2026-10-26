This is a Quine Recipe Version of the NothrhWind PLUS full database - Graph + simulation loop implemented with a combination of Steams and Standing queries 

The Streams simulate end-usrr Applications issuing Cypher queries against the Graph (i.e. Customer Order by Sales reo, PO crearion by a Procurement Assistant, etc.)
The Standing Queries are trigerd by State changes.  


How to run it (WSL, from the folder with both files)

Start Quine with the recipe. The streams wait until the data is in:
docker run --rm --name northwind-quine -p 8080:8080 -v "$PWD":/demo thatdot/quine -r /demo/northwind-plus-simulation.yaml
In a second window, load the graph: ./northwind-plus-quine-batch.sh --import-only
Its last step sets a switch node (Simulation.Ready = true), and the simulation starts by itself.
To watch the company act: docker logs -f northwind-quine 2>&1 | grep --line-buffered -o '"alert":"[^"]*"'

The order matters because Quine runs a recipe on a throwaway store. The graph disappears when Quine stops, so start Quine first and load the data second, every time.

What’s in the recipe

Ingest streams (the outside world):
Customer orders every 10 s.
Order fulfillment every 15 s.
Supplier RFQs every 15 s; 15% are priced over the PO budget, so RFQ vetting rejects them by rule.
RFQ resubmission every 20 s.
Goods arriving every 15 s.
Threshold recalibration every 5 minutes.
PO creation every 30 s, one PO per supplier as you chose.
To change a pace, edit the n % <seconds> on the first line of a stream.
Standing queries (your rules):
PO vetting at all three levels.
Putting a rejected PO’s products back in LowStock.
Buyer submission.
RFQ vetting.
Adding approved RFQ quantities to units on order.
Finance payment and closure.
A new one that re-checks LowStock when a customer order arrives (the Python loop used to do this).
Two log-only rules that print “PO created” and “shipped” alerts.
Sample queries (44, in the query-bar drop-down): your reports from the end of the Cypher script, adapted to Quine, plus the data-quality checks. Each check shows 0 when it’s ok.
Quick queries (23, on right-click): Product, PO, RFQ, Order, Customer, Supplier, Employee and Collection nodes each get their own. Examples are a product’s reorder rule right now, a PO’s vetting trail, and an RFQ’s quote against the PO budget.

Things you should know

Retries: Quine warns it may retry a stream after a timeout. The re-checks make a retry do nothing everywhere except customer orders, where a retry would add one extra order.
No PO rejections by rule in either run. As before, the data never breaks the PO rules. All rejections seen came from overpriced RFQs.
Two reports left out: db.schema.visualization() doesn’t exist in Quine. The duplicate-relationship check can never find anything, because Quine never keeps two copies of the same edge.
Changes to your report queries:
Count subqueries: count{} doesn’t work in Quine, so it became size([pattern | x]).
Duration function: duration_between became duration.between.
Date literals: dates now carry a Z time zone.
Blocked-orders reports: they use >= so they match the fulfillment rule, which ships only when stock is strictly greater than the quantity.
New quirk: WHERE NOT n:Label silently matches nothing in Quine, so I wrote it as NOT "Label" IN labels(n). None of the rules use it.
Three icons: I’m not certain ion-play, ion-checkmark-circled and ion-refresh exist in the icon set Quine uses. If they don’t, those nodes just show without an icon.