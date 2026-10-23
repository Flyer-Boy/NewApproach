#!/usr/bin/env bash
# NorthWindPLUS on Quine — one business day in five minutes.
#
#   ./run-demo.sh            run ONE day (300 ticks, ~5 min). When the streams
#                            finish, the graph sits still for inspection until
#                            you press Ctrl-C.
#   ./run-demo.sh --loop     run a day, print the day's tally, restart with a
#                            fresh graph, repeat until Ctrl-C.
#   ./run-demo.sh --port N   serve the UI/API on another port (default 8080).
#
# Each day is a fresh JVM: this jar keeps its graph in memory, so a restart IS
# the reset. Nothing is deleted from a running graph — rule 4 holds inside
# every day. Run artefacts (quine.log, shipped-orders.jsonl) land in ./.run/
# and are wiped at the start of each day.
#
# This script computes nothing. It starts Quine, arms the graph feeds through
# Quine's own tap-query API, and polls Quine's ingest status. Every alert,
# recommendation, resubmission, invoice and promotion is produced by the
# standing queries in the recipe.

set -uo pipefail

PORT=8080
LOOP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --loop) LOOP=1; shift ;;
    --port) PORT="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$HERE/../.." && pwd)"              # Outbound Campaign Working File/
RECIPE="$HERE/northwind-plus-streaming.yaml"
FEEDS="$HERE/feeds.json"
RUN="$HERE/.run"
API="http://localhost:${PORT}/api/v2/graph/quine"
UI="http://localhost:${PORT}"
DAY_TICKS=300
ALERTS='\[(LOW STOCK|RESTOCKED|RECOMMEND|AUTO-RESUBMIT|PO CLOSED|SHIPPED|TIER|BACKORDER|RELEASED)\][^"]*'

[ -r "$RECIPE" ] || { echo "ERROR: missing $RECIPE" >&2; exit 1; }
source "$PROJECT/_engine/resolve-jar.sh" || exit 1

QPID=""; TPID=""
cleanup() {
  [ -n "$TPID" ] && kill "$TPID" 2>/dev/null
  [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
  wait 2>/dev/null
}
trap 'echo; echo ">>> stopping"; cleanup; exit 0' INT TERM

tally() {
  # per-family alert counts from today's log
  for k in "LOW STOCK" "RESTOCKED" "RECOMMEND" "AUTO-RESUBMIT" "PO CLOSED" "BACKORDER" "RELEASED" "SHIPPED" "TIER"; do
    printf '    %-14s %5d\n' "$k" "$(grep -c "\[$k\]" "$RUN/quine.log")"
  done
}

ingest_state() {
  curl -sf -m 10 "${API}/ingests" 2>/dev/null | python3 -c '
import json, sys
try: items = json.load(sys.stdin)["items"]
except Exception: sys.exit(1)
if not items: sys.exit(1)
pending = [i["name"] for i in items if i["status"] != "COMPLETED"]
done = max((i.get("stats", {}).get("ingestedCount", 0) for i in items if i["name"] == "sales"), default=0)
print(("PENDING:%d" % done) if pending else "DONE")' 2>/dev/null
}

DAY=0
while :; do
  DAY=$((DAY + 1))
  rm -rf "$RUN"; mkdir -p "$RUN"; cd "$RUN" || exit 1

  echo
  echo "================================================================"
  echo "  NorthWindPLUS — DAY ${DAY}   (Quine ${QUINE_VERSION}, ${DAY_TICKS} ticks at 1/s)"
  echo "================================================================"
  java -jar "$QUINE_JAR" -r "$RECIPE" -p "$PORT" > quine.log 2>&1 &
  QPID=$!

  for _ in $(seq 1 90); do
    curl -sf -m 3 "${API}/ingests" >/dev/null 2>&1 && break
    kill -0 "$QPID" 2>/dev/null || { echo "ERROR: Quine exited during startup — see $RUN/quine.log" >&2; tail -5 quine.log >&2; exit 1; }
    # a Cypher compile error in a standing query kills the main thread but not
    # the JVM, and the API never comes up — fail fast and show it
    if grep -qaE "Failed creating Standing Query|Exception in thread .main.|DecodingFailure" quine.log; then
      echo "ERROR: recipe failed to load — see $RUN/quine.log" >&2
      grep -aE "Failed creating Standing Query|CypherException|DecodingFailure" quine.log | head -5 | cut -c1-300 >&2
      cleanup; exit 1
    fi
    sleep 1
  done
  curl -sf -m 5 "${API}/ingests" >/dev/null 2>&1 || { echo "ERROR: API never came up on port ${PORT}" >&2; cleanup; exit 1; }

  # graph feeds: draw each standing-query match on the canvas as it fires.
  # Saving arms nothing visually — toggle a feed's chip in the Exploration UI.
  if [ -f "$FEEDS" ]; then
    HTTP=$(curl -s -m 30 -o /dev/null -w '%{http_code}' -X PUT "${API}/queryUi/tapQueries" \
           -H 'Content-Type: application/json' --data-binary @"$FEEDS")
    if [ "$HTTP" = "204" ] || [ "$HTTP" = "200" ]; then
      echo "  graph feeds armed: $(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$FEEDS") (toggle their chips in the Exploration UI)"
    else
      echo "  ! graph feeds not armed (HTTP ${HTTP}) — continuing without the live canvas" >&2
    fi
  fi

  echo "  UI:   ${UI}"
  echo "  log:  ${RUN}/quine.log"
  echo "  start with sample query 1, then 3 (inventory) and 2 (where is everything)"
  echo "----------------------------------------------------------------"

  tail -n +1 -F quine.log 2>/dev/null | grep --line-buffered -oE "$ALERTS" &
  TPID=$!

  # wait for every stream to finish its 300 ticks
  DONE=0
  for _ in $(seq 1 $((DAY_TICKS + 120))); do
    kill -0 "$QPID" 2>/dev/null || { echo "ERROR: Quine exited mid-day — see $RUN/quine.log" >&2; cleanup; exit 1; }
    case "$(ingest_state)" in
      DONE) DONE=1; break ;;
    esac
    sleep 2
  done
  sleep 3   # let the last standing-query fires print
  kill "$TPID" 2>/dev/null; TPID=""

  echo "----------------------------------------------------------------"
  if [ "$DONE" = 1 ]; then
    echo "  END OF DAY ${DAY} — every stream completed. Today the twin fired:"
  else
    echo "  DAY ${DAY} — streams did not all complete in time; tally so far:"
  fi
  tally
  echo "  shipped ledger: ${RUN}/shipped-orders.jsonl ($(wc -l < "$RUN/shipped-orders.jsonl" 2>/dev/null || echo 0) lines)"

  if [ "$LOOP" = 0 ]; then
    echo
    echo "  The graph is now still. Explore it at ${UI} — Ctrl-C to stop."
    wait "$QPID"
    exit 0
  fi

  echo "  next day starts in 20 s (fresh graph) — Ctrl-C to stop"
  sleep 20
  kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; QPID=""
  sleep 2
done
