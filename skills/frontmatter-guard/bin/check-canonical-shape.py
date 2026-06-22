#!/usr/bin/env python3
"""check-canonical-shape — enforce OpenClaw's canonical wiki/* frontmatter shape.

Canonical shape (resolved 2026-06-11, see project_wiki_frontmatter_canonical_decision_2026-06-10.md):

```yaml
---
type: <category>           # gbrain → pages.type (top-level only; verified markdown.ts:96-99)
title: [Title]             # gbrain → pages.title
tags: [...]                # gbrain → pages.tags
name: <kebab-slug>         # Claude memory + slug-match check
description: <one-line>    # QMD/gbrain retrieval hook
created: YYYY-MM-DD
updated: YYYY-MM-DD
source: <agent>
---
```

Error classes emitted:
  CANONICAL_MISSING_TYPE     — no top-level `type:` (gbrain can't extract)
  CANONICAL_MISSING_TITLE    — no top-level `title:` (gbrain falls back to filename)
  CANONICAL_METADATA_NESTING — has `metadata:` block (legacy Option A shape)
  CANONICAL_SLUG_MISMATCH    — `name:` doesn't equal filename stem
  CANONICAL_EXPLICIT_SLUG    — has `slug:` (creates SLUG_MISMATCH trap with gbrain auto-derive)

Usage:
  check-canonical-shape.py <path>...     # scan files or dirs
  check-canonical-shape.py --json <path> # machine-readable
  check-canonical-shape.py --wiki        # all OpenClaw wiki/* across workspaces

Exit codes:
  0 — clean
  1 — violations found
  2 — invocation error
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Need PyYAML: pip install pyyaml", file=sys.stderr)
    sys.exit(2)


FM_RE = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n", re.DOTALL)

# Two-agent example: `main` (workspace) + `dev` (workspace-dev). Add more
# workspaces here as your agents.map grows (see ${OPENCLAW_HOME}/config/agents.map).
OPENCLAW_HOME = Path(os.environ.get("OPENCLAW_HOME", Path.home() / ".openclaw"))
WORKSPACE_WIKI_DIRS = [
    OPENCLAW_HOME / "workspace/wiki",
    OPENCLAW_HOME / "workspace-dev/wiki",
]


def check_file(path: Path) -> list[dict]:
    """Returns list of violation dicts for this file."""
    try:
        raw = path.read_text(encoding="utf-8")
    except Exception as e:
        return [{"code": "READ_ERROR", "msg": str(e)}]

    m = FM_RE.match(raw)
    if not m:
        # No frontmatter at all — out of scope for this check; gbrain validate covers it.
        return []

    fm_text = m.group(1)
    try:
        fm = yaml.safe_load(fm_text) or {}
    except yaml.YAMLError as e:
        # YAML parse error — gbrain validate covers it; not our class.
        return [{"code": "YAML_PARSE", "msg": str(e)}]

    if not isinstance(fm, dict):
        return [{"code": "YAML_PARSE", "msg": "frontmatter not a dict"}]

    violations = []

    if "type" not in fm:
        violations.append({
            "code": "CANONICAL_MISSING_TYPE",
            "msg": "no top-level `type:` — gbrain can't extract to pages.type",
        })

    if "title" not in fm:
        violations.append({
            "code": "CANONICAL_MISSING_TITLE",
            "msg": "no top-level `title:` — gbrain falls back to humanized filename",
        })

    # Legacy Option A shape: nested metadata: block. Skill-doc files (with
    # `metadata: {openclaw: {emoji: X}}`) are NOT in scope here — this checker
    # targets wiki entries. We still flag it so the agent decides.
    if isinstance(fm.get("metadata"), dict):
        nested_type = fm["metadata"].get("type")
        nested_title = fm["metadata"].get("title")
        if nested_type or nested_title:
            violations.append({
                "code": "CANONICAL_METADATA_NESTING",
                "msg": f"`metadata:` block contains type/title (legacy Option A shape); "
                       f"promote to top-level. nested type={nested_type!r}",
            })

    if "name" in fm:
        expected = path.stem
        actual = str(fm["name"])
        if actual != expected:
            violations.append({
                "code": "CANONICAL_SLUG_MISMATCH",
                "msg": f"name={actual!r} but filename stem is {expected!r}",
            })

    if "slug" in fm:
        violations.append({
            "code": "CANONICAL_EXPLICIT_SLUG",
            "msg": f"explicit slug={fm['slug']!r} — gbrain auto-derives; remove to avoid SLUG_MISMATCH trap",
        })

    return violations


def walk(target: Path):
    if target.is_file():
        yield target
        return
    for p in sorted(target.rglob("*.md")):
        if p.name == "INDEX.md":
            continue
        yield p


def main() -> int:
    p = argparse.ArgumentParser(prog="check-canonical-shape")
    p.add_argument("paths", nargs="*", help="files or directories to scan")
    p.add_argument("--wiki", action="store_true", help="scan all OpenClaw wiki/* dirs")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.add_argument("--summary", action="store_true", help="print only counts by code")
    args = p.parse_args()

    if not args.paths and not args.wiki:
        p.print_help()
        return 2

    targets = []
    if args.wiki:
        targets.extend([d for d in WORKSPACE_WIKI_DIRS if d.is_dir()])
    targets.extend([Path(x).expanduser() for x in args.paths])

    all_violations: list[dict] = []
    files_scanned = 0
    files_with_violations = 0

    for target in targets:
        if not target.exists():
            print(f"missing: {target}", file=sys.stderr)
            continue
        for path in walk(target):
            files_scanned += 1
            vs = check_file(path)
            if vs:
                files_with_violations += 1
                for v in vs:
                    v["path"] = str(path)
                    all_violations.append(v)

    if args.json:
        print(json.dumps({
            "files_scanned": files_scanned,
            "files_with_violations": files_with_violations,
            "violations": all_violations,
        }, indent=2))
    elif args.summary or not all_violations:
        from collections import Counter
        codes = Counter(v["code"] for v in all_violations)
        print(f"Scanned: {files_scanned} files")
        print(f"With violations: {files_with_violations} files, {len(all_violations)} violations")
        for code, count in sorted(codes.items(), key=lambda x: -x[1]):
            print(f"  {count:5d} × {code}")
    else:
        by_code: dict[str, list[dict]] = {}
        for v in all_violations:
            by_code.setdefault(v["code"], []).append(v)
        for code, items in sorted(by_code.items()):
            print(f"\n=== {code} ({len(items)}) ===")
            for v in items[:20]:
                print(f"  {v['path']}")
                print(f"    → {v['msg']}")
            if len(items) > 20:
                print(f"  ...and {len(items) - 20} more")
        print(f"\nTotal: {len(all_violations)} violations across {files_with_violations}/{files_scanned} files")

    return 1 if all_violations else 0


if __name__ == "__main__":
    sys.exit(main())
