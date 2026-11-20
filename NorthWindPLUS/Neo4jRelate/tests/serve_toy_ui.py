"""
Try the web UI without Aura or an API key: the API runs on the small toy procurement graph (tests/toy_procurement.py)
held in relate, with a canned "AI draft". Nothing leaves this machine.

  cd ui && npm install && npm run build && cd ..
  python tests/serve_toy_ui.py            # then open http://localhost:8000 and sign in as Albert Camus
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))

import uvicorn  # noqa: E402

from test_procurement_api import ThreadedAura  # noqa: E402
from api.main import create_app  # noqa: E402


def canned_draft(system: str, prompt: str) -> str:
    first = prompt.split("\n")[0]
    return f"(Toy draft, no AI) {first} Quantities follow the graph's restock recommendation and recent demand."


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    uvicorn.run(create_app(aura=ThreadedAura(), llm=canned_draft, mode="agents"), host="127.0.0.1", port=port, log_level="warning")
