"""Tiny retrieval check: does the expected template appear in the top 3 for each question?"""
from kb_query import KnowledgeBase
CASES = [
    ("Which customer orders are blocked by missing stock?", "Open Customer Orders currently blocked"),
    ("Who changed the approval limits and why?", "Approval Policy history"),
    ("What are total sales by region?", "Total Sales by Region"),
    ("Which products are at risk of running out?", "At-Risk Products"),
    ("What is our gross profit in the last hour?", "Total Units Ordered from Suppliers (fulfilled)"),
    ("Raise the L2 approval limit to speed up vetting", "Change the approval bands"),
    ("Which suppliers get their quotes rejected most often?", "Supplier Reliability"),
    ("Supplier RFQ rejection rate", "Supplier Reliability"),
    ("change approval bands Level2Approver ApprovalLimit", "Change the approval bands"),
    ("Is any inventory negative?", "Find Inventory Levels that are below zero"),
    ("Which employees approve the most purchase orders?", "Approval Workload by Employee"),
    ("How long do customers wait for their orders?", "Open Customer Orders waiting time"),
]
kb = KnowledgeBase()
hits = 0
for q, expected in CASES:
    top = kb.search_templates(q, k=3)
    rank = next((i + 1 for i, t in enumerate(top) if t["title"].startswith(expected)), None)
    hits += rank is not None
    print(f"{'OK ' if rank else 'MISS'} {('#'+str(rank)) if rank else '  '}  {q:<58} -> {top[0]['title'][:60] if top else '-'}")
print(f"\n{hits}/{len(CASES)} in top 3")
