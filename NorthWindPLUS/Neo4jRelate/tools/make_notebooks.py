"""Generates both notebooks from one definition:
  NorthWind_PLUS_Agent.ipynb        (local Jupyter)
  NorthWind_PLUS_Agent_Colab.ipynb  (Google Colab)
"""
from pathlib import Path

import nbformat as nbf

ROOT = Path(__file__).resolve().parent.parent
md, code = nbf.v4.new_markdown_cell, nbf.v4.new_code_cell

LOAD_GRAPH = """1. Load the graph: in the Aura Query console, run `model/NorthWind_PLUS_Graph_Data_Model_Import_v2.3.2.cypher`
   from line 95 (*"// Let's clear all Nodes..."*) to line 1171. This **wipes the database** and builds NorthWind PLUS v2.3.2.
   Optionally also run the Recommendation Engine (lines 1271-1334).
   *(Already on v2.3.1 with data you want to keep? Run `model/NorthWind_PLUS_v2.3.2_Upgrade_from_v2.3.1.cypher` instead.)*
2. Run `model/NorthwindPlusGraphType_v2.3.2.cypher` in the same console, to apply the GRAPH TYPE schema.
3. Start the six Python loops (`model/NorthwindPlus_Stress_Test.py`, one process per `--loop`), so the data is moving."""

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

| EmployeeID | Who | Can change approval bands? |
|---|---|---|
| `25` | Olivia Bennett, ProcurementPolicyAdmin | yes |
| `12` | Gloria Gaynor, Level1Approver | no (can still ask questions) |

Rerunning this cell closes the previous session first (relate allows one writing connection per store)."""

SIGN_IN = """EMPLOYEE_ID = "25"
MODEL = northwind_agent.DEFAULT_MODEL      # e.g. "claude-opus-5-5" for harder questions

if "session" in globals():
    try:
        session.close()
    except Exception:
        pass
session = northwind_agent.Session(EMPLOYEE_ID, MODEL)
print(f"Signed in as {session.user['name']} ({', '.join(session.user['roles']) or 'no roles'}) -- model {session.model}")
print(f"Knowledge store: ontology {session.kb.ontology_version}, embeddings {session.kb.embedding_model}")


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
    md("### Your questions"),
    code('# ask("Which products are at risk of running out?")'),
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
business questions. Without embeddings the baseline is 9/12 — the misses are vocabulary gaps ("quotes" vs. "RFQ",
"negative" vs. "below zero", "approve" vs. "approval")."""),
    code("""r = subprocess.run([sys.executable, str(PROJECT / "kb" / "eval_search.py"), "--compare", "voyage-4-nano"],
                   capture_output=True, text=True)
print(r.stdout[-4000:] or r.stderr[-4000:])"""),
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
from build_kb import build
from kb_query import KnowledgeBase
print("Project folder:", PROJECT)"""),
        md(EMBED_MD.format(n=2, where_runs="on this machine")),
        code(STORE_CELL),
        md(SIGN_IN_MD.format(n=3)),
        code(SIGN_IN),
        *renumber(QUESTIONS, 4),
        *renumber(LEARNED, 5),
        *renumber(EVAL, 6),
        md("## 7. Done"),
        code("""session.close()
print("Closed the Aura connection and the knowledge store. What the agent learned stays in kb/northwind_kb.rl.")"""),
    ]
    return cells


STORE_CELL = """EMBEDDINGS = "none"        # or "voyage-4-nano"
REBUILD = False            # rebuild after editing kb/semantics.json or the model files (learning is kept)

store = PROJECT / "kb" / "northwind_kb.rl"
current = "none"
if store.exists():
    k = KnowledgeBase(store); current = k.embedding_model; k.close()
if REBUILD or not store.exists() or current != EMBEDDINGS:
    print(json.dumps(build(store, embeddings=EMBEDDINGS), indent=2))
else:
    print(f"Using {store.name} (embeddings: {current})")"""


def colab_notebook():
    cells = [
        md(INTRO.format(suffix=" (Google Colab)", where="""
This notebook runs on Google's servers. Your six Python loops keep running wherever they are; both talk to the same
Aura database. The knowledge store is kept on your **Google Drive** between Colab sessions, so the agent's learning
isn't lost when the runtime resets.
""", keys="""4. Add these **Colab Secrets** (key icon 🔑 in the left sidebar), and switch on *Notebook access* for each:
   `ANTHROPIC_API_KEY`, `NEO4J_URI`, `NEO4J_PASSWORD`, and optionally `NEO4J_USER` (or `NEO4J_USERNAME`) and
   `NEO4J_DATABASE` (both default to `neo4j`). Names must match exactly; your Aura database name may be the instance
   ID rather than `neo4j`.

Then run the cells from the top (*Runtime → Run all* works too; the upload step waits for your file).""")),
        md("""## 1. Get the project

If the project is on GitHub, put its URL in `REPO_URL`. Otherwise leave it empty and upload `relate-agent.zip`
when the file picker appears."""),
        code("""import os, sys, subprocess, zipfile, json, logging, shutil
from pathlib import Path

REPO_URL = ""          # e.g. "https://github.com/<your-account>/<repo>.git" once published

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
if PROJECT is None and REPO_URL:
    subprocess.run(["git", "clone", "--depth", "1", REPO_URL, str(WORK / "repo")], check=True)
    PROJECT = find_project(WORK / "repo")
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
`sentence-transformers` for semantic search (Colab already has `torch`)."""),
        code("""EMBEDDINGS = "none"        # or "voyage-4-nano"

packages = ["-r", "requirements.txt"] + (["sentence-transformers>=5"] if EMBEDDINGS == "voyage-4-nano" else [])
r = subprocess.run([sys.executable, "-m", "pip", "install", "-q", *packages], capture_output=True, text=True)
print(r.stdout[-2000:] or "Installed.")
if r.returncode:
    print(r.stderr[-3000:])
    raise RuntimeError("pip install failed (see above)")"""),
        md("""## 3. Keys from Colab Secrets

Required: `ANTHROPIC_API_KEY`, `NEO4J_URI`, `NEO4J_PASSWORD`. Optional: `NEO4J_USER` (or `NEO4J_USERNAME`, as in Aura's
credentials file; default `neo4j`) and `NEO4J_DATABASE` (default `neo4j`). Each secret needs **Notebook access** switched on."""),
        code(SECRETS_CELL),
        md("""## 4. Knowledge store (relate), kept on Google Drive

The store lives at `MyDrive/northwind_relate_agent/northwind_kb.rl`. It's copied here at the start and back to Drive
in the last cell (relate works on a local copy; Drive's file system isn't a good place for a live database file).
Set `USE_DRIVE = False` to skip Drive (the learning then lasts only for this Colab session)."""),
        code("""USE_DRIVE = True
REBUILD = False            # rebuild after editing kb/semantics.json or the model files (learning is kept)

for sub in ("agent", "kb"):
    sys.path.insert(0, str(PROJECT / sub))
logging.getLogger("neo4j.notifications").setLevel(logging.ERROR)
from IPython.display import Markdown, display
from build_kb import build
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

current = "none"
if store.exists():
    k = KnowledgeBase(store); current = k.embedding_model; k.close()
if REBUILD or not store.exists() or current != EMBEDDINGS:
    print(json.dumps(build(store, embeddings=EMBEDDINGS), indent=2))
else:
    print(f"Using {store.name} (embeddings: {current})")"""),
        md(EMBED_NOTE_COLAB),
        md(SIGN_IN_MD.format(n=5)),
        code(SIGN_IN),
        *renumber(QUESTIONS, 6),
        *renumber(LEARNED, 7),
        *renumber(EVAL, 8),
        md("## 9. Done — save the knowledge store to Drive"),
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
