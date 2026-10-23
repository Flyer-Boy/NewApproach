#!/usr/bin/env bash
# NorthWindPLUS on Quine — Docker version of run-demo.sh (Windows + WSL + Docker Desktop).
#
#   ./run-demo-docker.sh                 run ONE day (300 ticks, ~5 min), then leave
#                                        the graph up for exploration until Ctrl-C.
#   ./run-demo-docker.sh --loop          a fresh day every ~5.5 min until Ctrl-C.
#   ./run-demo-docker.sh --port N        host port for the UI/API (default 8080).
#   ./run-demo-docker.sh --image TAG     Quine image (default thatdot/quine:latest).
#
# Differences from the original run-demo.sh:
#   - starts Quine in a Docker container instead of `java -jar` (no resolve-jar.sh needed)
#   - reads alerts from `docker logs` instead of a local quine.log
#   - each day's artefacts go to their own folder under ./.run/ (files the container
#     writes are owned by root, so they are not wiped automatically)
#
# Needs in WSL: docker (Docker Desktop with WSL integration on), curl, python3.
# Stop any other Quine container using the same port first.

set -uo pipefail

PORT=8080
LOOP=0
IMAGE="${QUINE_IMAGE:-thatdot/quine:latest}"
NAME="northwind-quine"
while [ $# -gt 0 ]; do
  case "$1" in
    --loop)  LOOP=1; shift ;;
    --port)  PORT="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
RECIPE_FILE="northwind-plus-streaming.yaml"
FEEDS="$HERE/feeds.json"
API="http://localhost:${PORT}/api/v2/graph/quine"
UI="http://localhost:${PORT}"
DAY_TICKS=300
ALERTS='\[(LOW STOCK|RESTOCKED|RECOMMEND|AUTO-RESUBMIT|PO CLOSED|SHIPPED|TIER|BACKORDER|RELEASED)\][^"]*'

# --- preflight ---------------------------------------------------------------
[ -r "$HERE/$RECIPE_FILE" ] || { echo "ERROR: missing $HERE/$RECIPE_FILE" >&2; exit 1; }
for cmd in docker curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' not found in WSL" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || {
  echo "ERROR: cannot talk to Docker. Is Docker Desktop running, with WSL integration" >&2
  echo "       enabled for this distro (Settings > Resources > WSL integration)?" >&2
  exit 1; }

LPID=""; TPID=""
cleanup() {
  [ -n "$TPID" ] && kill "$TPID" 2>/dev/null
  [ -n "$LPID" ] && kill "$LPID" 2>/dev/null
  docker rm -f "$NAME" >/dev/null 2>&1
  wait 2>/dev/null
}
trap 'echo; echo ">>> stopping"; cleanup; exit 0' INT TERM

running() { [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ]; }

tally() {
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
print("PENDING" if pending else "DONE")' 2>/dev/null
}

DAY=0
while :; do
  DAY=$((DAY + 1))
  RUN="$HERE/.run/$(date +%Y%m%d-%H%M%S)-day${DAY}"
  mkdir -p "$RUN"

  echo
  echo "================================================================"
  echo "  NorthWindPLUS — DAY ${DAY}   (image ${IMAGE}, ${DAY_TICKS} ticks at 1/s)"
  echo "================================================================"

  docker rm -f "$NAME" >/dev/null 2>&1
  # The folder is mounted at /demo; the container's working dir is today's run
  # folder so the recipe's shipped-orders.jsonl lands there.
  REL_RUN="${RUN#"$HERE"/}"
  if ! docker run -d --name "$NAME" -p "${PORT}:8080" \
        -v "$HERE":/demo -w "/demo/${REL_RUN}" \
        "$IMAGE" -r "/demo/${RECIPE_FILE}" >/dev/null; then
    echo "ERROR: docker run failed (port ${PORT} already in use by another container?)" >&2
    exit 1
  fi
  docker logs -f "$NAME" > "$RUN/quine.log" 2>&1 &
  LPID=$!

  # --- wait for the API, fail fast if the recipe does not load ---------------
  for _ in $(seq 1 90); do
    curl -sf -m 3 "${API}/ingests" >/dev/null 2>&1 && break
    if ! running; then
      echo "ERROR: Quine container exited during startup. Last log lines:" >&2
      tail -15 "$RUN/quine.log" >&2
      cleanup; exit 1
    fi
    if grep -qaE "Failed creating Standing Query|Exception in thread .main.|DecodingFailure" "$RUN/quine.log"; then
      echo "ERROR: recipe failed to load — see $RUN/quine.log" >&2
      grep -aE "Failed creating Standing Query|CypherException|DecodingFailure" "$RUN/quine.log" | head -5 | cut -c1-300 >&2
      cleanup; exit 1
    fi
    sleep 1
  done
  if ! curl -sf -m 5 "${API}/ingests" >/dev/null 2>&1; then
    echo "ERROR: ${API}/ingests never answered." >&2
    echo "       If the UI loads but this endpoint 404s, the image is probably a Quine" >&2
    echo "       version without the v2 API this recipe was built for (2.1.0)." >&2
    echo "       Last log lines:" >&2
    tail -15 "$RUN/quine.log" >&2
    cleanup; exit 1
  fi

  # --- graph feeds ------------------------------------------------------------
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

  tail -n +1 -F "$RUN/quine.log" 2>/dev/null | grep --line-buffered -oE "$ALERTS" &
  TPID=$!

  # --- wait for every stream to finish -----------------------------------------
  DONE=0
  for _ in $(seq 1 $((DAY_TICKS + 120))); do
    running || { echo "ERROR: Quine container exited mid-day — see $RUN/quine.log" >&2; cleanup; exit 1; }
    [ "$(ingest_state)" = "DONE" ] && { DONE=1; break; }
    sleep 2
  done
  sleep 3
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
    echo "  The graph is now still. Explore it at ${UI} — Ctrl-C to stop (removes the container)."
    docker wait "$NAME" >/dev/null 2>&1
    cleanup
    exit 0
  fi

  echo "  next day starts in 20 s (fresh graph) — Ctrl-C to stop"
  sleep 20
  kill "$LPID" 2>/dev/null; LPID=""
  docker rm -f "$NAME" >/dev/null 2>&1
  sleep 2
done
