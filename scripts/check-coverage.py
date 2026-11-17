#!/usr/bin/env python3
"""Line-coverage gate per module. Usage: check-coverage.py <codecov.json> <quality.json> <report-out.md>"""
import json
import os
import sys
from collections import defaultdict


def main() -> int:
    codecov_path, quality_path, report_path = sys.argv[1:4]
    with open(quality_path) as f:
        thresholds = json.load(f)["coverage"]
    with open(codecov_path) as f:
        data = json.load(f)["data"][0]["files"]

    totals = defaultdict(lambda: [0, 0])  # module -> [covered, count]
    per_file = []
    for entry in data:
        path = entry["filename"]
        marker = os.sep + "Sources" + os.sep
        if marker not in path:
            continue
        module = path.split(marker, 1)[1].split(os.sep, 1)[0]
        lines = entry["summary"]["lines"]
        totals[module][0] += lines["covered"]
        totals[module][1] += lines["count"]
        per_file.append((module, path.split(marker, 1)[1], lines["covered"], lines["count"]))

    failed = False
    rows = ["| Module | Lines | Covered | % | Threshold | Result |", "|---|---|---|---|---|---|"]
    for module in sorted(set(totals) | set(thresholds)):
        covered, count = totals.get(module, (0, 0))
        pct = 100.0 * covered / count if count else 0.0
        threshold = thresholds.get(module)
        if threshold is None:
            result = "not gated"
        elif count == 0:
            result, failed = "FAIL (no data)", True
        elif pct + 1e-9 < threshold:
            result, failed = "FAIL", True
        else:
            result = "ok"
        rows.append(f"| {module} | {count} | {covered} | {pct:.1f} | {threshold if threshold is not None else '—'} | {result} |")

    rows += ["", "| File | Covered / Lines |", "|---|---|"]
    rows += [f"| {p} | {c}/{n} |" for _, p, c, n in sorted(per_file) if n and c < n]
    report = "\n".join(rows)
    with open(report_path, "w") as f:
        f.write(report + "\n")
    print("\n".join(rows[: 2 + len(set(totals) | set(thresholds))]))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
