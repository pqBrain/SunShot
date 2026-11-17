#!/usr/bin/env python3
"""Acceptance-criteria traceability gate.

- Parses the slice table in docs/SLICES.md and every docs/acceptance/S<n>.md.
- For slices with status `Done`: every automated AC (Test level != manual) must be referenced
  by at least one test in Tests/ (by its ID, e.g. "S1-AC3" in a @Test name or comment), and every
  manual AC must be ticked "- [x] S1-AC5" in docs/qa/S<n>-manual.md (signed off by the tester).
- Any AC ID referenced in Tests/ must exist (catches typos).
- Prints per-slice progress for slices that are `In progress`.
Usage: check-traceability.py <repo-root>
"""
import pathlib
import re
import sys

AC_HEADING = re.compile(r"^##\s+(S\d+-AC\d+)\b", re.M)
AC_REF = re.compile(r"\b(S\d+-AC\d+)\b")
LEVEL = re.compile(r"^Test level:\s*([A-Za-z-]+)", re.M | re.I)
ROW = re.compile(r"^\|\s*(S\d+)\s*\|[^|]*\|\s*([^|]+?)\s*\|", re.M)
VALID_LEVELS = {"unit", "snapshot", "integration", "app-smoke", "manual"}


def parse_acceptance(path: pathlib.Path):
    text = path.read_text()
    headings = list(AC_HEADING.finditer(text))
    acs, errors = {}, []
    for i, match in enumerate(headings):
        block = text[match.end() : headings[i + 1].start() if i + 1 < len(headings) else len(text)]
        level_match = LEVEL.search(block)
        level = level_match.group(1).lower() if level_match else None
        ac_id = match.group(1)
        if ac_id in acs:
            errors.append(f"{path.name}: duplicate {ac_id}")
        if level not in VALID_LEVELS:
            errors.append(f"{path.name}: {ac_id} has missing/invalid 'Test level:' ({level})")
        if not ac_id.startswith(path.stem + "-"):
            errors.append(f"{path.name}: {ac_id} does not belong to slice {path.stem}")
        acs[ac_id] = level
    return acs, errors


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    statuses = {m.group(1): m.group(2) for m in ROW.finditer((root / "docs/SLICES.md").read_text())}
    if not statuses:
        print("traceability: could not parse slice table in docs/SLICES.md")
        return 1

    errors, all_acs = [], {}
    for path in sorted((root / "docs/acceptance").glob("S*.md")):
        acs, errs = parse_acceptance(path)
        errors += errs
        all_acs.update(acs)

    referenced = set()
    for test_file in (root / "Tests").rglob("*.swift"):
        referenced |= set(AC_REF.findall(test_file.read_text()))

    for ref in sorted(referenced - set(all_acs)):
        errors.append(f"Tests reference unknown acceptance criterion {ref}")

    for slice_id, status in sorted(statuses.items(), key=lambda kv: int(kv[0][1:])):
        acs = {k: v for k, v in all_acs.items() if k.startswith(slice_id + "-")}
        if status not in ("Done", "In progress") or slice_id == "S0":
            continue
        if not acs:
            (errors if status == "Done" else []).append(f"{slice_id} is {status} but has no docs/acceptance/{slice_id}.md")
            continue
        manual_file = root / f"docs/qa/{slice_id}-manual.md"
        ticked = set(re.findall(r"^- \[[xX]\]\s+(S\d+-AC\d+)", manual_file.read_text(), re.M)) if manual_file.exists() else set()
        missing_auto = sorted(k for k, v in acs.items() if v != "manual" and k not in referenced)
        missing_manual = sorted(k for k, v in acs.items() if v == "manual" and k not in ticked)
        done = len(acs) - len(missing_auto) - len(missing_manual)
        print(f"{slice_id} [{status}] {done}/{len(acs)} acceptance criteria verified")
        if status == "Done":
            errors += [f"{slice_id} is Done but {k} has no test referencing it" for k in missing_auto]
            errors += [f"{slice_id} is Done but manual {k} is not ticked in docs/qa/{slice_id}-manual.md" for k in missing_manual]

    if errors:
        print("\n".join(errors))
        print(f"traceability: {len(errors)} problem(s)")
        return 1
    print("traceability: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
