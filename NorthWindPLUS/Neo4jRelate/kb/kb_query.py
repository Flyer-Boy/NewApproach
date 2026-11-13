#!/usr/bin/env python3
"""
Read side of the agent's knowledge store: what the agent calls to find templates and schema context.

Retrieval (no embeddings yet):
  1. Full-text (BM25) over QueryTemplate title/description/name.
  2. Full-text over the ontology (NodeType / RelType names and descriptions), then graph traversal from the
     matching concepts to every template that USES / TRAVERSES them.
  The two ranked lists are fused with reciprocal rank fusion (RRF). Embeddings will be added later as a
  third list, without changing the callers.

Usage:
  python kb/kb_query.py search "which suppliers get their quotes rejected most?"
  python kb/kb_query.py schema PurchaseOrder RFQ
  python kb/kb_query.py fullschema
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import relate

DEFAULT_STORE = Path(__file__).resolve().parent / "northwind_kb.rl"
RRF_K = 60
GRAPH_WEIGHT = 0.35  # how much the concept-traversal list counts next to a direct full-text hit on the template


def _fulltext_terms(text: str) -> str:
    """Plain words only, so punctuation in a user's question can't break the full-text query syntax."""
    return " ".join(re.findall(r"[A-Za-z0-9]+", text))


class KnowledgeBase:
    def __init__(self, store: Path | str = DEFAULT_STORE):
        self.conn = relate.connect(str(store), read_only=True)

    def close(self):
        self.conn.close()

    def _rows(self, q: str, p: dict | None = None) -> list[dict]:
        return [dict(r) for r in self.conn.execute(q, p or {})]

    # ---------------- retrieval ----------------

    def search_templates(self, question: str, k: int = 5, include_simulation: bool = False,
                         candidates: int = 15) -> list[dict]:
        terms = _fulltext_terms(question)
        if not terms:
            return []
        govern = ["read", "governed"] + (["simulation"] if include_simulation else [])

        direct = self._rows("""
            MATCH (q:QueryTemplate)
            SEARCH q IN (FULLTEXT INDEX template_text FOR $terms LIMIT $n) SCORE AS score
            RETURN q.name AS name, score ORDER BY score DESC""", {"terms": terms, "n": candidates})

        concepts = self._rows("""
            CALL () {
              MATCH (c:NodeType) SEARCH c IN (FULLTEXT INDEX nodetype_text FOR $terms LIMIT $n) SCORE AS score
              RETURN c.name AS concept, score
              UNION ALL
              MATCH (c:RelType) SEARCH c IN (FULLTEXT INDEX reltype_text FOR $terms LIMIT $n) SCORE AS score
              RETURN c.name AS concept, score
            }
            RETURN concept, score ORDER BY score DESC LIMIT $n""", {"terms": terms, "n": candidates})

        via_graph = []
        if concepts:
            weights = {c["concept"]: 1.0 / (RRF_K + i + 1) for i, c in enumerate(concepts)}
            via_graph = self._rows("""
                UNWIND $names AS cname
                MATCH (q:QueryTemplate)-[:USES|TRAVERSES]->(c) WHERE c.name = cname
                WITH q, collect(DISTINCT cname) AS matched
                RETURN q.name AS name, matched, COUNT { (q)-[:USES|TRAVERSES]->() } AS size""",
                                   {"names": list(weights)})
            # Specificity: a template touching 20 concepts shouldn't win just because it touches everything.
            for row in via_graph:
                row["score"] = sum(weights[c] for c in row["matched"]) / (max(row["size"], 1) ** 0.5)
            via_graph.sort(key=lambda r: r["score"], reverse=True)

        # Blend normalized scores: direct full-text leads; the concept graph re-orders near-ties and adds
        # candidates the wording missed, but can't outvote a strong direct match.
        fused: dict[str, float] = {}
        for ranked, weight in ((direct, 1.0), (via_graph, GRAPH_WEIGHT)):
            top = max((r["score"] for r in ranked), default=0) or 1.0
            for row in ranked:
                fused[row["name"]] = fused.get(row["name"], 0.0) + weight * row["score"] / top
        if not fused:
            return []

        details = self._rows("""
            UNWIND $names AS n
            MATCH (q:QueryTemplate {name:n}) WHERE q.governance IN $govern
            OPTIONAL MATCH (q)-[:PART_OF]->(w:WorkflowStep)
            RETURN q.name AS name, q.title AS title, q.description AS description, q.governance AS governance,
                   q.kind AS kind, q.params AS params, q.cypher AS cypher, collect(DISTINCT w.name) AS workflow""",
                             {"names": list(fused), "govern": govern})
        for d in details:
            d["score"] = round(fused[d["name"]], 3)
        details.sort(key=lambda d: d["score"], reverse=True)
        return details[:k]

    def get_template(self, name: str) -> dict | None:
        rows = self._rows("MATCH (q:QueryTemplate {name:$n}) RETURN properties(q) AS q", {"n": name})
        return rows[0]["q"] if rows else None

    def template_by_title(self, title_prefix: str) -> dict:
        """Exactly one template whose title starts with title_prefix (used for the fixed, governed tools)."""
        rows = self._rows("MATCH (q:QueryTemplate) WHERE q.title STARTS WITH $p RETURN properties(q) AS q",
                          {"p": title_prefix})
        if len(rows) != 1:
            raise LookupError(f"Expected one template titled '{title_prefix}...', found {len(rows)}. Rebuild the store?")
        return rows[0]["q"]

    # ---------------- schema context ----------------

    def principles(self) -> list[str]:
        return [r["t"] for r in self._rows("MATCH (p:ModelPrinciple) RETURN p.text AS t ORDER BY p.rank")]

    def schema_for(self, labels: list[str]) -> str:
        """Compact schema text for the given node types: description, properties, and every relationship in or out."""
        out = []
        for row in self._rows("""
            UNWIND $labels AS l
            MATCH (n:NodeType {name:l})
            OPTIONAL MATCH (n)-[:HAS_PROPERTY]->(p:Property)
            WITH n, collect(p.name + ' ' + p.type + CASE WHEN p.notNull THEN ' NOT NULL' ELSE '' END
                            + CASE WHEN p.isKey THEN ' KEY' ELSE '' END) AS props
            OPTIONAL MATCH (n)-[:SOURCE_OF]->(o:RelType)
            WITH n, props, collect(o.pattern) AS outgoing
            OPTIONAL MATCH (i:RelType)-[:TARGETS]->(n)
            RETURN n.name AS name, n.category AS category, n.description AS description,
                   props, outgoing, collect(i.pattern) AS incoming""", {"labels": labels}):
            out.append(f"{row['name']} ({row['category']}): {row['description']}\n"
                       f"  properties: {', '.join(row['props']) or '-'}\n"
                       f"  out: {'; '.join(row['outgoing']) or '-'}\n"
                       f"  in:  {'; '.join(row['incoming']) or '-'}")
        return "\n".join(out)

    def full_schema(self) -> str:
        """The whole ontology as compact text -- small enough to keep in the agent's (cached) system prompt."""
        lines = ["# Node types"]
        for r in self._rows("""
            MATCH (n:NodeType) OPTIONAL MATCH (n)-[:HAS_PROPERTY]->(p:Property)
            WITH n, collect(p.name + ':' + p.type + CASE WHEN p.isKey THEN ' KEY' ELSE '' END) AS props
            RETURN n.name AS name, n.category AS cat, n.description AS d, props ORDER BY cat DESC, name"""):
            lines.append(f"- {r['name']} [{r['cat']}] {{{', '.join(r['props'])}}} -- {r['d']}")
        lines.append("\n# Relationship types")
        for r in self._rows("""
            MATCH (t:RelType) OPTIONAL MATCH (t)-[:HAS_PROPERTY]->(p:Property)
            WITH t, collect(p.name + ':' + p.type) AS props
            RETURN t.pattern AS pat, t.description AS d, props ORDER BY pat"""):
            props = f" {{{', '.join(r['props'])}}}" if r["props"] else ""
            desc = f" -- {r['d']}" if r["d"] else ""
            lines.append(f"- {r['pat']}{props}{desc}")
        lines.append("\n# Workflow steps")
        for r in self._rows("MATCH (w:WorkflowStep) RETURN w.name AS n, w.description AS d ORDER BY n"):
            lines.append(f"- {r['n']}: {r['d']}")
        return "\n".join(lines)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return
    kb = KnowledgeBase()
    cmd = argv[1]
    if cmd == "search":
        for t in kb.search_templates(" ".join(argv[2:])):
            print(f"{t['score']:>6}  [{t['governance']}] {t['title']}  {t['workflow']}  params={t['params']}")
    elif cmd == "schema":
        print(kb.schema_for(argv[2:]))
    elif cmd == "fullschema":
        print(kb.full_schema())
    else:
        print(__doc__)
    kb.close()


if __name__ == "__main__":
    main(sys.argv)
