"""Generates both notebooks from one definition:
  NorthWind_PLUS_Agent.ipynb        (local Jupyter)
  NorthWind_PLUS_Agent_Colab.ipynb  (Google Colab)
"""
from pathlib import Path

import nbformat as nbf

ROOT = Path(__file__).resolve().parent.parent
md, code = nbf.v4.new_markdown_cell, nbf.v4.new_code_cell

LOAD_GRAPH = """1. Load the graph: in the Aura Query console, run `model/NorthWind_PLUS_Graph_Data_Model_Import_v2.3.3.cypher`
   from line 109 (*"// Let's clear all Nodes..."*) to line 1186. This **wipes the database** and builds NorthWind PLUS v2.3.3.
   Optionally also run the Recommendation Engine (lines 1286-1349).
   *(Already on v2.3.2 with data you want to keep? Stop the loops and run `model/NorthWind_PLUS_v2.3.3_Upgrade_from_v2.3.2.cypher`
   instead; it lists its steps. From v2.3.1, run the v2.3.2 upgrade first.)*
   The import rebuilds the classic Northwind database as a graph-native application and extends it into a complete,
   360-degree business cycle: customer orders, low-stock detection, purchase orders with three levels of approval,
   supplier RFQs, warehouse receiving, finance closure and order fulfillment. All of it runs natively on the graph from
   here on: no data ingestion, no ETL or data pipelines.
2. Run `model/NorthwindPlusGraphType_v2.3.3.cypher` in the same console, to apply the GRAPH TYPE schema. This adds a
   governance layer to the model: the database itself enforces the ontology.
3. Start the Python loops (`model/NorthwindPlus_Stress_Test.py`, one process per `--loop`), so the data is moving.
   **Pick a mode** and set `SIMULATION_MODE` to match in step "Sign in" below:
   - **full**: all six loops run, and the agent works alongside them (questions, what-ifs, approval limits). On Windows:
     `run_loops_full.bat`.
   - **agents**: PO creation and resubmission are done by a Procurement Assistant with the agent (step "Procurement
     Assistant" below), so five loops run: no `--loop po-creation`, and `--loop po-vetting` with `--no-resubmit`. On
     Windows: `run_loops_agents.bat`.

   Run the `.bat` file from the `NorthWindPLUS/Neo4jRelate` folder on your own machine, with `.env` filled in: it opens
   one console per business process, so you can watch what happens in the background.
   Your graph-native system of record is now running on Neo4j Aura. Next, an AI agent answers questions about that live
   graph, using its own embedded Relate graph."""

INTRO = """# NorthWind PLUS business agent — Relate by Neo4j + Neo4j Aura + Claude{suffix}

Ask business questions about the **live** NorthWind PLUS simulation. The agent looks up proven Cypher templates in its
**relate** knowledge store (the ontology plus the query library), runs read queries on **Neo4j Aura**, can make one
governed change (the L1/L2/L3 PO approval bands) — and **learns**: every question is kept in relate as an
`Interaction`, and new queries you approve become templates that later questions find.
{where}
**Before you start**
""" + LOAD_GRAPH + """
{keys}"""

EMBED_MD = """## {n}. Knowledge store (relate)

`EMBEDDINGS = "none"` uses full-text + graph + past-questions retrieval. `"voyage-4-nano"` adds semantic search with
Voyage AI's open-weight model, run {where_runs} (no API key; ~700 MB download the first time; needs
`sentence-transformers` and `torch`). Changing it rebuilds the store; **what the agent has learned is kept**."""

SIGN_IN_MD = """## {n}. Sign in

`EMPLOYEE_ID` stands in for a login — the session decides who you are, the model never does.

| EmployeeID | Who | What the agent lets them do |
|---|---|---|
| `25` | Olivia Bennett, ProcurementPolicyAdmin | ask questions, run what-ifs, change the approval bands |
| `16`, `17`, `18` | Albert Camus, Bernard Shaw, Carlos Santana, Procurement Assistants | ask questions, create, resubmit and cancel POs |
| `12` | Gloria Gaynor, Level1Approver | ask questions, run what-ifs |

The agent offers each person only the tools their roles allow. `sign_in("16")` switches to someone else later; it
closes the previous session first (relate allows one writing connection per store).

`SIMULATION_MODE` must match the loops you started: `"full"` with `run_loops_full.bat` (six loops; no PO tools for
Procurement Assistants), `"agents"` with `run_loops_agents.bat` (the Procurement Assistant creates and resubmits POs).
In `agents` mode the agent refuses to create POs while the PO Creation loop still seems to be running."""

SIGN_IN = """if "northwind_agent" not in globals():
    raise RuntimeError("Run the cells above first (Runtime > Run all, or from step 1): this cell needs the agent and "
                       "the knowledge store set up by the earlier steps. A runtime restart clears them.")

EMPLOYEE_ID = "25"
SIMULATION_MODE = "full"                   # "full" (run_loops_full.bat) or "agents" (run_loops_agents.bat)
MODEL = northwind_agent.DEFAULT_MODEL      # e.g. "claude-opus-5-5" for harder questions
import os
os.environ["SIMULATION_MODE"] = SIMULATION_MODE


def sign_in(employee_id: str):
    \"\"\"Sign in as another employee: closes the current session (one writer per relate store), opens a new one.\"\"\"
    global session
    if "session" in globals():
        try:
            session.close()
        except Exception:
            pass
    session = northwind_agent.Session(employee_id, MODEL)
    tools = sorted(t["name"] for t in session.tools)
    print(f"Signed in as {session.user['name']} ({', '.join(session.user['roles']) or 'no roles'}) -- "
          f"model {session.model}, SIMULATION_MODE={session.mode}")
    print(f"Tools offered: {', '.join(tools)}")
    print(f"Knowledge store: ontology {session.kb.ontology_version}, embeddings {session.kb.embedding_model}")


sign_in(EMPLOYEE_ID)


def ask(question: str):
    \"\"\"Ask the agent. Tool calls print as they happen; the answer renders as Markdown.\"\"\"
    display(Markdown(session.ask(question)))


def new_conversation():
    \"\"\"Forget the conversation so far (same sign-in).\"\"\"
    session.messages.clear()
    print("Conversation cleared.")"""

QUESTIONS = [
    md("""## {n}. Ask questions

The conversation carries over between cells, so follow-ups like *\"and for last week?\"* work. When the agent writes a
new query that worked, it offers to save it as a template: a text box appears under the cell — `y` to keep it."""),
    code('ask("Which suppliers get their quotes rejected most often?")'),
    code('ask("How many POs are waiting for approval?")'),
    md("""Ask the same thing in other words: if you saved the template above, the search should now find it — through
the template itself and through the past question it answered."""),
    code('ask("What is the number and value of purchase orders still waiting to be vetted?")'),
    md("""### Governed change

The agent previews first, then asks you to confirm in a text box under the cell: `y` to apply, anything else to cancel.
Only EmployeeID 25 can apply it."""),
    code('ask("Raise L1 to 8000 and L2 to 20000 to speed up vetting.")'),
    code('ask("Who changed the approval limits, when and why?")'),
    md("""### Your questions

Some ideas to start from (also in the README's *Things to ask*). Remove the `#` in front of one line and run the
cell, or copy a line into a new cell and change it: another time window, a top 5 instead of a top 10, another level.
One question per cell keeps each answer next to its question."""),
    code('''# ask("What were total revenue and gross profit in the last hour?")        # or: in the last 15 minutes
# ask("Which available products urgently need restocking to fulfill customer orders?")
# ask("Who are our top 10 customers by revenue, and by product quantity?")
# ask("Who does the most PO vetting?")
# ask("Where is the PO vetting friction concentrated?")
# ask("Which supplier has the most rejected RFQs?")
# ask("Which available products are ordered least?")
# ask("Who is our best salesperson?")
# ask("Which is our best sales region?")
# ask("Which employee gives our customers the biggest discounts?")
# ask("Which fulfillment clerk received the most supplier deliveries (POs)?")   # or: customer orders
# ask("How are the POs waiting for approval spread across the L1, L2 and L3 bands?")
# ask("Which products are at risk of running out?")'''),
    code('# ask("")'),
]

WHATIF = [
    md("""## {n}. What-if: rehearse a change before making it

The agent pulls the POs waiting for approval from Aura into a **scratch relate store**, then runs the simulation's own
vetting Cypher there twice: with today's limits and with the proposed ones, 5 runs each (the simulation picks POs and
decisions at random). It compares approvals per level, rejections, POs left stuck and the cycles needed to clear the
queue. Nothing is written to Aura; the scratch stores are deleted afterwards.

The copy comes from `relate pull` when the `relate` command-line tool is installed, otherwise from a fallback copier
through the Neo4j driver. The answer says which, and how old the snapshot is. Resubmitted POs aren't replayed yet: a
rejection ends a PO's path in the rehearsal.

> **If the what-if shows little or no difference between the two scenarios**, the queue is probably too short to
> rehearse on. With the rates in the `run_loops_*.bat` files, the PO Vetting loop (12 per minute) clears new POs almost as fast as
> PO Creation (1 per minute) makes them. To build a backlog:
> - **pause the PO Vetting loop** (Ctrl+C in its window) for 10-15 minutes, run the what-if, then restart it; or
> - **slow it down**: change its `--rate 12` to 2 or 3 in the `.bat` file;
> - optionally **raise the Customer Order rate** (e.g. `--rate 6` to 12): POs include stock promised to open orders,
>   so busier sales mean bigger POs, and more of them land in the L2 and L3 bands. Keep an eye on the fulfillment window.
>
> Also check how the waiting POs spread across the bands first, e.g. `ask("How are the POs waiting for approval spread
> across the L1, L2 and L3 bands?")`. If almost all of them are under the L1 limit, raising it changes nothing.
> And note what the rehearsal measures: the simulation gives every approval level the same speed, so higher limits
> show up as fewer hand-offs between levels and fewer cycles to clear the queue, not as one level holding others up."""),
    code('ask("What would happen to the approval queue if we raised L1 to 8000 and L2 to 20000? Run a what-if.")'),
    md("If the rehearsal looks right, apply it: the `PolicyChange` justification will cite the what-if's ID."),
    code('# ask("Apply those limits: L1 8000, L2 20000, L3 unchanged.")'),
    code("""rows = session.kb._rows(\"\"\"MATCH (i:Interaction)-[:RAN]->(w:WhatIf)
    RETURN w.id AS id, w.createdAt AS at, w.method AS method, w.queuePOs AS pos, w.currentLimits AS cur,
           w.proposedLimits AS prop, w.appliedAs AS applied, i.question AS q ORDER BY at DESC LIMIT 10\"\"\")
display(Markdown("**What-ifs run so far**\\n\\n| What-if | POs pulled | Current limits | Proposed | Pulled with | Applied as |\\n|---|---|---|---|---|---|\\n" +
    "\\n".join(f"| {r['id']} | {r['pos']} | {' / '.join(f'{v:,.0f}' for v in r['cur'])} | {' / '.join(f'{v:,.0f}' for v in r['prop'])} | "
               f"{r['method'].split(' ')[0]} | {r['applied'] or '-'} |" for r in rows) if rows else "_No what-if yet._"))"""),
]

PROCUREMENT = [
    md("""## {n}. Procurement Assistant: create, resubmit and cancel POs

Since model v2.3.3 a person does what the `po-creation` loop used to do. The agent recommends with the loop's own rules;
you accept all, some, or change quantities, give **one justification per PO**, and confirm (a text box under the cell:
`y` to write). Every PO records who created it, when, why, `Source: "agent"`, and the recommended quantity next to the one
ordered. Rejected POs are yours too: resubmit them, or cancel them with a reason.

The agent never suggests splitting a PO to fit under a lower approval limit, and refuses two POs for one Supplier in a batch.

**This needs `SIMULATION_MODE = "agents"`** (set in step "Sign in", then rerun it) and the loops started with
`run_loops_agents.bat`. In `"full"` mode the loops create and resubmit POs, so the agent offers no PO tools and only
answers questions about them."""),
    code('''sign_in("16")      # Albert Camus, Procurement Assistant
if session.mode != "agents":
    print("\\nSIMULATION_MODE is 'full', so the agent offers no PO tools (in full mode the loops create POs). "
          "If you started run_loops_agents.bat: set SIMULATION_MODE = 'agents' in step 'Sign in', rerun that cell, "
          "then this one.")'''),
    code('ask("What needs restocking?")'),
    md("Reply in your own words, for example the line below: which POs to create, any quantity changes, and why."),
    code('# ask("Create PO 1 as recommended, and PO 2 with 20 units fewer of the first product. Justification: restock ahead of the weekend orders.")'),
    code('ask("Which rejected POs should I resubmit or cancel?")'),
    code('# ask("Resubmit the first one with the recommended quantities: L1 asked for a smaller order. Cancel any with nothing still needed.")'),
    code('ask("Show the POs created, resubmitted or cancelled through the agent, and where the recommendation was changed.")'),
    code('sign_in(EMPLOYEE_ID)      # back to the first sign-in'),
]

LEARNED = [
    md("""## {n}. What the agent learned (from relate)

Templates the agent created, how often templates get reused, and the question history — all read from the knowledge
store, the same graph the agent searches."""),
    code("""kb = session.kb
learned = kb._rows(\"\"\"
    MATCH (q:QueryTemplate {source:'agent'})
    OPTIONAL MATCH (q)-[:PART_OF]->(w:WorkflowStep)
    RETURN q.title AS title, q.createdBy AS by, q.question AS firstQuestion, coalesce(q.useCount, 0) AS reuses,
           q.status AS status, collect(DISTINCT w.name) AS workflows ORDER BY reuses DESC\"\"\")
display(Markdown("**Learned templates**\\n\\n| Title | First question | Created by | Reuses | Workflows |\\n|---|---|---|---|---|\\n" +
    "\\n".join(f"| {r['title']} | {r['firstQuestion']} | {r['by']} | {r['reuses']} | {', '.join(r['workflows'])} |" for r in learned)
    if learned else "_No learned templates yet._"))

top = kb._rows(\"\"\"MATCH (q:QueryTemplate) WHERE q.useCount > 0
                 RETURN q.title AS title, q.source AS source, q.useCount AS uses ORDER BY uses DESC LIMIT 10\"\"\")
display(Markdown("**Most used templates**\\n\\n| Template | Source | Uses |\\n|---|---|---|\\n" +
    "\\n".join(f"| {r['title'][:90]} | {r['source']} | {r['uses']} |" for r in top) if top else "_No template used yet._"))

hist = kb._rows(\"\"\"MATCH (i:Interaction) OPTIONAL MATCH (i)-[:USED|CREATED]->(q:QueryTemplate)
                  RETURN i.question AS q, i.employeeId AS who, i.modelCalls AS calls, i.inputTokens AS tin,
                         i.cacheReadTokens AS tcache, i.outputTokens AS tout, collect(DISTINCT q.title) AS templates,
                         i.newQueries AS newq, i.startedAt AS t ORDER BY t DESC LIMIT 15\"\"\")
display(Markdown("**Recent questions**\\n\\n| Question | By | Templates | New queries | Model calls | Tokens in (+cached) / out |\\n|---|---|---|---|---|---|\\n" +
    "\\n".join(f"| {r['q']} | {r['who']} | {'<br>'.join(t[:60] for t in r['templates']) or '-'} | {r['newq'] or 0} | {r['calls']} | "
               f"{(r['tin'] or 0):,} (+{(r['tcache'] or 0):,}) / {(r['tout'] or 0):,} |" for r in hist)))"""),
]

EVAL = [
    md("""## {n}. Optional: retrieval with vs. without embeddings

Builds two temporary stores (seed templates only) and checks whether the right template is in the top 3 for 12
business questions. **Slow on a CPU runtime** (several minutes: ~700 MB model download, then embedding) -- progress
prints as it goes. Without embeddings the baseline is 9/12 — the misses are vocabulary gaps ("quotes" vs. "RFQ",
"negative" vs. "below zero", "approve" vs. "approval")."""),
    code("""# Output streams as it runs. On Colab's CPU runtime this takes several minutes (model download + embedding);
# a GPU runtime (Runtime -> Change runtime type -> T4 GPU) is much faster. Needs sentence-transformers (step 2 installs it
# when EMBEDDINGS = "voyage-4-nano"; otherwise: pip install sentence-transformers).
proc = subprocess.Popen([sys.executable, "-u", str(PROJECT / "kb" / "eval_search.py"), "--compare", "voyage-4-nano"],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
for line in proc.stdout:
    print(line, end="")
proc.wait()"""),
]


def local_notebook():
    cells = [
        md(INTRO.format(suffix="", where="", keys="""4. Fill in `.env` in this folder (see `.env.example`): `ANTHROPIC_API_KEY`, `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`, `NEO4J_DATABASE`.
5. Use a kernel where `pip install -r requirements.txt` has been run.

Run the cells from the top. Each question is one `ask(...)` call.""")),
        md("## 1. Setup"),
        code("""import logging, os, sys, json, subprocess
from pathlib import Path

PROJECT = Path.cwd()                   # the notebook lives in the project folder
assert (PROJECT / "agent" / "agent.py").exists(), f"Open this notebook from the project folder (found {PROJECT})"
for sub in ("agent", "kb"):
    sys.path.insert(0, str(PROJECT / sub))
logging.getLogger("neo4j.notifications").setLevel(logging.ERROR)

from IPython.display import Markdown, display
import agent as northwind_agent
from build_kb import build, needs_rebuild
from kb_query import KnowledgeBase
print("Project folder:", PROJECT)
import shutil
cli = os.environ.get("RELATE_BIN") or shutil.which("relate")
print("relate CLI:", cli or "not found -- the what-if (step 5) will copy data through the Neo4j driver instead of relate pull")"""),
        md(EMBED_MD.format(n=2, where_runs="on this machine")),
        code(STORE_CELL),
        md(SIGN_IN_MD.format(n=3)),
        code(SIGN_IN),
        *renumber(QUESTIONS, 4),
        *renumber(WHATIF, 5),
        *renumber(PROCUREMENT, 6),
        *renumber(LEARNED, 7),
        md("## 8. Done"),
        code("""session.close()
print("Closed the Aura connection and the knowledge store. What the agent learned stays in kb/northwind_kb.rl.")"""),
    ]
    return cells


STORE_CELL = """EMBEDDINGS = "none"        # or "voyage-4-nano"
REBUILD = False            # rebuild after editing kb/semantics.json or the model files (learning is kept)

store = PROJECT / "kb" / "northwind_kb.rl"
why = "REBUILD = True" if REBUILD else needs_rebuild(store, EMBEDDINGS)   # new model version, edited model files, ...
if why:
    print(f"Building the knowledge store: {why}.")
    print(json.dumps(build(store, embeddings=EMBEDDINGS), indent=2))
else:
    print(f"Using {store.name} (embeddings: {EMBEDDINGS})")"""


def colab_notebook():
    cells = [
        md(INTRO.format(suffix=" (Google Colab)", where="""
This notebook runs on Google's servers. Your Python loops keep running wherever they are; both talk to the same
Aura database. The knowledge store is kept on your **Google Drive** between Colab sessions, so the agent's learning
isn't lost when the runtime resets.
""", keys="""4. Add these **Colab Secrets** (key icon 🔑 in the left sidebar), and switch on *Notebook access* for each:
   `ANTHROPIC_API_KEY`, `NEO4J_URI`, `NEO4J_PASSWORD`, and optionally `NEO4J_USER` (or `NEO4J_USERNAME`) and
   `NEO4J_DATABASE` (both default to `neo4j`). Names must match exactly; your Aura database name may be the instance
   ID rather than `neo4j`.

Then run the cells from the top (*Runtime → Run all* works too).""")),
        md("""## 1. Get the project

By default this clones the [NewApproach](https://github.com/Flyer-Boy/NewApproach) repository from GitHub (about
14 MB) and uses its `NorthWindPLUS/Neo4jRelate` folder. To run your own copy instead, set `REPO_URL` to your fork,
or set it to `""` and upload `relate-agent.zip` when the file picker appears.

**Getting a newer version** after you push changes: rerun this cell (it pulls the latest from GitHub), then
*Runtime → Restart session* and *Run all*. The restart matters: Python keeps the old modules loaded until then. A
restart keeps the downloaded files, so the next run updates them rather than cloning again."""),
        code("""import os, sys, subprocess, zipfile, json, logging, shutil
from pathlib import Path

REPO_URL = "https://github.com/Flyer-Boy/NewApproach.git"   # set to "" to upload relate-agent.zip instead

try:
    import google.colab  # noqa: F401
    IN_COLAB = True
except ImportError:
    IN_COLAB = False

WORK = Path("/content") if IN_COLAB else Path.cwd()

def find_project(base: Path):
    for p in [base, *base.glob("*"), *base.glob("*/*")]:
        if (p / "agent" / "agent.py").exists() and (p / "kb" / "build_kb.py").exists():
            return p
    return None

PROJECT = find_project(WORK)
REPO_DIR = WORK / "repo"
if PROJECT is None and REPO_URL:
    if (REPO_DIR / ".git").exists():
        # Already cloned earlier in this runtime (a session restart keeps the files): bring it up to date.
        r = subprocess.run(["git", "-C", str(REPO_DIR), "pull", "--ff-only"], capture_output=True, text=True)
        print((r.stdout or r.stderr).strip()[-500:])
        if r.returncode:
            raise RuntimeError(f"Couldn't update {REPO_DIR}. Delete it (!rm -rf {REPO_DIR}) and rerun this cell.")
    else:
        subprocess.run(["git", "clone", "--depth", "1", REPO_URL, str(REPO_DIR)], check=True)
    PROJECT = find_project(REPO_DIR)
if PROJECT is None and IN_COLAB:
    from google.colab import files
    print("Choose relate-agent.zip ...")
    uploaded = files.upload()
    for name in uploaded:
        if name.endswith(".zip"):
            with zipfile.ZipFile(WORK / name) as z:
                z.extractall(WORK)
    PROJECT = find_project(WORK)
assert PROJECT, "Project not found: set REPO_URL or upload relate-agent.zip"
os.chdir(PROJECT)
print("Project folder:", PROJECT)"""),
        md("""## 2. Install packages

Takes a minute the first time in a new Colab session. Set `EMBEDDINGS = "voyage-4-nano"` to also install
`sentence-transformers` for semantic search (Colab already has `torch`).

**If Colab asks to restart the session after this step** (it does when a package it had already loaded gets upgraded),
accept, then choose *Runtime → Run all* again. A restart clears everything the earlier cells set up; the second run
skips the clone and finishes the install in seconds."""),
        code("""if "PROJECT" not in globals():
    raise RuntimeError("Run step 1 first. If Colab restarted the session, that cleared the earlier steps: choose "
                       "Runtime > Run all again (step 1 won't clone twice, and step 2 finishes in seconds).")

EMBEDDINGS = "none"        # or "voyage-4-nano"

packages = ["-r", "requirements.txt"] + (["sentence-transformers>=5"] if EMBEDDINGS == "voyage-4-nano" else [])
r = subprocess.run([sys.executable, "-m", "pip", "install", "-q", *packages], capture_output=True, text=True)
print(r.stdout[-2000:] or "Installed.")
if r.returncode:
    print(r.stderr[-3000:])
    raise RuntimeError("pip install failed (see above)")
if "previously imported" in (r.stdout + r.stderr):
    print("Colab needs to restart the session to use the upgraded packages: click 'Restart session' if it offers, "
          "or Runtime > Restart session, then Runtime > Run all.")"""),
        md("""The **relate command-line tool** gives the what-if section (step 7) `relate pull`. It isn't part of
`pip install relate-db`; this cell runs relate's official installer, which checks the download's signature and puts
the binary in `~/.local/bin`. Set `INSTALL_RELATE_CLI = False` to skip it: the what-if then copies the data through the
Neo4j driver instead."""),
        code("""if "PROJECT" not in globals():
    raise RuntimeError("Run step 1 first. If Colab restarted the session, that cleared the earlier steps: choose "
                       "Runtime > Run all again (step 1 won't clone twice, and step 2 finishes in seconds).")

INSTALL_RELATE_CLI = True

cli = Path.home() / ".local" / "bin" / "relate"
if INSTALL_RELATE_CLI and not cli.exists():
    r = subprocess.run("curl -sSfL https://relatedb.ai/install.sh | bash", shell=True, capture_output=True, text=True)
    print((r.stdout + r.stderr).strip()[-1500:])
if cli.exists():
    os.environ["RELATE_BIN"] = str(cli)
    print(subprocess.run([str(cli), "--version"], capture_output=True, text=True).stdout.splitlines()[0],
          "-- the what-if will use relate pull")
else:
    print("No relate CLI: the what-if will copy the data through the Neo4j driver instead.")"""),
        md("""## 3. Keys from Colab Secrets

Required: `ANTHROPIC_API_KEY`, `NEO4J_URI`, `NEO4J_PASSWORD`. Optional: `NEO4J_USER` (or `NEO4J_USERNAME`, as in Aura's
credentials file; default `neo4j`) and `NEO4J_DATABASE` (default `neo4j`). Each secret needs **Notebook access** switched on."""),
        code('''if "PROJECT" not in globals():
    raise RuntimeError("Run step 1 first. If Colab restarted the session, that cleared the earlier steps: choose "
                       "Runtime > Run all again (step 1 won't clone twice, and step 2 finishes in seconds).")

''' + SECRETS_CELL),
        md("""## 4. Knowledge store (relate), kept on Google Drive

The store lives at `MyDrive/northwind_relate_agent/northwind_kb.rl`. It's copied here at the start and back to Drive
in the last cell (relate works on a local copy; Drive's file system isn't a good place for a live database file).
Set `USE_DRIVE = False` to skip Drive (the learning then lasts only for this Colab session)."""),
        code("""if "PROJECT" not in globals():
    raise RuntimeError("Run step 1 first. If Colab restarted the session, that cleared the earlier steps: choose "
                       "Runtime > Run all again (step 1 won't clone twice, and step 2 finishes in seconds).")

USE_DRIVE = True
REBUILD = False            # rebuild after editing kb/semantics.json or the model files (learning is kept)

for sub in ("agent", "kb"):
    sys.path.insert(0, str(PROJECT / sub))
logging.getLogger("neo4j.notifications").setLevel(logging.ERROR)
from IPython.display import Markdown, display
from build_kb import build, needs_rebuild
from kb_query import KnowledgeBase
import agent as northwind_agent

store = PROJECT / "kb" / "northwind_kb.rl"
DRIVE_STORE = None
if IN_COLAB and USE_DRIVE:
    from google.colab import drive
    drive.mount("/content/drive")
    DRIVE_STORE = Path("/content/drive/MyDrive/northwind_relate_agent/northwind_kb.rl")
    DRIVE_STORE.parent.mkdir(parents=True, exist_ok=True)
    if DRIVE_STORE.exists() and not store.exists():
        shutil.copy(DRIVE_STORE, store)
        print("Copied the knowledge store from Drive.")

why = "REBUILD = True" if REBUILD else needs_rebuild(store, EMBEDDINGS)   # new model version, edited model files, ...
if why:
    print(f"Building the knowledge store: {why}.")
    print(json.dumps(build(store, embeddings=EMBEDDINGS), indent=2))
else:
    print(f"Using {store.name} (embeddings: {EMBEDDINGS})")"""),
        md(EMBED_NOTE_COLAB),
        md(SIGN_IN_MD.format(n=5)),
        code(SIGN_IN),
        *renumber(QUESTIONS, 6),
        *renumber(WHATIF, 7),
        *renumber(PROCUREMENT, 8),
        *renumber(LEARNED, 9),
        md("## 10. Done — save the knowledge store to Drive"),
        code("""session.close()
if DRIVE_STORE:
    shutil.copy(store, DRIVE_STORE)
    print(f"Saved the knowledge store (and everything the agent learned) to {DRIVE_STORE}")
if IN_COLAB:
    from google.colab import files
    files.download(str(session.log_path))   # the JSON-lines session log
print("Closed the Aura connection and the knowledge store.")"""),
    ]
    return cells


EMBED_NOTE_COLAB = """*Embeddings:* with `EMBEDDINGS = "voyage-4-nano"` (set in step 2) the store is rebuilt with vectors from Voyage AI's
open-weight model, downloaded from Hugging Face on first use (~700 MB). A GPU runtime is faster but not needed."""

SECRETS_CELL = """REQUIRED = ["ANTHROPIC_API_KEY", "NEO4J_URI", "NEO4J_PASSWORD"]
OPTIONAL = ["NEO4J_USER", "NEO4J_USERNAME", "NEO4J_DATABASE"]

def secret(name):
    if IN_COLAB:
        from google.colab import userdata
        try:
            return userdata.get(name)
        except Exception as exc:   # not defined, or Notebook access is off
            return exc
    return os.environ.get(name)

report = []
for name in REQUIRED + OPTIONAL:
    value = secret(name)
    if isinstance(value, Exception):
        report.append((name, f"not available ({type(value).__name__})"))
    elif value:
        os.environ[name] = value.strip().strip('"').strip("'").strip()   # values pasted from .env may carry quotes
        report.append((name, "loaded"))
    else:
        report.append((name, "not set"))
for name, status in report:
    print(f"  {name:<18} {status}")

if os.environ.get("NEO4J_USERNAME") and not os.environ.get("NEO4J_USER"):
    os.environ["NEO4J_USER"] = os.environ["NEO4J_USERNAME"]
missing = [n for n in REQUIRED if not os.environ.get(n)]
if missing:
    raise RuntimeError("Missing required secret(s): " + ", ".join(missing) +
                       ". In the key panel, check the exact names and switch on Notebook access for each, then rerun this cell.")
print("\\nNEO4J_URI =", os.environ["NEO4J_URI"], "| user =", os.environ.get("NEO4J_USER", "neo4j"),
      "| database =", os.environ.get("NEO4J_DATABASE", "neo4j"))"""


def renumber(cells, n):
    out = []
    for c in cells:
        c = nbf.from_dict(dict(c))
        if c.cell_type == "markdown" and "{n}" in c.source:
            c.source = c.source.replace("{n}", str(n))
        out.append(c)
    return out


for filename, cells in (("NorthWind_PLUS_Agent.ipynb", local_notebook()),
                        ("NorthWind_PLUS_Agent_Colab.ipynb", colab_notebook())):
    nb = nbf.v4.new_notebook()
    nb.cells = cells
    nb.metadata["kernelspec"] = {"display_name": "Python 3", "language": "python", "name": "python3"}
    if "Colab" in filename:
        nb.metadata["colab"] = {"provenance": []}
    nbf.write(nb, str(ROOT / filename))
    print("written", filename)
