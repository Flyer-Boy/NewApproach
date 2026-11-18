"""
What-if sandbox: rehearse an L1/L2/L3 approval-limit change on a pulled copy of the live queue.

  1. pull   -- the POs waiting for approval, their lines and products, the approver roles and the state nodes,
               into a scratch relate store (sandbox/pull.py)
  2. replay -- for each scenario (current limits, proposed limits) and each run: copy the pulled store, set the
               scenario's limits on the RolE nodes, then run the simulation's own PO-vetting actions, one per
               cycle, chosen by the harness's weights, until none is eligible
  3. report -- approvals per level, rejections, POs left stuck, cycles to clear the queue; median and range

The vetting Cypher is imported from model/NorthwindPlus_Stress_Test.py (one source of truth). Only the
`CALL apoc.lock.nodes(...)` lines are dropped: relate has no APOC, and nothing else writes to the scratch store.
po_resubmit is left out (v1): a rejection ends the PO's path, and the report counts it.

Nothing here writes to Aura.
"""
from __future__ import annotations

import importlib.util
import random
import shutil
import statistics
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import relate

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "model" / "NorthwindPlus_Stress_Test.py"
SCRATCH = ROOT / "whatif"
LOOP_RATE_PER_MINUTE = 12        # the PO Vetting loop's rate in run_loops_full.bat / run_loops_agents.bat
EXCLUDED = {"po_resubmit"}
LEVELS = {"l1": "L1", "l2": "L2", "l3": "L3"}

SET_LIMITS = """
MATCH (l1:RolE {Title:"Level1Approver"}), (l2:RolE {Title:"Level2Approver"}), (l3:RolE {Title:"Level3Approver"})
SET l1.ApprovalLimit = toFloat($l1Limit),
    l2.ApprovalBase  = toFloat($l1Limit),
    l2.ApprovalLimit = toFloat($l2Limit),
    l3.ApprovalBase  = toFloat($l2Limit),
    l3.ApprovalLimit = toFloat($l3Limit)
RETURN count(*) AS n
"""   # the same SET as the governed change on Aura, without the role check and the PolicyChange audit node

LIMITS = """
MATCH (r:RolE) WHERE r.Title IN ["Level1Approver", "Level2Approver", "Level3Approver"]
RETURN r.Title AS title, r.ApprovalBase AS base, r.ApprovalLimit AS lim ORDER BY title
"""

QUEUE = """
MATCH (:NewPoS)-[]->(po:PurchaseOrder)-[i:HAS_PO_ITEM]->(p:Product)
WITH po, sum(i.POqt * (p.UnitPrice * i.POPriceDiscount)) AS cost
RETURN po.PONumber AS po, cost ORDER BY po
"""


def load_actions():
    """The harness's PO-vetting actions, minus po_resubmit, with the APOC lock lines removed."""
    spec = importlib.util.spec_from_file_location("northwind_harness", HARNESS)
    harness = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = harness   # dataclasses look their module up here
    spec.loader.exec_module(harness)
    strip = lambda q: "\n".join(l for l in q.split("\n") if "apoc.lock" not in l)
    return [(a.name, a.weight, strip(a.eligibility_query), strip(a.execute_query))
            for a in harness.PO_VETTING_ACTIONS if a.name not in EXCLUDED]


def check_limits(l1: float, l2: float, l3: float) -> str | None:
    if not (0 < l1 < l2 < l3):
        return "Limits must be positive and increasing (L1 < L2 < L3), as on Aura."
    return None


def _copy(src: Path, dst: Path):
    for f in dst.parent.glob(dst.name + "*"):
        shutil.rmtree(f) if f.is_dir() else f.unlink()
    shutil.copy2(src, dst)


def replay(store: Path, actions, limits: dict | None, rng: random.Random, max_cycles: int) -> dict:
    """One run on one copy: set limits, then vet until nothing is eligible."""
    conn = relate.connect(str(store))
    try:
        if limits:
            conn.execute(SET_LIMITS, limits)
        queue = {r["po"]: r["cost"] for r in conn.execute(QUEUE)}
        counts: dict[str, int] = {}
        value: dict[str, float] = {}
        cycles = 0
        while cycles < max_cycles:
            eligible = [a for a in actions if (conn.execute(a[2]).single() or {"EligibleCount": 0})["EligibleCount"] > 0]
            if not eligible:
                break
            name, _, _, execute = rng.choices(eligible, weights=[a[1] for a in eligible], k=1)[0]
            row = conn.execute(execute).single()
            cycles += 1
            if row is None:
                continue
            counts[name] = counts.get(name, 0) + 1
            value[name] = value.get(name, 0.0) + float(row.get("Cost") or 0)
        left = {r["po"]: r["cost"] for r in conn.execute(QUEUE)}
    finally:
        conn.close()
    out = {"cycles": cycles, "hit_cycle_cap": cycles >= max_cycles, "stuck": left, "queue": queue}
    for lvl, label in LEVELS.items():
        out[f"approved_{label}"] = counts.get(f"{lvl}_approve_final", 0)
        out[f"approved_{label}_value"] = round(value.get(f"{lvl}_approve_final", 0.0), 2)
        out[f"rejected_{label}"] = counts.get(f"{lvl}_reject", 0)
        out[f"passed_on_{label}"] = counts.get(f"{lvl}_approve_passthrough", 0)
    out["rejected"] = sum(out[f"rejected_{l}"] for l in LEVELS.values())
    out["rejected_value"] = round(sum(value.get(f"{l}_reject", 0.0) for l in LEVELS), 2)
    return out


def _summarize(runs: list[dict]) -> dict:
    keys = [k for k in runs[0] if isinstance(runs[0][k], (int, float)) and not isinstance(runs[0][k], bool)]
    summary = {}
    for k in keys:
        vals = [r[k] for r in runs]
        summary[k] = {"median": statistics.median(vals), "min": min(vals), "max": max(vals)}
    summary["minutes_at_loop_rate"] = round(summary["cycles"]["median"] / LOOP_RATE_PER_MINUTE, 1)
    stuck: dict[str, float] = {}
    for r in runs:
        stuck.update(r["stuck"])
    summary["stuck_pos"] = [{"po": po, "cost": round(c, 2)} for po, c in sorted(stuck.items())][:20]
    summary["stuck_in_runs"] = sum(1 for r in runs if r["stuck"])
    summary["hit_cycle_cap_in_runs"] = sum(1 for r in runs if r["hit_cycle_cap"])
    return summary


def boundary_pos(queue: dict, limits: dict) -> list[dict]:
    """POs no approval action can match under these limits. Since v2.3.3 the bands are contiguous (a level approves
    ApprovalBase < cost <= ApprovalLimit, and the next level starts at that limit), so only a cost of 0 or less, or
    above the L3 limit, has no path."""
    l3 = limits["l3Limit"]
    out = []
    for po, c in queue.items():
        why = None
        if c <= 0:
            why = "cost is 0 or less: no action matches"
        elif c > l3:
            why = "cost is above the L3 limit: no action matches, not even a rejection"
        if why:
            out.append({"po": po, "cost": round(c, 2), "why": why})
    return out


def what_if(l1: float, l2: float, l3: float, runs: int = 5, aura=None, method: str = "auto",
            seed: int | None = None, keep: bool = False, pulled_store: Path | None = None) -> dict:
    """Pull once, then replay the current and the proposed limits `runs` times each. Returns the comparison.
    `pulled_store` skips the pull and uses an existing store (tests)."""
    if (err := check_limits(l1, l2, l3)):
        return {"refused": err}
    from pull import pull   # sandbox/ is on sys.path when the agent imports this module
    wid = "WI-" + uuid.uuid4().hex[:8]
    work = SCRATCH / wid
    work.mkdir(parents=True, exist_ok=True)
    baseline = work / "baseline.rl"
    try:
        if pulled_store:
            shutil.copy2(pulled_store, baseline)
            source = {"method": "existing store", "pulled_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}
        else:
            source = pull(baseline, aura=aura, method=method)
        conn = relate.connect(str(baseline), read_only=True)
        current = {r["title"]: {"base": r["base"], "limit": r["lim"]} for r in conn.execute(LIMITS)}
        queue = {r["po"]: r["cost"] for r in conn.execute(QUEUE)}
        conn.close()
        if len(current) != 3:
            return {"error": f"The pulled copy has {len(current)} approver roles, expected 3. Pull summary: {source}"}
        current_limits = {"l1Limit": current["Level1Approver"]["limit"], "l2Limit": current["Level2Approver"]["limit"],
                          "l3Limit": current["Level3Approver"]["limit"]}
        proposed_limits = {"l1Limit": float(l1), "l2Limit": float(l2), "l3Limit": float(l3)}
        actions = load_actions()
        rng = random.Random(seed)
        max_cycles = max(50, 5 * len(queue))
        scenarios = {}
        for name, limits in (("current", None), ("proposed", proposed_limits)):
            results = []
            for i in range(runs):
                copy = work / f"{name}-{i}.rl"
                _copy(baseline, copy)
                results.append(replay(copy, actions, limits, rng, max_cycles))
            scenarios[name] = {"limits": limits or current_limits, **_summarize(results)}
        return {
            "whatIfId": wid,
            "source": source,
            "queue_at_pull": {"pos": len(queue), "value": round(sum(queue.values()), 2)},
            "runs_per_scenario": runs,
            "scenarios": scenarios,
            "boundary_pos": {"current": boundary_pos(queue, current_limits),
                             "proposed": boundary_pos(queue, proposed_limits)},
            "notes": [
                "A snapshot: new POs keep arriving on Aura after the pull.",
                "The harness's weights stand in for human approvers; a rejection ends the PO's path here "
                "(resubmissions aren't replayed in v1).",
                f"Minutes assume the PO Vetting loop's {LOOP_RATE_PER_MINUTE} cycles per minute, ignoring new POs.",
                "Medians are taken per measure, so they needn't add up to the queue size.",
            ],
        }
    finally:
        if not keep:
            shutil.rmtree(work, ignore_errors=True)
