#!/usr/bin/env python3
"""Rewrite wiki/* frontmatter to the canonical hybrid shape.

Gbrain-consumed fields go first (type, title, tags) so they're visually obvious
and survive hand-editing. Claude/QMD convenience fields (name, description) come
right after. Other metadata fields preserved at top level.

Source data: current files use `name + metadata.{type,tags,...}` shape from the
2026-06-10 normalization pass. We promote `metadata.*` to top level, derive `title`
from the H1, drop the `metadata:` nesting.
"""
from __future__ import annotations
import argparse
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Need PyYAML: pip install pyyaml")
    sys.exit(1)


# Default — overridable via --wiki-root <path>.
OPENCLAW_HOME = Path(os.environ.get("OPENCLAW_HOME", Path.home() / ".openclaw"))
WIKI_ROOT = OPENCLAW_HOME / "workspace" / "wiki"

# Order of top-level keys in the output. Anything not in this list comes after,
# alphabetical. The first three are what gbrain extracts to dedicated columns.
CANONICAL_ORDER = [
    "type",
    "title",
    "tags",
    "name",
    "description",
    "created",
    "updated",
    "source",
]


def derive_title_from_h1(body: str, fallback: str) -> str:
    """First non-empty `# ...` line in the body. Strips trailing whitespace."""
    for line in body.splitlines():
        m = re.match(r"^#\s+(.+?)\s*$", line)
        if m:
            return m.group(1).strip()
    return fallback


def derive_type_from_path(rel_path: Path) -> str:
    """Folder-based type inference, matches gbrain's inferType()."""
    parts = rel_path.parts
    if "people" in parts:
        return "person"
    if "companies" in parts:
        return "company"
    if "meetings" in parts:
        return "meeting"
    if "tools" in parts:
        return "tool"
    if "concepts" in parts:
        return "concept"
    if "projects" in parts:
        return "project"
    if "agent-behaviors" in parts:
        return "agent-behavior"
    return "reference"


def transform_file(path: Path) -> tuple[bool, str]:
    """Returns (changed, reason)."""
    raw = path.read_text()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", raw, re.DOTALL)
    if not m:
        return (False, "no frontmatter")

    fm_text, body = m.group(1), m.group(2)
    try:
        fm = yaml.safe_load(fm_text) or {}
    except yaml.YAMLError as e:
        return (False, f"yaml parse error: {e}")

    if not isinstance(fm, dict):
        return (False, "frontmatter not a dict")

    metadata = fm.get("metadata", {}) if isinstance(fm.get("metadata"), dict) else {}

    rel = path.relative_to(WIKI_ROOT)
    new_fm: dict = {}

    # 1. type — top-level wins, else metadata.type, else folder-derived
    new_fm["type"] = fm.get("type") or metadata.get("type") or derive_type_from_path(rel)

    # 2. title — top-level wins, else metadata.title, else H1, else humanized filename
    fallback_title = path.stem.replace("-", " ").title()
    new_fm["title"] = (
        fm.get("title")
        or metadata.get("title")
        or derive_title_from_h1(body, fallback_title)
    )

    # 3. tags — top-level wins, else metadata.tags
    tags = fm.get("tags") or metadata.get("tags")
    if tags:
        new_fm["tags"] = tags

    # 4. name — kebab slug matching filename (Claude memory convention)
    new_fm["name"] = fm.get("name") or path.stem

    # 5. description — preserve as-is; gbrain ignores but QMD/Claude memory use it
    desc = fm.get("description")
    if desc:
        new_fm["description"] = desc

    # 6. dates + source
    for key in ("created", "updated", "source"):
        val = fm.get(key) or metadata.get(key)
        if val:
            new_fm[key] = val

    # 7. Preserve any other top-level or metadata keys (alphabetical) — but NOT
    #    the keys we've already placed and NOT `metadata` itself.
    used = set(new_fm.keys()) | {"metadata", "node_type"}
    extras: dict = {}
    for k, v in fm.items():
        if k not in used:
            extras[k] = v
    for k, v in metadata.items():
        if k not in used and k not in extras:
            extras[k] = v
    for k in sorted(extras.keys()):
        new_fm[k] = extras[k]

    # Render YAML with sort_keys=False to preserve our insertion order.
    new_fm_text = yaml.safe_dump(new_fm, sort_keys=False, allow_unicode=True, default_flow_style=False).rstrip()

    new_raw = f"---\n{new_fm_text}\n---\n{body}"
    if new_raw == raw:
        return (False, "no change")

    path.write_text(new_raw)
    return (True, f"type={new_fm['type']} title={new_fm['title'][:40]!r}")


def main():
    global WIKI_ROOT
    parser = argparse.ArgumentParser(description="Canonicalize wiki/* frontmatter to the hybrid shape.")
    parser.add_argument(
        "--wiki-root",
        type=Path,
        default=WIKI_ROOT,
        help=f"Wiki root directory to canonicalize. Default: {WIKI_ROOT}",
    )
    parser.add_argument("--dry-run", action="store_true", help="Show changes without writing.")
    args = parser.parse_args()
    WIKI_ROOT = args.wiki_root.expanduser().resolve()
    if not WIKI_ROOT.is_dir():
        print(f"ERROR: {WIKI_ROOT} is not a directory", file=sys.stderr)
        sys.exit(2)
    print(f"Canonicalizing wiki root: {WIKI_ROOT}")
    if args.dry_run:
        print("(dry-run — no files will be written)")
    changed = 0
    unchanged = 0
    errors = 0
    for path in sorted(WIKI_ROOT.rglob("*.md")):
        # Skip INDEX.md — it's a flat index, no frontmatter.
        if path.name == "INDEX.md":
            continue
        if args.dry_run:
            # Re-implement read-only check: read original, transform in-memory, compare.
            try:
                original = path.read_text()
                did_change, reason = transform_file(path)
                if did_change:
                    # transform_file already wrote — undo
                    path.write_text(original)
            except Exception as e:
                errors += 1
                print(f"ERROR: {path.relative_to(WIKI_ROOT)} → {e}")
                continue
        else:
            try:
                did_change, reason = transform_file(path)
            except Exception as e:
                errors += 1
                print(f"ERROR: {path.relative_to(WIKI_ROOT)} → {e}")
                continue
        if did_change:
            changed += 1
            print(f"  ✓ {path.relative_to(WIKI_ROOT)}: {reason}")
        else:
            unchanged += 1
    print(f"\nChanged: {changed}, unchanged: {unchanged}, errors: {errors}")


if __name__ == "__main__":
    main()
