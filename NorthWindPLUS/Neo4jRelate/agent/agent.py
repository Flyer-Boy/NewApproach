#!/usr/bin/env python3
"""
NorthWind PLUS business agent: answers questions about the live simulation on Neo4j Aura, using the relate
knowledge store (ontology + proven Cypher templates) to find or write the right query.

  python agent/agent.py --as-employee 25            # Olivia Bennett, ProcurementPolicyAdmin
  python agent/agent.py --as-employee 12            # Gloria Gaynor, Level1Approver (can ask, can't change bands)
  python agent/agent.py --as-employee 25 --model claude-opus-5-5

--as-employee stands in for a real login: it decides who the user is. The model never does.

Needs (e.g. in the project's .env): ANTHROPIC_API_KEY, NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD, NEO4J_DATABASE.
Every tool call is logged to agent/logs/ as JSON lines.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path

import anthropic
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "kb"))
sys.path.insert(0, str(ROOT / "agent"))
from kb_query import KnowledgeBase  # noqa: E402
from aura import Aura               # noqa: E402

DEFAULT_MODEL = "claude-sonnet-5-5"
MAX_ROWS_TO_MODEL = 50
POLICY_TEMPLATE_TITLE = "Change the approval bands (governed)"
PREVIEW_TEMPLATE_TITLE = "Preview (read-only) -- how the current and the proposed bands"
POLICY_ROLE = "ProcurementPolicyAdmin"

TOOLS = [
    {
        "name": "search_templates",
        "description": (
            "Search the library of proven Cypher templates for the NorthWind PLUS graph. Rewrite the user's "
            "question into the model's own terms first (labels, relationship types, workflow words: e.g. "
            "'quotes rejected' -> 'Supplier RFQ rejection rate'). Returns up to 5 templates with title, "
            "description, parameters and Cypher. Search before writing new Cypher."),
        "input_schema": {"type": "object", "properties": {
            "query": {"type": "string", "description": "Search terms in ontology vocabulary."}},
            "required": ["query"]},
    },
    {
        "name": "get_schema",
        "description": ("Exact schema for some node types: description, properties with types, and every "
                        "relationship pattern in and out. Use before writing or adapting Cypher."),
        "input_schema": {"type": "object", "properties": {
            "labels": {"type": "array", "items": {"type": "string"}, "description": "Node labels, exact case."}},
            "required": ["labels"]},
    },
    {
        "name": "run_read_query",
        "description": (
            "Run a READ-ONLY Cypher query on the live NorthWind PLUS database (Neo4j Aura) and get the rows. "
            "Writes are rejected. The simulation is running, so results are a snapshot at query time; gather "
            "what one answer needs in ONE query where possible. Use $parameters for values."),
        "input_schema": {"type": "object", "properties": {
            "cypher": {"type": "string"},
            "params": {"type": "object", "description": "Values for $parameters in the query."},
            "template": {"type": "string", "description": "Name of the template used or adapted, if any."}},
            "required": ["cypher"]},
    },
    {
        "name": "preview_approval_bands",
        "description": ("Read-only: show how proposed L1/L2/L3 approval limits would route the POs currently "
                        "awaiting vetting, next to the current limits. Always run this before proposing a change."),
        "input_schema": {"type": "object", "properties": {
            "l1Limit": {"type": "number"}, "l2Limit": {"type": "number"}, "l3Limit": {"type": "number"}},
            "required": ["l1Limit", "l2Limit", "l3Limit"]},
    },
    {
        "name": "change_approval_bands",
        "description": (
            "Change the L1/L2/L3 PO approval limits (all three together; each level's base is derived from the "
            "level below, so no gaps). Only users with the ProcurementPolicyAdmin role may do this; the tool "
            "checks the role and asks the user to confirm in the terminal before anything is written. Every "
            "change is recorded as a PolicyChange node. Run preview_approval_bands first."),
        "input_schema": {"type": "object", "properties": {
            "l1Limit": {"type": "number"}, "l2Limit": {"type": "number"}, "l3Limit": {"type": "number"},
            "justification": {"type": "string", "description": "Why, in the user's words."}},
            "required": ["l1Limit", "l2Limit", "l3Limit", "justification"]},
    },
]

RULES = """You are the NorthWind PLUS business assistant. You answer questions about a LIVE procurement and
order-fulfillment simulation running on Neo4j, and you can make one governed change (the PO approval bands).

How to work:
- Rewrite the question into the model's vocabulary, then search_templates. If a template fits, run it (adapt
  parameters or filters as needed). If none fits, use get_schema and write new Cypher from the schema below.
- Use only labels, relationship types and properties that exist in the schema. Relationship direction matters.
- State lives in relationships to Collection nodes (see the principles), not in properties.
- If a query errors, read the error, fix the query and retry (at most twice), then explain what went wrong.
- Answer in plain business language. Say the numbers are a live snapshot (the simulation keeps changing them).
  Mention which template you used, or that you wrote a new query, in one short line at the end.
- Never invent numbers. If the data doesn't answer the question, say so.
- Ask a clarifying question when the request is ambiguous (e.g. which time window, which supplier).
- Changes: only via change_approval_bands, only after preview_approval_bands, and only when the user asked for
  the change. You can't create, approve or delete anything else; say so if asked.

The current user is {user}.
"""


class Session:
    def __init__(self, employee_id: str, model: str):
        load_dotenv(ROOT / ".env")
        self.client = anthropic.Anthropic()
        self.model = model
        self.kb = KnowledgeBase()
        self.aura = Aura()
        self.employee_id = employee_id
        self.user = self.aura.whoami(employee_id)
        if not self.user:
            raise SystemExit(f"No Employee with EmployeeID {employee_id!r} in the database.")
        self.messages: list[dict] = []
        # Fixed, governed tools are bound to their templates at startup (fails fast if the store is stale).
        self.policy_template = self.kb.template_by_title(POLICY_TEMPLATE_TITLE)
        self.preview_template = self.kb.template_by_title(PREVIEW_TEMPLATE_TITLE)
        logs = ROOT / "agent" / "logs"
        logs.mkdir(exist_ok=True)
        self.log_path = logs / f"session-{datetime.now():%Y%m%d-%H%M%S}.jsonl"
        user_line = f"{self.user['name']} (EmployeeID {employee_id}, roles: {', '.join(self.user['roles']) or 'none'})"
        self.system = [
            {"type": "text", "text": RULES.format(user=user_line)},
            {"type": "text",
             "text": "Model principles:\n- " + "\n- ".join(self.kb.principles()) + "\n\n" + self.kb.full_schema(),
             "cache_control": {"type": "ephemeral"}},   # the big, stable part: cached across turns
        ]

    def log(self, **event):
        event["ts"] = datetime.now().isoformat(timespec="seconds")
        with self.log_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(event, default=str) + "\n")

    # ---------------- tools ----------------

    def tool(self, name: str, args: dict) -> dict:
        if name == "search_templates":
            hits = self.kb.search_templates(args["query"], k=5)
            return {"templates": [{k: t[k] for k in ("name", "title", "description", "governance", "params", "cypher")}
                                  for t in hits]}
        if name == "get_schema":
            return {"schema": self.kb.schema_for(args["labels"]) or "No such node types."}
        if name == "run_read_query":
            result = self.aura.read(args["cypher"], args.get("params"))
            if "rows" in result and len(result["rows"]) > MAX_ROWS_TO_MODEL:
                result["note"] = f"Showing the first {MAX_ROWS_TO_MODEL} of {result['row_count']} rows."
                result["rows"] = result["rows"][:MAX_ROWS_TO_MODEL]
            return result
        if name == "preview_approval_bands":
            return self.aura.read(self.preview_template["cypher"], {k: args[k] for k in ("l1Limit", "l2Limit", "l3Limit")})
        if name == "change_approval_bands":
            return self.change_bands(args)
        return {"error": f"Unknown tool {name}"}

    def change_bands(self, args: dict) -> dict:
        # Identity comes from the session, never from the model.
        if POLICY_ROLE not in self.user["roles"]:
            return {"refused": f"{self.user['name']} does not hold the {POLICY_ROLE} role, so the approval bands "
                               f"can't be changed in this session."}
        l1, l2, l3 = (float(args[k]) for k in ("l1Limit", "l2Limit", "l3Limit"))
        if not (0 < l1 < l2 < l3):
            return {"refused": "Limits must be positive and increasing (L1 < L2 < L3)."}
        print(f"\n  >>> Confirm approval-band change requested by {self.user['name']}:"
              f"\n      L1 limit {l1:,.2f} | L2 {l1 + 0.01:,.2f}-{l2:,.2f} | L3 {l2 + 0.01:,.2f}-{l3:,.2f}"
              f"\n      Justification: {args['justification']}")
        if input("      Apply this change? [y/N] ").strip().lower() != "y":
            return {"refused": "The user did not confirm the change. Nothing was written."}
        result = self.aura.run_governed(self.policy_template["cypher"], {
            "requesterId": self.employee_id, "l1Limit": l1, "l2Limit": l2, "l3Limit": l3,
            "justification": args["justification"]})
        if "rows" in result and not result["rows"]:
            return {"refused": "The database refused the change (role or limit check failed). Nothing was written."}
        return result

    # ---------------- conversation ----------------

    def ask(self, question: str) -> str:
        self.messages.append({"role": "user", "content": question})
        self.log(event="question", text=question)
        usage = {"model_calls": 0}   # summed over every model call for this question
        for _ in range(12):   # tool-use rounds per question
            response = self.client.messages.create(
                model=self.model, max_tokens=4096, system=self.system, tools=TOOLS, messages=self.messages)
            usage["model_calls"] += 1
            for k, v in response.usage.model_dump().items():
                if isinstance(v, (int, float)):
                    usage[k] = usage.get(k, 0) + v
            self.messages.append({"role": "assistant", "content": response.content})
            if response.stop_reason != "tool_use":
                answer = "".join(b.text for b in response.content if b.type == "text")
                self.log(event="answer", text=answer, usage=usage)
                return answer
            results = []
            for block in response.content:
                if block.type != "tool_use":
                    continue
                started = time.perf_counter()
                output = self.tool(block.name, block.input)
                self.log(event="tool", name=block.name, input=block.input, ms=round((time.perf_counter() - started) * 1000),
                         output_preview=json.dumps(output, default=str)[:2000])
                print(f"  [{block.name}] {self._brief(block.name, block.input, output)}")
                results.append({"type": "tool_result", "tool_use_id": block.id,
                                "content": json.dumps(output, default=str),
                                "is_error": "error" in output})
            self.messages.append({"role": "user", "content": results})
        self.log(event="answer", text="(stopped: too many steps)", usage=usage)
        return "I stopped after too many steps without an answer. Try narrowing the question."

    @staticmethod
    def _brief(name, args, output):
        if name == "search_templates":
            return f"\"{args['query']}\" -> " + "; ".join(t["title"][:50] for t in output["templates"][:3])
        if "error" in output:
            return f"error: {output['error'][:120]}"
        if "rows" in output:
            return f"{output.get('row_count', len(output['rows']))} row(s)"
        return next(iter(output.keys()), "")


def main():
    ap = argparse.ArgumentParser(description="NorthWind PLUS business agent (relate + Neo4j Aura + Claude).")
    ap.add_argument("--as-employee", required=True, help="EmployeeID of the user (stands in for a login).")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    args = ap.parse_args()
    s = Session(args.as_employee, args.model)
    print(f"NorthWind PLUS agent -- signed in as {s.user['name']} ({', '.join(s.user['roles']) or 'no roles'}).")
    print(f"Model {s.model}. Log: {s.log_path.relative_to(ROOT)}. Type 'quit' to exit.\n")
    try:
        while True:
            q = input("You> ").strip()
            if q.lower() in ("quit", "exit"):
                break
            if q:
                print(f"\nAgent> {s.ask(q)}\n")
    except (KeyboardInterrupt, EOFError):
        print()
    finally:
        s.aura.close()
        s.kb.close()


if __name__ == "__main__":
    main()
