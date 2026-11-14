#!/usr/bin/env python3
"""
The agent's access to its knowledge store (relate): retrieval, schema context, and the learning loop.

Retrieval -- up to four ranked lists, blended on normalized scores:
  1. full-text (BM25) over QueryTemplate title/description/name                           weight 1.0
  2. vector search over template embeddings (only if the store was built with embeddings)  weight VECTOR_WEIGHT
  3. past questions: full-text over Interaction.question -> the templates those questions
     USED or CREATED (the store learns which template answered which question)             weight HISTORY_WEIGHT
  4. concept graph: full-text over the ontology, then traversal to templates that USE /
     TRAVERSE the matched concepts, scored by specificity                                   weight GRAPH_WEIGHT

Learning loop (writes; the store must be opened with read_only=False, and relate allows one writing process):
  start_interaction / finish_interaction   provenance: (:Interaction)-[:USED|CREATED]->(:QueryTemplate)
  record_use                               useCount / lastUsed on a template, USED edge from the interaction
  save_template                            a new, user-approved template (source 'agent'), linked and embedded

Usage:
  python kb/kb_query.py search "which suppliers get their quotes rejected most?"
  python kb/kb_query.py schema PurchaseOrder RFQ
  python kb/kb_query.py fullschema
  python kb/kb_query.py learned
"""
from __future__ import annotations

import re
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import relate  # noqa: E402

from embeddings import get_embedder  # noqa: E402
from kb_write import add_template, embed_templates, link_workflows, load_semantics, schema_names, slug, unique_name  # noqa: E402

DEFAULT_STORE = Path(__file__).resolve().parent / "northwind_kb.rl"
GRAPH_WEIGHT = 0.35
VECTOR_WEIGHT = 0.8
HISTORY_WEIGHT = 0.6


def _fulltext_terms(text: str) -> str:
    """Plain words only, so punctuation in a user's question can't break the full-text query syntax."""
    return " ".join(re.findall(r"[A-Za-z0-9]+", text))


def _normalized(rows: list[dict], minmax: bool = False) -> dict[str, float]:
    """name -> score in [0, 1]. Max-normalized (BM25-like scores) or min-max (cosine scores bunch together)."""
    if not rows:
        return {}
    scores = [r["score"] for r in rows]
    hi, lo = max(scores), (min(scores) if minmax and len(rows) > 1 else 0.0)
    span = (hi - lo) or 1.0
    return {r["name"]: (r["score"] - lo) / span for r in rows}


class KnowledgeBase:
    def __init__(self, store: Path | str = DEFAULT_STORE, read_only: bool = True, embedder="auto"):
        self.conn = relate.connect(str(store), read_only=read_only)
        meta = self.conn.execute("MATCH (k:KnowledgeBase) RETURN properties(k) AS k").single()["k"]
        self.ontology_version = meta.get("ontologyVersion")
        self.embedding_model = meta.get("embeddingModel") or "none"
        # The query embedder must match the one the store was built with.
        if embedder == "auto":
            embedder = get_embedder(self.embedding_model) if self.embedding_model != "none" else None
        self.embedder = embedder
        self._sem = None

    def close(self):
        self.conn.close()

    def _rows(self, q: str, p: dict | None = None) -> list[dict]:
        return [dict(r) for r in self.conn.execute(q, p or {})]

    # ---------------- retrieval ----------------

    def search_templates(self, question: str, k: int = 5, include_simulation: bool = False,
                         candidates: int = 15, explain: bool = False) -> list[dict]:
        terms = _fulltext_terms(question)
        if not terms:
            return []
        govern = ["read", "governed"] + (["simulation"] if include_simulation else [])
        lists: dict[str, tuple[dict, float]] = {}

        direct = self._rows("""
            MATCH (q:QueryTemplate)
            SEARCH q IN (FULLTEXT INDEX template_text FOR $terms LIMIT $n) SCORE AS score
            RETURN q.name AS name, score""", {"terms": terms, "n": candidates})
        lists["fulltext"] = (_normalized(direct), 1.0)

        if self.embedder:
            vec = self._rows("""
                MATCH (q:QueryTemplate)
                SEARCH q IN (VECTOR INDEX template_vec FOR $v LIMIT $n) SCORE AS score
                RETURN q.name AS name, score""", {"v": self.embedder.embed_query(question), "n": candidates})
            lists["vector"] = (_normalized(vec, minmax=True), VECTOR_WEIGHT)

        history = self._rows("""
            MATCH (i:Interaction)
            SEARCH i IN (FULLTEXT INDEX interaction_text FOR $terms LIMIT $n) SCORE AS score
            MATCH (i)-[:USED|CREATED]->(q:QueryTemplate)
            RETURN q.name AS name, max(score) AS score""", {"terms": terms, "n": candidates})
        lists["history"] = (_normalized(history), HISTORY_WEIGHT)

        concepts = self._rows("""
            CALL () {
              MATCH (c:NodeType) SEARCH c IN (FULLTEXT INDEX nodetype_text FOR $terms LIMIT $n) SCORE AS score
              RETURN c.name AS concept, score
              UNION ALL
              MATCH (c:RelType) SEARCH c IN (FULLTEXT INDEX reltype_text FOR $terms LIMIT $n) SCORE AS score
              RETURN c.name AS concept, score
            }
            RETURN concept, score ORDER BY score DESC LIMIT $n""", {"terms": terms, "n": candidates})
        if concepts:
            weights = {c["concept"]: 1.0 / (60 + i + 1) for i, c in enumerate(concepts)}
            via_graph = self._rows("""
                UNWIND $names AS cname
                MATCH (q:QueryTemplate)-[:USES|TRAVERSES]->(c) WHERE c.name = cname
                WITH q, collect(DISTINCT cname) AS matched
                RETURN q.name AS name, matched, COUNT { (q)-[:USES|TRAVERSES]->() } AS size""",
                                   {"names": list(weights)})
            for row in via_graph:   # specificity: touching everything shouldn't win
                row["score"] = sum(weights[c] for c in row["matched"]) / (max(row["size"], 1) ** 0.5)
            lists["graph"] = (_normalized(via_graph), GRAPH_WEIGHT)

        fused: dict[str, float] = {}
        parts: dict[str, dict] = {}
        for label, (scores, weight) in lists.items():
            for name, s in scores.items():
                fused[name] = fused.get(name, 0.0) + weight * s
                parts.setdefault(name, {})[label] = round(s, 2)
        if not fused:
            return []

        details = self._rows("""
            UNWIND $names AS n
            MATCH (q:QueryTemplate {name:n}) WHERE q.governance IN $govern AND coalesce(q.status, 'seed') <> 'needs-review'
            OPTIONAL MATCH (q)-[:PART_OF]->(w:WorkflowStep)
            RETURN q.name AS name, q.title AS title, q.description AS description, q.governance AS governance,
                   q.kind AS kind, q.params AS params, q.cypher AS cypher, q.source AS source,
                   coalesce(q.useCount, 0) AS useCount, collect(DISTINCT w.name) AS workflow""",
                             {"names": list(fused), "govern": govern})
        for d in details:
            d["score"] = round(fused[d["name"]], 3)
            if explain:
                d["why"] = parts[d["name"]]
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

    # ---------------- learning loop (writes) ----------------

    def start_interaction(self, question: str, employee_id: str, model: str) -> str:
        iid = "I-" + uuid.uuid4().hex[:12]
        self.conn.execute("""CREATE (:Interaction {id:$id, question:$q, employeeId:$e, model:$m,
                                                   ontologyVersion:$v, startedAt:datetime()})""",
                          {"id": iid, "q": question, "e": employee_id, "m": model, "v": self.ontology_version})
        return iid

    def finish_interaction(self, iid: str, answer: str, usage: dict, new_queries: int):
        self.conn.execute("""MATCH (i:Interaction {id:$id})
                             SET i.answer = $a, i.finishedAt = datetime(), i.newQueries = $nq,
                                 i.modelCalls = $mc, i.inputTokens = $it, i.outputTokens = $ot,
                                 i.cacheReadTokens = $cr""",
                          {"id": iid, "a": answer, "nq": new_queries, "mc": usage.get("model_calls", 0),
                           "it": usage.get("input_tokens", 0), "ot": usage.get("output_tokens", 0),
                           "cr": usage.get("cache_read_input_tokens") or 0})

    def record_use(self, iid: str, template_name: str) -> bool:
        rows = self._rows("""MATCH (i:Interaction {id:$id}), (q:QueryTemplate {name:$n})
                             SET q.useCount = coalesce(q.useCount, 0) + 1, q.lastUsed = datetime()
                             MERGE (i)-[:USED]->(q)
                             RETURN q.name AS n""", {"id": iid, "n": template_name})
        return bool(rows)

    def save_template(self, iid: str, title: str, description: str, cypher: str, employee_id: str,
                      question: str) -> dict:
        if self._sem is None:
            self._sem = load_semantics()
        labels, rel_types = schema_names(self.conn)
        name = unique_name(self.conn, slug(title) or "agent_query")
        t = add_template(self.conn, {
            "name": name, "title": title, "description": description, "cypher": cypher.strip(),
            "kind": "read", "governance": "read", "source": "agent", "status": "approved",
            "ontologyVersion": self.ontology_version, "createdBy": employee_id, "question": question,
        }, labels, rel_types)
        link_workflows(self.conn, self._sem, name)
        if self.embedder:
            embed_templates(self.conn, self.embedder, name)
        self.conn.execute("MATCH (i:Interaction {id:$id}), (q:QueryTemplate {name:$n}) CREATE (i)-[:CREATED]->(q)",
                          {"id": iid, "n": name})
        workflows = [r["w"] for r in self._rows(
            "MATCH (:QueryTemplate {name:$n})-[:PART_OF]->(w) RETURN w.name AS w", {"n": name})]
        return {"name": name, "labels": t["labels"], "rels": t["rels"], "workflow": workflows}

    def learned(self) -> list[dict]:
        return self._rows("""
            MATCH (q:QueryTemplate {source:'agent'})
            OPTIONAL MATCH (i:Interaction)-[:USED]->(q)
            RETURN q.title AS title, q.status AS status, q.createdBy AS createdBy, coalesce(q.useCount, 0) AS uses,
                   q.question AS firstQuestion, count(i) AS reusedBy ORDER BY uses DESC""")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return
    kb = KnowledgeBase()
    cmd = argv[1]
    if cmd == "search":
        for t in kb.search_templates(" ".join(argv[2:]), explain=True):
            print(f"{t['score']:>6}  [{t['governance']}] {t['title'][:80]}  {t['why']}")
    elif cmd == "schema":
        print(kb.schema_for(argv[2:]))
    elif cmd == "fullschema":
        print(kb.full_schema())
    elif cmd == "learned":
        for t in kb.learned():
            print(t)
    else:
        print(__doc__)
    kb.close()


if __name__ == "__main__":
    main(sys.argv)
