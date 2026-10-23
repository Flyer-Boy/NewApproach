#!/usr/bin/env bash
# =============================================================================
# NorthWind PLUS v2.4 -> Quine: OPTIONAL recommendation layer
#
# Not part of the demo. Run it on demand, after northwind-plus-quine-batch.sh,
# to (re)build the collaborative-filtering layer:
#     (Customer)-[:HAS_RATING]->(:Rating {Rating})-[:RATING_FOR_PRODUCT]->(Product)
#     (Customer)-[:HAS_SIMILARITY]->(:Similarity {Similarity})<-[:HAS_SIMILARITY]-(Customer)
# Re-running it is safe: Rating and Similarity nodes have deterministic ids
# (idFrom), so a second run updates the scores instead of duplicating them.
#
#   ./northwind-plus-quine-recommendations.sh [--quine URL]
# =============================================================================

set -uo pipefail

QUINE="http://localhost:8080"
FROM=1
while [ $# -gt 0 ]; do
  case "$1" in
    --quine) QUINE="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
ENDPOINT="${QUINE}/api/v2/graph/quine/cypher:query?timeout=600s"
CSV=""
STEP=0

# --- helpers -----------------------------------------------------------------

# post <cypher>  -> prints the response body, then the HTTP code on the last line
post() {
  python3 -c 'import json,sys; sys.stdout.write(json.dumps({"text": sys.argv[1], "parameters": {}}))' "$1" |
    curl -sS -m 900 -w '\n%{http_code}' -X POST "$ENDPOINT" \
         -H 'Content-Type: application/json' --data-binary @-
}

# exec_query <title> <cypher>  -> body on stdout; exits the script on any error
exec_query() {
  local title="$1" q="${2//\{\{CSV\}\}/$CSV}" out code body
  out="$(post "$q")" || { echo "ERROR: cannot reach Quine at $QUINE" >&2; exit 1; }
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  if [ "$code" != "200" ] || [[ "$body" == '{"error"'* ]]; then
    echo >&2
    echo "FAILED at step $STEP: $title (HTTP $code)" >&2
    printf '%s' "$body" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["error"]["message"])
except Exception: print(sys.stdin.read())' >&2
    echo "Fix it, then resume with:  $0 --from $STEP" >&2
    exit 1
  fi
  printf '%s' "$body"
}

# summarise <body>  -> one short line: row count, or the single value returned
summarise() {
  printf '%s' "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin); r = d.get("results", [])
if not d.get("columns"): print("ok")
elif len(r) == 1: print(", ".join(f"{c}={v}" for c, v in zip(d["columns"], r[0])))
else: print(f"{len(r)} rows")'
}

# table <body>  -> the result as an aligned table
table() {
  printf '%s' "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin); cols = d.get("columns", []); rows = [["" if v is None else str(v) for v in r] for r in d.get("results", [])]
w = [max([len(c)] + [len(r[i]) for r in rows]) for i, c in enumerate(cols)]
print("        " + "  ".join(c.ljust(w[i]) for i, c in enumerate(cols)))
for r in rows: print("        " + "  ".join(v.ljust(w[i]) for i, v in enumerate(r)))'
}

begin_step() { STEP=$((STEP + 1)); [ "$STEP" -ge "$FROM" ]; }
skipped()    { printf '  %3d  %-74s skipped\n' "$STEP" "$1"; }

# run "title" <<'CYPHER' ... CYPHER          one write command
run() {
  local title="$1" q; q="$(cat)"
  begin_step || { skipped "$title"; return 0; }
  printf '  %3d  %-74s ' "$STEP" "$title"
  local body; body="$(exec_query "$title" "$q")" || exit 1
  summarise "$body"
}

# repeat N "title" <<'CYPHER' ... CYPHER     the same command N times (a loop command)
repeat() {
  local n="$1" title="$2" q; q="$(cat)"
  begin_step || { skipped "$title"; return 0; }
  printf '  %3d  %-74s ' "$STEP" "$title (x$n)"
  local i body
  for i in $(seq 1 "$n"); do body="$(exec_query "$title" "$q")" || exit 1; done
  echo "ok"
}

# check "title" <<'CYPHER' ... CYPHER        checkpoint: prints the result table
check() {
  local title="$1" q; q="$(cat)"
  begin_step || { skipped "CHECK: $title"; return 0; }
  printf '  %3d  CHECK: %s\n' "$STEP" "$title"
  local body; body="$(exec_query "$title" "$q")" || exit 1
  table "$body"
}

# must_be_zero "title" <<'CYPHER' ... CYPHER  invariant: the query returns one number that must be 0
must_be_zero() {
  local title="$1" q; q="$(cat)"
  begin_step || { skipped "INVARIANT: $title"; return 0; }
  printf '  %3d  %-74s ' "$STEP" "INVARIANT: $title"
  local body v; body="$(exec_query "$title" "$q")" || exit 1
  v="$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["results"][0][0])')"
  if [ "$v" = "0" ]; then echo "ok (0)"; else echo "VIOLATED ($v)"; INVARIANT_FAILURES=$((INVARIANT_FAILURES + 1)); fi
}
INVARIANT_FAILURES=0

section() { [ "$FROM" -le "$((STEP + 1))" ] || return 0; echo; echo "== $1"; }

echo "NorthWind PLUS v2.4 -> Quine at $QUINE: recommendation layer"
section "Recommendation layer (Rating, Similarity)"

run "Customer -> Product ratings (share of the customer's order lines)" <<'CYPHER'
MATCH (cs) WHERE id(cs) = idFrom("CustomerS")
MATCH (cs)-[:IS_CUSTOMER]->(c:Customer)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_ITEM]->(:OrderItem)-[:ORDER_ITEM_PRODUCT]->(p:Product)
WITH c, count(p) AS Total
MATCH (c)<-[:HAS_ORDER_CUSTOMER]-(o:Order)-[:HAS_ORDER_ITEM]->(:OrderItem)-[:ORDER_ITEM_PRODUCT]->(p:Product)
WITH c, Total, p, count(o) * 1.0 AS Orders
MATCH (rated) WHERE id(rated) = idFrom("Rating", c.CustomerID, p.ProductID)
SET rated:Rating, rated.Rating = Orders / Total
CREATE (c)-[:HAS_RATING]->(rated), (rated)-[:RATING_FOR_PRODUCT]->(p)
RETURN count(rated) AS ratings
CYPHER

run "Customer <-> Customer cosine similarity" <<'CYPHER'
MATCH (c1:Customer)-[:HAS_RATING]->(r1:Rating)-[:RATING_FOR_PRODUCT]->(p:Product)<-[:RATING_FOR_PRODUCT]-(r2:Rating)<-[:HAS_RATING]-(c2:Customer)
WHERE c1.CustomerID < c2.CustomerID
WITH c1, c2,
     sum(r1.Rating * r2.Rating) AS dot_product,
     sqrt(reduce(x = 0.0, a IN collect(r1.Rating) | x + a^2)) AS r1_length,
     sqrt(reduce(y = 0.0, b IN collect(r2.Rating) | y + b^2)) AS r2_length
MATCH (s) WHERE id(s) = idFrom("Similarity", c1.CustomerID, c2.CustomerID)
SET s:Similarity, s.Similarity = dot_product / (r1_length * r2_length)
CREATE (c1)-[:HAS_SIMILARITY]->(s), (c2)-[:HAS_SIMILARITY]->(s)
RETURN count(s) AS customerPairs
CYPHER

check "top recommendations for ANTON" <<'CYPHER'
MATCH (me) WHERE id(me) = idFrom("Customer", "ANTON")
MATCH (me)-[:HAS_SIMILARITY]->(:Similarity)<-[:HAS_SIMILARITY]-(c:Customer)-[:HAS_RATING]->(r:Rating)-[:RATING_FOR_PRODUCT]->(p:Product)
WHERE NOT (me)-[:HAS_RATING]->(:Rating)-[:RATING_FOR_PRODUCT]->(p)
WITH p, collect(r.Rating)[0..1] AS Ratings, collect(c.CompanyName)[0..1] AS Customers
WITH p, Customers, round(reduce(s = 0, i IN Ratings | s + i) / size(Ratings), 5) AS Recommendation
RETURN p.ProductName AS product, Customers[0] AS likedBy, Recommendation
ORDER BY Recommendation DESC LIMIT 5
CYPHER

echo
echo "DONE: recommendation layer built."
