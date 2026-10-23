# Quine Tap Queries API (agent reference)

Tap queries are saved "wiretap + Cypher query" pairs that drive the Exploration UI's live graph feeds. Each one taps the result stream of a standing query (SQ) and runs a read-only Cypher query in the browser for every match; whatever nodes the query returns are drawn on the canvas in real time. They are UI configuration only — nothing runs server-side until a user enables the tap's feed chip in the Explorer.

## Endpoints

Both are graph-scoped (a tap query targets an SQ that exists in exactly one graph/namespace):

```
GET /api/v2/graph/{graph}/queryUi/tapQueries   -> 200, JSON array of TapQuery
PUT /api/v2/graph/{graph}/queryUi/tapQueries   -> 204 on success, 400 on invalid query
```

- `{graph}` is the graph (namespace) name; the default graph is `quine`.
- **PUT replaces the entire list for that graph.** To add one, GET first, append, PUT the merged array. PUT an empty array `[]` to clear all.
- Body may be JSON or YAML (Content-Type `application/json` or `application/yaml`).
- Requests are atomic: if any tap query in the array fails validation, the whole PUT is rejected with 400 and nothing is saved.

## TapQuery object

| Field | Type | Required | Meaning |
|---|---|---|---|
| `name` | string | yes | Display name, unique key in the UI (Explorer Settings, feed chips). |
| `description` | string or null | no | Longer description shown in Explorer Settings. |
| `standingQueryName` | string | yes | Name of the SQ to tap. Not validated against existing SQs — an orphan tap query simply produces no feed. |
| `outputName` | string or null | no | Null/omitted = tap the SQ's **raw match stream** (positive/negative results before any output workflow). Set to an output workflow name to tap that output's stream instead. |
| `preEnrichment` | boolean | no (default `false`) | Only meaningful when `outputName` is set: `true` taps the output's stream *before* its enrichment query runs, `false` after. Ignored for raw taps. |
| `query` | string | yes | Cypher run in the browser for each incoming wiretap message. Must compile and be **read-only** (see Validation). |
| `syntheticEdges` | array | no (default `[]`) | Visual-only edges drawn between node IDs read from the wiretap message (see below). |

## Query parameters available in `query`

Each wiretap message is a JSON envelope; its **top-level fields become Cypher parameters**. For a raw SQ tap the envelope is:

```json
{ "meta": { "isPositiveMatch": true, ... }, "data": { "<sq-return-column>": ... } }
```

So the query references:

- `$data.<column>` — the SQ's RETURN columns (e.g. an SQ returning `id(n) AS numberId` gives `$data.numberId`)
- `$meta.isPositiveMatch` — true for new matches, false for cancellations

Values flow through the Cypher parameter map (no string interpolation, no injection risk). Typical shape:

```cypher
MATCH (n) WHERE id(n) = $data.numberId RETURN n
```

Only nodes returned by the query are rendered; you can filter (`AND n.number % 2 = 0`) or traverse from the matched node before returning.

## Validation (PUT-time)

Every query in the array is compiled with its `$`-referenced parameters declared. Rejected with 400 (nothing saved) if:

- the query does not compile (syntax/semantic error), or
- it has write effects: CREATE, MERGE, SET, DELETE, DETACH DELETE, REMOVE, or a writing procedure. Tap queries are projections — observe and draw only.

The 400 body names the offending tap query and the reason.

## syntheticEdges (optional)

Draw a visual-only edge (not persisted in the graph) between two nodes whose IDs appear in the wiretap message:

```json
{
  "fromNode": "data.even1",
  "toNode": "data.even2",
  "label": "consecutive-even",
  "direction": "OUT",
  "nodeIdsFrom": "WIRETAP_MESSAGE"
}
```

- `fromNode` / `toNode`: dot-paths into the message JSON envelope.
- `direction`: `"OUT"` (from→to), `"IN"` (to→from), or `"UNDIRECTED"`.
- `nodeIdsFrom`: only `"WIRETAP_MESSAGE"` currently.

## Runtime behavior (what saving does and does not do)

- Saving tap queries only stores definitions. A tap opens (websocket wiretap on the SQ stream) when a user toggles the feed chip on in the Explorer UI; results then stream onto the canvas.
- Editing a saved tap query's `query`/`syntheticEdges` applies live to an open tap; changing its tap point (`standingQueryName`/`outputName`/`preEnrichment`) reopens the tap.
- Deleting a tap query (PUT without it) closes its tap and drops the user's opt-in; recreating it later starts disabled.

## Example curls

Replace the list with one tap query on the raw matches of SQ `numbers-enriched`:

```bash
curl -sS -w '\nHTTP %{http_code}\n' -X PUT \
  http://localhost:8080/api/v2/graph/quine/queryUi/tapQueries \
  -H 'Content-Type: application/json' \
  -d '[
    {
      "name": "even-number-nodes",
      "description": "Show even Number nodes as the standing query matches them.",
      "standingQueryName": "numbers-enriched",
      "outputName": null,
      "preEnrichment": false,
      "query": "MATCH (n) WHERE id(n) = $data.numberId AND n.number % 2 = 0 RETURN n"
    }
  ]'
# -> HTTP 204
```

Read the current list (also the merge source before any PUT):

```bash
curl -sS http://localhost:8080/api/v2/graph/quine/queryUi/tapQueries | jq .
```

Append without clobbering (merge pattern):

```bash
existing=$(curl -sS http://localhost:8080/api/v2/graph/quine/queryUi/tapQueries)
new='{"name":"odd-number-nodes","standingQueryName":"numbers-enriched","query":"MATCH (n) WHERE id(n) = $data.numberId AND n.number % 2 <> 0 RETURN n"}'
curl -sS -X PUT http://localhost:8080/api/v2/graph/quine/queryUi/tapQueries \
  -H 'Content-Type: application/json' \
  -d "$(jq -c --argjson n "$new" '. + [$n]' <<<"$existing")"
```

Clear all tap queries for the graph:

```bash
curl -sS -X PUT http://localhost:8080/api/v2/graph/quine/queryUi/tapQueries \
  -H 'Content-Type: application/json' -d '[]'
```

## Agent checklist

1. GET the current list first; PUT replaces everything.
2. `standingQueryName` must match an existing SQ for the feed to produce anything (create the SQ first; no error if it is missing).
3. Reference SQ columns as `$data.<column>`; use `$meta.isPositiveMatch` to distinguish matches from cancellations.
4. Query must be read-only and compile, or the whole PUT 400s.
5. Expect 204 with empty body on success; verify with a follow-up GET.
6. Tap queries render in the UI only after a user enables the feed chip — saving alone shows nothing on the canvas.
