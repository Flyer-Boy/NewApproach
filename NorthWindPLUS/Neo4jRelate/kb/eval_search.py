#!/usr/bin/env python3
"""
Retrieval check: is the expected template in the top 3 for each business question?

  python kb/eval_search.py                          # the current store (kb/northwind_kb.rl)
  python kb/eval_search.py --compare voyage-4-nano  # builds two temporary stores -- without and with
                                                    # embeddings -- and scores both side by side
"""
from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kb_query import KnowledgeBase  # noqa: E402

CASES = [
    ("Which customer orders are blocked by missing stock?", "Open Customer Orders currently blocked"),
    ("Who changed the approval limits and why?", "Approval Policy history"),
    ("What are total sales by region?", "Total Sales by Region"),
    ("Which products are at risk of running out?", "At-Risk Products"),
    ("What is our gross profit in the last hour?", "Total Units Ordered from Suppliers (fulfilled)"),
    # the agent changes bands through its own tools; the preview comes first, so either counts
    ("Raise the L2 approval limit to speed up vetting", ("Change the approval bands", "Preview (read-only)")),
    ("Which suppliers get their quotes rejected most often?", "Supplier Reliability"),
    ("Supplier RFQ rejection rate", "Supplier Reliability"),
    ("change approval bands Level2Approver ApprovalLimit", ("Change the approval bands", "Preview (read-only)")),
    ("Is any inventory negative?", "Find Inventory Levels that are below zero"),
    ("Which employees approve the most purchase orders?", "Approval Workload by Employee"),
    ("How long do customers wait for their orders?", "Open Customer Orders waiting time"),
]


def evaluate(kb: KnowledgeBase) -> list[tuple]:
    out = []
    for question, expected in CASES:
        expected = expected if isinstance(expected, tuple) else (expected,)
        top = kb.search_templates(question, k=3)
        rank = next((i + 1 for i, t in enumerate(top) if t["title"].startswith(expected)), None)
        out.append((question, rank, top[0]["title"] if top else "-"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--compare", help="embedding provider to compare against no embeddings (e.g. voyage-4-nano)")
    args = ap.parse_args()

    if not args.compare:
        kb = KnowledgeBase()
        print(f"Embeddings: {kb.embedding_model}\n")
        results = evaluate(kb)
        for q, rank, top in results:
            print(f"{'OK ' if rank else 'MISS'} {('#' + str(rank)) if rank else '  '}  {q:<58} -> {top[:60]}")
        print(f"\n{sum(1 for _, r, _ in results if r)}/{len(results)} in top 3")
        return

    from build_kb import build
    tmp = Path(tempfile.mkdtemp(prefix="kbeval-"))
    try:
        build(tmp / "plain.rl", embeddings="none", fresh=True)
        print(f"Building with {args.compare} (first run downloads the model)...")
        build(tmp / "vec.rl", embeddings=args.compare, fresh=True)
        plain, vec = KnowledgeBase(tmp / "plain.rl"), KnowledgeBase(tmp / "vec.rl")
        a, b = evaluate(plain), evaluate(vec)
        print(f"\n{'question':<58} {'no emb.':>8} {args.compare:>14}")
        for (q, r1, _), (_, r2, top2) in zip(a, b):
            fmt = lambda r: f"#{r}" if r else "miss"
            print(f"{q:<58} {fmt(r1):>8} {fmt(r2):>14}")
        print(f"\n{'in top 3':<58} {sum(1 for _, r, _ in a if r):>6}/{len(a)} {sum(1 for _, r, _ in b if r):>12}/{len(b)}")
        plain.close(); vec.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
