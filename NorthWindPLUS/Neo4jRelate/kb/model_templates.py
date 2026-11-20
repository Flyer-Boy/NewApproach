"""
Templates read straight from the model files, without the knowledge store.

The knowledge store (kb/northwind_kb.rl) is built from the same files, but relate allows no other connection --
not even a read-only one -- while a process has a store open for writing (tested with relate 1.0.1). The web UI's
API runs next to the agent, so it reads the governed templates from the import script instead. It only needs
fixed templates by title, which come from the model files either way: no learned knowledge is involved.

Same interface as KnowledgeBase.template_by_title, so agent/procurement.py works with either.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_kb import seed_templates  # noqa: E402


class ModelTemplates:
    def __init__(self):
        self.templates = seed_templates()

    def template_by_title(self, title_prefix: str) -> dict:
        """Exactly one template whose title starts with title_prefix."""
        hits = [t for t in self.templates if t["title"].startswith(title_prefix)]
        if len(hits) != 1:
            raise LookupError(f"Expected one template titled '{title_prefix}...' in the model files, found {len(hits)}.")
        return hits[0]

    def close(self) -> None:
        pass
