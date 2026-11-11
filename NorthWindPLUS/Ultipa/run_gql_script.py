#!/usr/bin/env python3
"""
Runs the NorthWind PLUS GQL script against Ultipa GQLDB, one statement at a time.

The .gql file marks its sections with lines that start with //@@ :
    //@@ BEGIN SETUP ... //@@ END SETUP                    import + full workflow walk-through (the Cypher "line 82 to 1240" part)
    //@@ BEGIN LIVE_VIEWS ... //@@ END LIVE_VIEWS          the two "what happened today" views
    //@@ BEGIN RECOMMENDATION ... //@@ END RECOMMENDATION  optional recommendation engine
    //@@ BEGIN EXAMPLES ... //@@ END EXAMPLES              query examples and data-quality checks

Usage (same ULTIPA_* environment variables as the stress harness):
    python run_gql_script.py NorthWind_PLUS_Graph_Data_Model_Import_v2.3.1_Ultipa_GQL.gql --section setup
    python run_gql_script.py <file> --section setup --dry-run          # just print the statements
    python run_gql_script.py <file> --section examples --keep-going    # don't stop on the first error
    python run_gql_script.py <file> --section setup --from 40 --to 51  # run statements #40 through #51 only
    python run_gql_script.py <file> --section setup --timeout 1800     # allow 30 minutes per statement

--section setup also runs CREATE GRAPH IF NOT EXISTS <ULTIPA_GRAPH> first.
"""

from __future__ import annotations

import argparse
import sys
import time


def split_statements(text: str) -> list[str]:
    """Strip // and /* */ comments (outside string literals) and split on ';' (outside string literals)."""
    out, buf = [], []
    i, n = 0, len(text)
    quote = None
    while i < n:
        ch = text[i]
        if quote:
            buf.append(ch)
            if ch == "\\" and i + 1 < n:          # escaped character inside a string
                buf.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"', "`"):
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
            continue
        if ch == ";":
            stmt = "".join(buf).strip()
            if stmt:
                out.append(stmt)
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def extract_section(text: str, section: str) -> str:
    if section == "all":
        return text
    begin, end = f"//@@ BEGIN {section.upper()}", f"//@@ END {section.upper()}"
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == begin)
        stop = next(i for i, l in enumerate(lines) if l.strip() == end and i > start)
    except StopIteration:
        raise SystemExit(f"Section markers '{begin}' / '{end}' not found.")
    return "\n".join(lines[start + 1:stop])


def main() -> None:
    ap = argparse.ArgumentParser(description="Run a sectioned GQL script against Ultipa GQLDB.")
    ap.add_argument("file")
    ap.add_argument("--section", default="setup", help="setup | live_views | recommendation | examples | all (default: setup)")
    ap.add_argument("--dry-run", action="store_true", help="Print the statements without connecting.")
    ap.add_argument("--keep-going", action="store_true", help="Continue after a failed statement.")
    ap.add_argument("--from", dest="start", type=int, default=1, help="1-based statement number to start from.")
    ap.add_argument("--to", dest="stop", type=int, default=None, help="1-based statement number to stop after (inclusive).")
    ap.add_argument("--timeout", type=int, default=None,
                    help="Per-statement deadline in seconds (default: ULTIPA_TIMEOUT, else 600). The driver's own default is 30.")
    ap.add_argument("--show-rows", type=int, default=5, help="Rows to print for statements that return data (default 5).")
    args = ap.parse_args()

    with open(args.file, encoding="utf-8") as fh:
        statements = split_statements(extract_section(fh.read(), args.section))

    if args.dry_run:
        for k, s in enumerate(statements, 1):
            print(f"-- [{k}] " + "-" * 60 + f"\n{s}\n")
        print(f"{len(statements)} statement(s) in section '{args.section}'.")
        return

    from NorthwindPlus_Stress_Test_Ultipa import connect_from_env   # same connection settings as the harness
    import os
    graph = os.environ.get("ULTIPA_GRAPH", "NorthWindPLUS")
    if args.section in ("setup", "all"):
        # The graph must exist before connect_from_env() selects it.
        from NorthwindPlus_Stress_Test_Ultipa import GqldbClient, make_config
        boot = GqldbClient(make_config())
        boot.login(os.environ.get("ULTIPA_USER", "root"), os.environ.get("ULTIPA_PASSWORD", ""))
        boot.gql(f"CREATE GRAPH IF NOT EXISTS {graph}")
        try:
            boot.close()
        except Exception:
            pass

    client, graph = connect_from_env()
    from gqldb.client import QueryConfig
    timeout = args.timeout or int(os.environ.get("ULTIPA_TIMEOUT", "600"))
    cfg = QueryConfig(timeout=timeout)      # per-call timeout overrides the client's
    print(f"Per-statement deadline: {timeout}s")
    failures = 0
    ran = 0
    for k, stmt in enumerate(statements, 1):
        if k < args.start:
            continue
        if args.stop is not None and k > args.stop:
            break
        first_line = stmt.splitlines()[0][:110]
        t0 = time.perf_counter()
        ran += 1
        try:
            resp = client.gql(stmt, cfg)
            rows = resp.to_dicts() if resp is not None else []
            print(f"[{k}/{len(statements)}] OK  {time.perf_counter() - t0:6.2f}s  rows={len(rows):<5} {first_line}")
            for r in rows[:args.show_rows]:
                print(f"        {r}")
        except Exception as exc:
            failures += 1
            print(f"[{k}/{len(statements)}] ERR {time.perf_counter() - t0:6.2f}s  {first_line}\n        {exc}", file=sys.stderr)
            if not args.keep_going:
                print(f"Stopped at statement {k}. Fix it and resume with --from {k}.", file=sys.stderr)
                sys.exit(1)
    print(f"Done: ran {ran} of {len(statements)} statement(s) in section '{args.section}', {failures} failure(s).")


if __name__ == "__main__":
    main()
