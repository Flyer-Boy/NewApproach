#!/usr/bin/env python3
"""
NorthWind PLUS business agent: answers questions about the live simulation on Neo4j Aura, using the relate
knowledge store (ontology + proven Cypher templates) to find or write the right query -- and learning from it.

  python agent/agent.py --as-employee 25            # Olivia Bennett, ProcurementPolicyAdmin
  python agent/agent.py --as-employee 12            # Gloria Gaynor, Level1Approver (can ask, can't change bands)
  python agent/agent.py --as-employee 25 --model claude-opus-5-5

--as-employee stands in for a real login: it decides who the user is. The model never does.

Needs (e.g. in the project's .env): ANTHROPIC_API_KEY, NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD, NEO4J_DATABASE.
If the knowledge store was built with embeddings, the same embedder is loaded for queries (see kb/embeddings.py).

What the agent keeps in relate:
  - every question as an (:Interaction), linked to the templates it USED and the ones it CREATED
  - new queries the user approves, as QueryTemplates (source 'agent') -- found by later searches
Every tool call is also logged to agent/logs/ as JSON lines.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

import anthropic
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "kb"))
sys.path.insert(0, str(ROOT / "agent"))
sys.path.insert(0, str(ROOT / "sandbox"))
from kb_query import KnowledgeBase  # noqa: E402
from kb_write import is_write       # noqa: E402
from aura import Aura               # noqa: E402
import whatif                       # noqa: E402
import procurement                  # noqa: E402

DEFAULT_MODEL = "claude-sonnet-5-5"
MAX_ROWS_TO_MODEL = 50
POLICY_TEMPLATE_TITLE = "Change the approval bands (governed)"
PREVIEW_TEMPLATE_TITLE = "Preview (read-only) -- how the current and the proposed bands"
POLICY_ROLE = "ProcurementPolicyAdmin"
WHATIF_RUNS = 5
# full:   all six simulation loops run; the agent answers questions, runs what-ifs and changes approval limits.
# agents: PO creation and resubmission are handed to a Procurement Assistant with the agent (five loops run).
SIMULATION_MODES = ("full", "agents")

TOOLS = [
    {
        "name": "search_templates",
        "description": (
            "Search the library of proven Cypher templates for the NorthWind PLUS graph. Rewrite the user's "
            "question into the model's own terms first (labels, relationship types, workflow words: e.g. "
            "'quotes rejected' -> 'Supplier RFQ rejection rate'). Returns up to 5 templates with title, "
            "description, parameters and Cypher, including templates learned from earlier questions. "
            "Required before run_read_query for every question."),
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
            "Writes are rejected. Search templates first. The simulation is running, so results are a snapshot at "
            "query time; gather what one answer needs in ONE query where possible. Use $parameters for values. "
            "The result may include Neo4j 'warnings' (e.g. a property or label that doesn't exist): read them, "
            "they usually mean the query needs fixing."),
        "input_schema": {"type": "object", "properties": {
            "cypher": {"type": "string"},
            "params": {"type": "object", "description": "Values for $parameters in the query."},
            "template": {"type": "string", "description": "Name of the template used or adapted, if any."}},
            "required": ["cypher"]},
    },
    {
        "name": "save_template",
        "description": (
            "Offer to save a NEW query you wrote (not one from the library) as a reusable template, so later "
            "questions find it. Only for a read query that already ran successfully for this question and answers "
            "a question others are likely to ask. Generalize first: use $parameters instead of hard-coded values "
            "(then run that version). The user is asked to approve (a prompt under the notebook cell, or in the terminal); nothing is saved otherwise."),
        "input_schema": {"type": "object", "properties": {
            "title": {"type": "string", "description": "Short business title, like the library's titles."},
            "description": {"type": "string", "description": "What it answers, in business words; mention parameters."},
            "cypher": {"type": "string", "description": "Exactly the Cypher that ran successfully."}},
            "required": ["title", "description", "cypher"]},
    },
    {
        "name": "preview_approval_bands",
        "description": ("Read-only: show how proposed L1/L2/L3 approval limits would route the POs currently "
                        "awaiting vetting, next to the current limits: a quick look at who moves band. For what a change would "
                        "do to the queue, use what_if_approval_bands. Run this before change_approval_bands."),
        "input_schema": {"type": "object", "properties": {
            "l1Limit": {"type": "number"}, "l2Limit": {"type": "number"}, "l3Limit": {"type": "number"}},
            "required": ["l1Limit", "l2Limit", "l3Limit"]},
    },
    {
        "name": "what_if_approval_bands",
        "description": (
            "Rehearse proposed L1/L2/L3 approval limits on a private copy of the live queue: pulls the POs waiting "
            "for approval into a scratch relate store, then runs the simulation's own vetting logic there with the "
            "current and with the proposed limits (5 runs each) and compares approvals per level, rejections, POs "
            "left stuck and cycles to clear the queue. Never writes to Aura. Takes up to a minute."),
        "input_schema": {"type": "object", "properties": {
            "l1Limit": {"type": "number"}, "l2Limit": {"type": "number"}, "l3Limit": {"type": "number"}},
            "required": ["l1Limit", "l2Limit", "l3Limit"]},
    },
    {
        "name": "change_approval_bands",
        "description": (
            "Change the L1/L2/L3 PO approval limits (all three together; each level starts where the level below "
            "ends, so no gaps). Only users with the ProcurementPolicyAdmin role may do this; the tool "
            "checks the role and asks the user to confirm (a prompt under the notebook cell, or in the terminal) before anything is written. Every "
            "change is recorded as a PolicyChange node. Run preview_approval_bands first."),
        "input_schema": {"type": "object", "properties": {
            "l1Limit": {"type": "number"}, "l2Limit": {"type": "number"}, "l3Limit": {"type": "number"},
            "justification": {"type": "string", "description": "Why, in the user's words."}},
            "required": ["l1Limit", "l2Limit", "l3Limit", "justification"]},
    },
]

RULES = """You are the NorthWind PLUS business assistant. You answer questions about a LIVE procurement and
order-fulfillment simulation running on Neo4j, and you carry out the governed actions the signed-in user's roles
allow (only the tools you are given; each one checks the role again and asks the user to confirm).

How to work:
- Rewrite the question into the model's vocabulary, then search_templates (required before any query). If a
  template fits, run it (adapt parameters or filters as needed) and pass its name as `template`. If none fits,
  use get_schema and write new Cypher from the schema below.
- Use only labels, relationship types and properties that exist in the schema. Relationship direction matters.
- State lives in relationships to Collection nodes (see the principles), not in properties.
- If a query errors or returns warnings, read them, fix the query and retry (at most twice), then explain.
- Numbers: take every count, total and average from query results. If the answer needs a total or a count of
  groups (e.g. "how many suppliers have no rejections"), compute it in Cypher -- don't add numbers up yourself.
- Answer in plain business language. Say the numbers are a live snapshot (the simulation keeps changing them).
  End with one short line: the template you used, or that you wrote a new query.
- After answering with a NEW query that worked and would help others, call save_template once (generalized
  with $parameters). The user decides whether it's kept.
- Never invent numbers. If the data doesn't answer the question, say so.
- Ask a clarifying question when the request is ambiguous (e.g. which time window, which supplier).
- Changes: only through your governed tools, and only when the user asked for the change. Approval bands: only via
  change_approval_bands, after preview_approval_bands. You can't create, approve or delete anything else; say so if
  asked, and name the role that could.
- Limit changes: when the user asks what a change WOULD DO (its effect on the queue, approvals, speed), run
  what_if_approval_bands directly; don't stop at the preview. Use preview_approval_bands alone only for a quick look
  at which POs fall in which band, or when the user asks for the preview. Before change_approval_bands, if no what-if
  was run for those limits in this conversation, offer one. Report it as a comparison of the two scenarios (medians, with the range when runs disagree), name POs that
  would be stuck or only rejectable, say how old the snapshot is and that it doesn't replay resubmissions, and give
  its whatIfId.

The current user is {user}.
{role_rules}"""


def _norm(cypher: str) -> str:
    return " ".join(cypher.split())


class Session:
    def __init__(self, employee_id: str, model: str):
        load_dotenv(ROOT / ".env")
        self.client = anthropic.Anthropic()
        self.model = model
        self.kb = KnowledgeBase(read_only=False)       # the agent writes its learning back to relate
        self.aura = Aura()
        self.employee_id = employee_id
        self.user = self.aura.whoami(employee_id)
        self.messages: list[dict] = []
        self._setup_tools()
        logs = ROOT / "agent" / "logs"
        logs.mkdir(exist_ok=True)
        self.log_path = logs / f"session-{datetime.now():%Y%m%d-%H%M%S}.jsonl"
        self.system = self._system_prompt()
        self._reset_question_state()

    def _setup_tools(self):
        """Tools are offered by role: everyone can ask; governed actions only for the roles that may take them.
        Fixed, governed tools are bound to their templates here (fails fast if the store is stale)."""
        self.whatifs: dict[tuple, str] = {}     # (l1, l2, l3) -> whatIfId, for this session
        self.policy_template = self.kb.template_by_title(POLICY_TEMPLATE_TITLE)
        self.preview_template = self.kb.template_by_title(PREVIEW_TEMPLATE_TITLE)
        self.procurement = procurement.Procurement(self)
        self.mode = (os.environ.get("SIMULATION_MODE") or "full").strip().lower()
        if self.mode not in SIMULATION_MODES:
            raise SystemExit(f"SIMULATION_MODE must be one of {', '.join(SIMULATION_MODES)} (got {self.mode!r}).")
        roles = self.user["roles"]
        self.tools = [t for t in TOOLS if t["name"] != "change_approval_bands" or POLICY_ROLE in roles]
        if self.procurement.allowed():
            self.tools += procurement.TOOLS
        self.offered = {t["name"] for t in self.tools}

    def _system_prompt(self):
        user_line = f"{self.user['name']} (EmployeeID {self.employee_id}, roles: {', '.join(self.user['roles']) or 'none'})"
        if self.procurement.allowed():
            role_rules = procurement.RULES
        elif procurement.ROLE in self.user["roles"]:
            role_rules = ("\nSIMULATION_MODE is 'full': the simulation's loops create and resubmit POs, so you can answer "
                          "questions about procurement but not create, resubmit or cancel POs. If asked, say that "
                          "SIMULATION_MODE=agents (with run_loops_agents.bat) hands those jobs to the Procurement Assistant.\n")
        else:
            role_rules = ""
        return [
            {"type": "text", "text": RULES.format(user=user_line, role_rules=role_rules)},
            {"type": "text",
             "text": "Model principles:\n- " + "\n- ".join(self.kb.principles()) + "\n\n" + self.kb.full_schema(),
             "cache_control": {"type": "ephemeral"}},   # the big, stable part: cached across turns
        ]

    def _reset_question_state(self):
        self.interaction_id = None
        self.searched = False
        self.ok_new_queries: set[str] = set()   # new Cypher that ran without error for this question
        self.saved = False

    def log(self, **event):
        event["ts"] = datetime.now().isoformat(timespec="seconds")
        with self.log_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(event, default=str) + "\n")

    def confirm(self, prompt: str) -> bool:
        """Human approval for anything that writes. Terminal and Jupyter/Colab all support input()."""
        return input(prompt).strip().lower() == "y"

    # ---------------- tools ----------------

    def tool(self, name: str, args: dict) -> dict:
        if name not in self.offered:
            return {"refused": f"The {name} tool isn't available to {self.user['name']} (roles: "
                               f"{', '.join(self.user['roles']) or 'none'})."}
        if name in procurement.NAMES:
            return self.procurement.handle(name, args)
        if name == "search_templates":
            self.searched = True
            hits = self.kb.search_templates(args["query"], k=5)
            return {"templates": [{k: t[k] for k in ("name", "title", "description", "governance", "params", "cypher", "source")}
                                  for t in hits]}
        if name == "get_schema":
            return {"schema": self.kb.schema_for(args["labels"]) or "No such node types."}
        if name == "run_read_query":
            return self.run_read(args)
        if name == "save_template":
            return self.save_template(args)
        if name == "preview_approval_bands":
            return self.aura.read(self.preview_template["cypher"], {k: args[k] for k in ("l1Limit", "l2Limit", "l3Limit")})
        if name == "what_if_approval_bands":
            return self.what_if(args)
        if name == "change_approval_bands":
            return self.change_bands(args)
        return {"error": f"Unknown tool {name}"}

    def run_read(self, args: dict) -> dict:
        if not self.searched:
            return {"error": "Search the template library first: call search_templates for this question, "
                             "then run a matching template or write a new query."}
        result = self.aura.read(args["cypher"], args.get("params"))
        template = args.get("template")
        if "error" not in result:
            if template and self.kb.get_template(template):
                self.kb.record_use(self.interaction_id, template)
            else:
                self.ok_new_queries.add(_norm(args["cypher"]))
        if "rows" in result and len(result["rows"]) > MAX_ROWS_TO_MODEL:
            result["note"] = f"Showing the first {MAX_ROWS_TO_MODEL} of {result['row_count']} rows."
            result["rows"] = result["rows"][:MAX_ROWS_TO_MODEL]
        return result

    def save_template(self, args: dict) -> dict:
        cypher = args["cypher"]
        if self.saved:
            return {"refused": "A template was already saved for this question."}
        if is_write(cypher):
            return {"refused": "Only read queries can be saved as templates."}
        if _norm(cypher) not in self.ok_new_queries:
            return {"refused": "Only a new query that already ran successfully for this question can be saved. "
                               "Run exactly this Cypher first."}
        print(f"\n  >>> Save this query to the template library?\n      Title: {args['title']}"
              f"\n      {args['description']}\n      " + cypher.strip().replace("\n", "\n      "))
        if not self.confirm("      Save it? [y/N] "):
            return {"refused": "The user chose not to save it. Nothing was written."}
        saved = self.kb.save_template(self.interaction_id, args["title"], args["description"], cypher,
                                      self.employee_id, self.current_question)
        self.saved = True
        return {"saved": saved}

    def what_if(self, args: dict) -> dict:
        limits = tuple(float(args[k]) for k in ("l1Limit", "l2Limit", "l3Limit"))
        print(f"  ... rehearsing L1 {limits[0]:,.0f} / L2 {limits[1]:,.0f} / L3 {limits[2]:,.0f} on a pulled copy "
              f"({WHATIF_RUNS} runs per scenario)")
        try:
            result = whatif.what_if(*limits, runs=WHATIF_RUNS, aura=self.aura)
        except Exception as exc:
            return {"error": f"The what-if couldn't run: {type(exc).__name__}: {exc}"}
        if "whatIfId" in result:
            self.kb.record_whatif(self.interaction_id, self.employee_id, result)
            self.whatifs[limits] = result["whatIfId"]
        return result

    def change_bands(self, args: dict) -> dict:
        # Identity comes from the session, never from the model.
        if POLICY_ROLE not in self.user["roles"]:
            return {"refused": f"{self.user['name']} does not hold the {POLICY_ROLE} role, so the approval bands "
                               f"can't be changed in this session."}
        l1, l2, l3 = (float(args[k]) for k in ("l1Limit", "l2Limit", "l3Limit"))
        if not (0 < l1 < l2 < l3):
            return {"refused": "Limits must be positive and increasing (L1 < L2 < L3)."}
        rehearsal = self.whatifs.get((l1, l2, l3))
        if rehearsal and rehearsal not in args["justification"]:
            args["justification"] = f"{args['justification']} [rehearsed in what-if {rehearsal}]"
        print(f"\n  >>> Confirm approval-band change requested by {self.user['name']}:"
              f"\n      L1 up to {l1:,.2f} | L2 above {l1:,.2f} up to {l2:,.2f} | L3 above {l2:,.2f} up to {l3:,.2f}"
              f"\n      Justification: {args['justification']}")
        if not self.confirm("      Apply this change? [y/N] "):
            return {"refused": "The user did not confirm the change. Nothing was written."}
        result = self.aura.run_governed(self.policy_template["cypher"], {
            "requesterId": self.employee_id, "l1Limit": l1, "l2Limit": l2, "l3Limit": l3,
            "justification": args["justification"]})
        if "rows" in result and not result["rows"]:
            return {"refused": "The database refused the change (role or limit check failed). Nothing was written."}
        self.kb.record_use(self.interaction_id, self.policy_template["name"])
        if rehearsal and result.get("rows"):
            self.kb.mark_whatif_applied(rehearsal, result["rows"][0].get("PolicyChangeID"))
        return result

    # ---------------- conversation ----------------

    def ask(self, question: str) -> str:
        self._reset_question_state()
        self.current_question = question
        self.interaction_id = self.kb.start_interaction(question, self.employee_id, self.model)
        self.messages.append({"role": "user", "content": question})
        self.log(event="question", text=question, interaction=self.interaction_id)
        usage = {"model_calls": 0}   # summed over every model call for this question
        answer = "I stopped after too many steps without an answer. Try narrowing the question."
        for _ in range(12):   # tool-use rounds per question
            response = self.client.messages.create(
                model=self.model, max_tokens=4096, system=self.system, tools=self.tools, messages=self.messages)
            usage["model_calls"] += 1
            for k, v in response.usage.model_dump().items():
                if isinstance(v, (int, float)):
                    usage[k] = usage.get(k, 0) + v
            self.messages.append({"role": "assistant", "content": response.content})
            if response.stop_reason != "tool_use":
                answer = "".join(b.text for b in response.content if b.type == "text")
                break
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
        self.kb.finish_interaction(self.interaction_id, answer, usage, len(self.ok_new_queries))
        self.log(event="answer", text=answer, usage=usage, interaction=self.interaction_id)
        return answer

    @staticmethod
    def _brief(name, args, output):
        if name == "search_templates":
            return f"\"{args['query']}\" -> " + "; ".join(t["title"][:50] for t in output["templates"][:3])
        if "error" in output:
            return f"error: {output['error'][:120]}"
        if name == "recommend_resubmissions" and "rows" in output:
            still = sum(1 for r in output["rows"] if r.get("EstimatedCost"))
            return f"{len(output['rows'])} rejected PO(s): {still} can be resubmitted, {len(output['rows']) - still} have nothing still needed"
        if name == "recommend_restock" and "rows" in output:
            return f"{len(output['rows'])} PO(s) recommended" + (" -- WARNING: a loop still seems to be running" if "warning" in output else "")
        if "whatIfId" in output:
            p = output["scenarios"]["proposed"]
            return (f"{output['whatIfId']}: {output['queue_at_pull']['pos']} POs pulled via {output['source']['method']}; "
                    f"proposed: median {p['cycles']['median']} cycles, {p['stuck_in_runs']} run(s) with stuck POs")
        if "saved" in output:
            return f"saved as template '{output['saved']['name']}'"
        if "created" in output:
            return f"created {', '.join(c['PONumber'] for c in output['created']) or 'nothing'}; {len(output['left_out'])} line(s) left out"
        if "resubmitted" in output:
            done = ', '.join(c['ResubmittedFrom'] + ' as ' + c['PONumber'] for c in output['resubmitted']) or 'nothing'
            return f"resubmitted {done}; {len(output['not_resubmitted'])} not resubmitted, {len(output['left_out'])} line(s) left out"
        if "cancelled" in output:
            return f"cancelled {', '.join(output['cancelled']) or 'nothing'}"
        if "rows" in output:
            w = f", {len(output['warnings'])} warning(s)" if output.get("warnings") else ""
            return f"{output.get('row_count', len(output['rows']))} row(s){w}"
        return next(iter(output.keys()), "")

    def close(self):
        self.aura.close()
        self.kb.close()
        shutil.rmtree(whatif.SCRATCH, ignore_errors=True)   # pulled copies hold business data


def main():
    ap = argparse.ArgumentParser(description="NorthWind PLUS business agent (relate + Neo4j Aura + Claude).")
    ap.add_argument("--as-employee", required=True, help="EmployeeID of the user (stands in for a login).")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--mode", choices=SIMULATION_MODES, help="Overrides SIMULATION_MODE from .env: full (six loops) "
                    "or agents (a Procurement Assistant with the agent creates and resubmits POs).")
    args = ap.parse_args()
    if args.mode:
        os.environ["SIMULATION_MODE"] = args.mode
    s = Session(args.as_employee, args.model)
    print(f"NorthWind PLUS agent -- signed in as {s.user['name']} ({', '.join(s.user['roles']) or 'no roles'}), "
          f"SIMULATION_MODE={s.mode}.")
    print(f"Model {s.model}. Knowledge store: ontology {s.kb.ontology_version}, embeddings {s.kb.embedding_model}. "
          f"Log: {s.log_path.relative_to(ROOT)}. Type 'quit' to exit.\n")
    from build_kb import ONTOLOGY_VERSION, model_fingerprint
    if s.kb.ontology_version != ONTOLOGY_VERSION or s.kb.model_hash != model_fingerprint():
        print("  Note: the model files changed since the knowledge store was built. Quit and run "
              "python kb/build_kb.py (what the agent learned is kept).\n")
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
        s.close()


if __name__ == "__main__":
    main()
