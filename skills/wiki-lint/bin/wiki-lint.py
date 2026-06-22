#!/usr/bin/env python3
"""wiki-lint — graph / link / synthesis-integrity linter for OpenClaw wikis.

Fills the gap left by the existing hygiene layer. None of these check cross-page
integrity:
  - freshness-watch          → mtime/lifespan pruning (wiki/* is evergreen, so skipped)
  - frontmatter-guard        → YAML structure + canonical shape (per-file)
  - openclaw-invariants-check → DR defense fingerprints (per-script)

wiki-lint checks the connective tissue between pages — the thing that rots as the
wiki grows and that humans abandon wikis for not maintaining.

Checks (deterministic, no LLM):
  DANGLING_LINK   [[target]] with no page anywhere in the federated set.
                  Grouped by target = the "pages worth writing" backlog,
                  ranked by how many pages already want them.
  ORPHAN          page with 0 inbound [[links]] AND not listed in any INDEX.md
                  → candidate to cross-link or cold-store.
  DUPLICATE_SLUG  two pages resolving to the same slug → [[link]] ambiguity.
  INDEX_MISSING   page on disk not catalogued in its category INDEX.md.
  INDEX_DEAD      INDEX.md entry pointing to a file that no longer exists.
  STALE_REVIEW    orphan whose `updated:` is older than --stale-days (default 365).
                  Wiki pages are evergreen by policy, so this is a REVIEW flag,
                  never a prune.

Design notes:
  - Link resolution is GLOBAL across all scanned roots (federation-safe) and
    normalizes `_`→`-` + case, so cross-wiki refs and slug drift don't produce
    false danglings.
  - Wiki-links are parsed straight from markdown — NOT gbrain's graph — because
    gbrain typed-edge resolution has known bugs (#1846 bare-name resolver,
    #1847 empty link_type). Markdown is the source of truth.
  - Read-only. Never mutates a page. The LLM-judgement checks (contradictions,
    concept gaps) live in SKILL.md as an on-demand pass, not here.

Usage:
  wiki-lint.py <path>...        scan explicit files/dirs
  wiki-lint.py --wiki           all OpenClaw workspace wikis (default roots)
  wiki-lint.py --json           machine-readable (cron / incident)
  wiki-lint.py --summary        one-line counts
  wiki-lint.py --stale-days N   STALE_REVIEW threshold (default 365)
  wiki-lint.py --top N          max rows shown per section in text mode (default 15)

Exit codes:
  0 — clean (no findings)
  1 — findings present. NORMAL for a living wiki: this is a backlog, not a failure.
  2 — invocation error
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

HOME = Path.home()

# Default federated wiki roots. Non-existent ones are skipped.
# Two-agent example: `main` (workspace) + `dev` (workspace-dev). Add more
# workspaces here as your agents.map grows (see ${OPENCLAW_HOME}/config/agents.map).
OPENCLAW_HOME = Path(os.environ.get("OPENCLAW_HOME", HOME / ".openclaw"))
DEFAULT_WIKI_ROOTS = [
    OPENCLAW_HOME / "workspace" / "wiki",
    OPENCLAW_HOME / "workspace-dev" / "wiki",
]

# Path fragments that are never linted (mirrors freshness-policy.json skip_patterns).
SKIP_DIR_FRAGMENTS = (
    "/.git/",
    "/node_modules/",
    "/cold-storage/",
    "/cold-projects/",
    "/archive/",
    "/quarantine/",
    "/inbox/",
    "/_attachments/",
)

# Structural / navigation / config files: parsed as link SOURCES, but never
# themselves flagged as orphans or counted as duplicate slugs.
STRUCTURAL_NAMES = {
    "INDEX.md", "WIKI.md", "AGENTS.md", "README.md", "MEMORY.md", "SOUL.md",
    "IDENTITY.md", "HEARTBEAT.md", "USER.md", "TOOLS.md", "LESSONS.md",
    "DREAMS.md", "MODEL-ROUTING.md", "CLAUDE.md",
}

WIKILINK_RE = re.compile(r"\[\[\s*([^\]|#]+?)\s*(?:#[^\]|]*)?(?:\|[^\]]*)?\s*\]\]")
MDLINK_RE = re.compile(r"\[[^\]]*\]\(\s*(<?[^)>\s]+?\.md)[^)]*\)")
FM_FIELD_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*?)\s*$")

# Claude-memory filename prefixes that leak into wiki [[links]] as broken refs.
# A [[feedback-x]] / [[project-x]] / [[reference-x]] whose de-prefixed form is a
# real wiki page is a BROKEN_REF the --fix pass auto-repoints to [[x]].
KNOWN_PREFIXES = ("feedback", "project", "reference")


def norm(s: str) -> str:
    """Canonicalise a slug/link target: lowercase, `_`→`-`, drop `.md` + anchors."""
    s = s.strip().lower()
    if s.endswith(".md"):
        s = s[:-3]
    s = s.split("#", 1)[0]
    s = s.replace("_", "-").strip("/")
    # collapse a leading relative path: [[people/bent-dalager]] → bent-dalager
    if "/" in s:
        s = s.rsplit("/", 1)[-1]
    return s.strip()


def parse_frontmatter(text: str) -> dict:
    """Minimal scalar frontmatter parse (stdlib only — no PyYAML dependency)."""
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    block = text[3:end]
    out: dict = {}
    for line in block.splitlines():
        m = FM_FIELD_RE.match(line)
        if m:
            key, val = m.group(1), m.group(2)
            out[key.lower()] = val.strip().strip('"').strip("'")
    return out


def strip_code(text: str) -> str:
    """Drop fenced (``` / ~~~) and inline (`...`) code so template-example
    [[links]] in operating-manual code blocks aren't counted as real edges."""
    out, in_fence, marker = [], False, None
    for line in text.splitlines():
        s = line.lstrip()
        if not in_fence and (s.startswith("```") or s.startswith("~~~")):
            in_fence, marker = True, s[:3]
            continue
        if in_fence and s.startswith(marker):
            in_fence, marker = False, None
            continue
        if not in_fence:
            out.append(line)
    return re.sub(r"`[^`\n]*`", " ", "\n".join(out))


def should_skip(path: Path) -> bool:
    p = "/" + str(path).replace("\\", "/").lstrip("/")
    if path.name == ".DS_Store" or path.name.startswith("."):
        return True
    return any(frag in p for frag in SKIP_DIR_FRAGMENTS)


def parse_date(val: str):
    if not val:
        return None
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", val)
    if not m:
        return None
    try:
        return dt.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        return None


def collect_md(roots) -> list[Path]:
    files: list[Path] = []
    for root in roots:
        root = Path(root)
        if root.is_file() and root.suffix == ".md":
            if not should_skip(root):
                files.append(root)
        elif root.is_dir():
            for p in root.rglob("*.md"):
                if not should_skip(p):
                    files.append(p)
    # dedupe, stable order
    seen, out = set(), []
    for p in files:
        rp = p.resolve()
        if rp not in seen:
            seen.add(rp)
            out.append(p)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True, description="OpenClaw wiki integrity linter")
    ap.add_argument("paths", nargs="*", help="files or dirs to scan")
    ap.add_argument("--wiki", action="store_true", help="scan all OpenClaw workspace wikis")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--summary", action="store_true", help="one-line counts")
    ap.add_argument("--stale-days", type=int, default=365, help="STALE_REVIEW threshold (default 365)")
    ap.add_argument("--top", type=int, default=15, help="rows per section in text mode")
    ap.add_argument("--no-fail", action="store_true",
                    help="exit 0 even when findings exist (cron/ledger mode); "
                         "exit 2 still signals a real invocation error")
    ap.add_argument("--fix", action="store_true",
                    help="auto-repoint BROKEN_REF links ([[prefix-slug]] → [[slug]] "
                         "where the de-prefixed wiki page exists). Mechanical class only.")
    ap.add_argument("--dry-run", action="store_true",
                    help="with --fix, preview the repoints without writing")
    ap.add_argument("--check", metavar="PATH",
                    help="write-path guard: report only dangling [[links]] sourced "
                         "from PATH and exit 1 if any. Resolves against all wiki roots.")
    ap.add_argument("--demote", metavar="SLUGS",
                    help="downgrade dangling [[X]] to backtick `X` for the comma-separated "
                         "slugs (the cold/generic DEMOTE class). Explicit list only; pairs with --dry-run.")
    args = ap.parse_args()

    if args.wiki or (args.check and not args.paths):
        roots = [r for r in DEFAULT_WIKI_ROOTS if Path(r).exists()]
    elif args.paths:
        roots = [Path(p) for p in args.paths]
    else:
        ap.print_usage()
        print("wiki-lint: provide paths, --wiki, or --check PATH", file=sys.stderr)
        return 2

    if not roots:
        print("wiki-lint: no existing roots to scan", file=sys.stderr)
        return 2

    files = collect_md(roots)
    today = dt.date.today()

    pages = []          # non-structural content pages
    structural = []     # INDEX.md / WIKI.md / etc — link sources only
    alias_to_idx = defaultdict(list)   # normalized alias -> [page index]
    index_files = []    # all INDEX.md paths

    for path in files:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        fm = parse_frontmatter(text)
        outbound = {norm(t) for t in WIKILINK_RE.findall(strip_code(text)) if norm(t)}
        rec = {
            "path": str(path),
            "rel": _rel(path),
            "root": _root_label(path),
            "category": path.parent.name,
            "stem": norm(path.stem),
            "name": norm(fm.get("name", "")) if fm.get("name") else "",
            "type": fm.get("type", ""),
            "updated": parse_date(fm.get("updated") or fm.get("created") or ""),
            "outbound": outbound,
        }
        if path.name in STRUCTURAL_NAMES:
            structural.append(rec)
            if path.name == "INDEX.md":
                index_files.append(path)
            continue
        idx = len(pages)
        pages.append(rec)
        for alias in {rec["stem"], rec["name"]} - {""}:
            alias_to_idx[alias].append(idx)

    global_slugs = set(alias_to_idx.keys())

    # ---- inbound link resolution (pages + structural files are all sources) ----
    linked_idxs = set()
    dangling = defaultdict(list)   # target -> [source rel paths]
    for src in pages + structural:
        for target in src["outbound"]:
            hits = alias_to_idx.get(target)
            if hits:
                for i in hits:
                    if pages[i]["path"] != src["path"]:
                        linked_idxs.add(i)
            else:
                dangling[target].append(src["rel"])

    # ---- index-referenced set (markdown links inside INDEX.md files) ----
    index_ref_resolved = set()       # resolved absolute page paths catalogued by some INDEX.md
    index_dead = []                  # (index_rel, missing_target_rel)
    for ipath in index_files:
        try:
            itext = ipath.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for raw in MDLINK_RE.findall(itext):
            tgt = raw.strip("<>")
            resolved = (ipath.parent / tgt).resolve()
            if resolved.exists():
                index_ref_resolved.add(str(resolved))
            else:
                index_dead.append((_rel(ipath), tgt))
        # [[wikilinks]] inside an INDEX also count as cataloguing
        for wl in WIKILINK_RE.findall(strip_code(itext)):
            for i in alias_to_idx.get(norm(wl), []):
                index_ref_resolved.add(str(Path(pages[i]["path"]).resolve()))

    # ---- INDEX_MISSING: content page in a dir whose INDEX.md doesn't list it ----
    index_dirs = {ip.parent.resolve() for ip in index_files}
    index_missing = []
    for i, pg in enumerate(pages):
        parent = Path(pg["path"]).parent.resolve()
        if parent in index_dirs:
            if str(Path(pg["path"]).resolve()) not in index_ref_resolved:
                index_missing.append(pg["rel"])

    # ---- duplicate slugs (intra-wiki = real ambiguity; cross-wiki = federation-dependent) ----
    duplicates = []
    for alias, idxs in alias_to_idx.items():
        distinct = sorted({pages[i]["path"] for i in idxs})
        if len(distinct) > 1:
            roots_involved = {_root_label(Path(p)) for p in distinct}
            scope = "intra-wiki" if len(roots_involved) == 1 else "cross-wiki"
            duplicates.append({
                "slug": alias,
                "scope": scope,
                "paths": [_rel(Path(p)) for p in distinct],
            })
    duplicates.sort(key=lambda d: (d["scope"] != "intra-wiki", d["slug"]))

    # ---- orphans + stale-review ----
    orphans, stale = [], []
    for i, pg in enumerate(pages):
        if i in linked_idxs:
            continue
        if str(Path(pg["path"]).resolve()) in index_ref_resolved:
            continue
        orphans.append(pg["rel"])
        if pg["updated"] and (today - pg["updated"]).days > args.stale_days:
            stale.append((pg["rel"], pg["updated"].isoformat(),
                          (today - pg["updated"]).days))

    dangling_ranked = sorted(dangling.items(), key=lambda kv: (-len(kv[1]), kv[0]))

    # ---- --check PATH: write-path guard (only this file's danglings) ----
    if args.check:
        check_abs = str(Path(args.check).resolve())
        scanned_abs = {str(p.resolve()) for p in files}
        if check_abs not in scanned_abs:
            print(f"wiki-lint --check: {args.check} is not a scanned wiki page "
                  f"(it must resolve to a file under a wiki root) — nothing checked.",
                  file=sys.stderr)
            return 2
        check_rel = _rel(Path(check_abs))
        hits = [(t, srcs) for t, srcs in dangling_ranked if check_rel in srcs]
        if not hits:
            print(f"wiki-lint --check: {check_rel} — all [[links]] resolve ✓")
            return 0
        print(f"wiki-lint --check: {check_rel} has {len(hits)} unresolved [[link]](s):")
        for t, _ in hits:
            sug = _repoint(t, global_slugs)
            tip = (f"  → [[{sug}]]" if sug else
                   "  (promote the target to a wiki page, or downgrade to a "
                   "markdown/backtick link — see wiki/WIKI.md)")
            print(f"    [[{t}]]{tip}")
        return 1

    # ---- --fix: auto-repoint the deterministic BROKEN_REF class only ----
    if args.fix:
        repoint = {t: _repoint(t, global_slugs) for t in dangling}
        repoint = {t: c for t, c in repoint.items() if c}
        if not repoint:
            print("wiki-lint --fix: no auto-fixable BROKEN_REF links "
                  "(prefix → existing-slug) found.")
            return 0
        fixpat = re.compile(r"\[\[\s*([^\]|#]+?)\s*(#[^\]|]*)?(\|[^\]]*)?\s*\]\]")
        total, nfiles = 0, 0
        for path in files:
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            cnt = [0]

            def repl(m):
                n = norm(m.group(1))
                if n in repoint:
                    cnt[0] += 1
                    return f"[[{repoint[n]}{m.group(2) or ''}{m.group(3) or ''}]]"
                return m.group(0)

            new = fixpat.sub(repl, text)
            if cnt[0]:
                if not args.dry_run:
                    path.write_text(new, encoding="utf-8")
                nfiles += 1
                total += cnt[0]
                print(f"  {'would fix' if args.dry_run else 'fixed'} {cnt[0]:>2}  {_rel(path)}")
        verb = "Would repoint" if args.dry_run else "Repointed"
        print(f"\nwiki-lint --fix: {verb} {total} link(s) across {nfiles} file(s) "
              f"({len(repoint)} BROKEN_REF target(s) → existing pages):")
        for t, c in sorted(repoint.items()):
            print(f"    [[{t}]] → [[{c}]]")
        if args.dry_run:
            print("(dry run — nothing written. Re-run without --dry-run to apply.)")
        return 0

    # ---- --demote SLUGS: downgrade specified dangling [[X]] → backtick `X` ----
    if args.demote:
        demote_set = {norm(s) for s in args.demote.split(",") if s.strip()}
        dempat = re.compile(r"\[\[\s*([^\]|#]+?)\s*(?:#[^\]|]*)?(?:\|[^\]]*)?\s*\]\]")
        total, nfiles = 0, 0
        for path in files:
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            cnt = [0]

            def repl(m):
                inner = m.group(1).strip()
                n = norm(inner)
                if n in demote_set and n not in global_slugs:
                    cnt[0] += 1
                    return f"`{inner}`"
                return m.group(0)

            new = dempat.sub(repl, text)
            if cnt[0]:
                if not args.dry_run:
                    path.write_text(new, encoding="utf-8")
                nfiles += 1
                total += cnt[0]
                print(f"  {'would demote' if args.dry_run else 'demoted'} {cnt[0]:>2}  {_rel(path)}")
        verb = "Would downgrade" if args.dry_run else "Downgraded"
        print(f"\nwiki-lint --demote: {verb} {total} link(s) → backtick across {nfiles} file(s).")
        if args.dry_run:
            print("(dry run — nothing written.)")
        return 0

    findings = {
        "scanned_roots": [str(r) for r in roots],
        "pages": len(pages),
        "structural_files": len(structural),
        "counts": {
            "dangling_targets": len(dangling),
            "dangling_refs": sum(len(v) for v in dangling.values()),
            "duplicate_slugs": len(duplicates),
            "orphans": len(orphans),
            "index_missing": len(index_missing),
            "index_dead": len(index_dead),
            "stale_review": len(stale),
        },
        "dangling": [{"target": t, "refs": srcs} for t, srcs in dangling_ranked],
        "duplicate_slugs": duplicates,
        "orphans": sorted(orphans),
        "index_missing": sorted(index_missing),
        "index_dead": [{"index": i, "target": t} for i, t in index_dead],
        "stale_review": [{"page": p, "updated": u, "age_days": d} for p, u, d in
                         sorted(stale, key=lambda x: -x[2])],
    }
    total = sum(findings["counts"].values()) - findings["counts"]["dangling_refs"]

    if args.json:
        print(json.dumps(findings, indent=2))
        return 0 if (total == 0 or args.no_fail) else 1

    if args.summary:
        c = findings["counts"]
        print(f"wiki-lint: dangling={c['dangling_targets']}t/{c['dangling_refs']}r "
              f"dup={c['duplicate_slugs']} orphan={c['orphans']} "
              f"index_missing={c['index_missing']} index_dead={c['index_dead']} "
              f"stale={c['stale_review']}  ({findings['pages']} pages)")
        return 0 if (total == 0 or args.no_fail) else 1

    _print_text(findings, args.top)
    return 0 if (total == 0 or args.no_fail) else 1


def _rel(path: Path) -> str:
    s = str(path)
    marker = "/.openclaw/"
    return s.split(marker, 1)[1] if marker in s else s


def _root_label(path: Path) -> str:
    m = re.search(r"workspace[^/]*", str(path))
    return m.group(0) if m else "?"


def _repoint(target: str, slugs):
    """If `target` is a memory-style prefixed slug (feedback-/project-/reference-)
    whose de-prefixed form is an existing wiki page, return that slug; else None.
    This is the deterministic BROKEN_REF repoint."""
    for p in KNOWN_PREFIXES:
        if target.startswith(p + "-"):
            cand = target[len(p) + 1:]
            if cand in slugs:
                return cand
    return None


def _print_text(f: dict, top: int) -> None:
    c = f["counts"]
    total = sum(c.values()) - c["dangling_refs"]
    if total == 0:
        print(f"wiki-lint: clean — {f['pages']} pages, "
              f"{len(f['scanned_roots'])} root(s). No findings.")
        return

    print(f"wiki-lint: {total} finding(s) across {len(f['scanned_roots'])} root(s), "
          f"{f['pages']} pages\n")

    if f["dangling"]:
        print(f"▸ DANGLING_LINK — pages worth writing "
              f"({c['dangling_targets']} targets, {c['dangling_refs']} refs)")
        for d in f["dangling"][:top]:
            ex = ", ".join(d["refs"][:3]) + (" …" if len(d["refs"]) > 3 else "")
            print(f"    {d['target']:<34} ← {len(d['refs'])} ref(s)  {ex}")
        if len(f["dangling"]) > top:
            print(f"    … +{len(f['dangling']) - top} more (--json)")
        print()

    if f["duplicate_slugs"]:
        intra = [d for d in f["duplicate_slugs"] if d["scope"] == "intra-wiki"]
        print(f"▸ DUPLICATE_SLUG — [[link]] ambiguity ({c['duplicate_slugs']}; "
              f"{len(intra)} intra-wiki = real)")
        for d in f["duplicate_slugs"][:top]:
            tag = "" if d["scope"] == "intra-wiki" else \
                "   (cross-wiki — separate namespace unless federated)"
            print(f"    {d['slug']}{tag}")
            for p in d["paths"]:
                print(f"        {p}")
        print()

    if f["orphans"]:
        print(f"▸ ORPHAN — no inbound links, not in any INDEX ({c['orphans']})")
        for o in f["orphans"][:top]:
            print(f"    {o}")
        if len(f["orphans"]) > top:
            print(f"    … +{len(f['orphans']) - top} more (--json)")
        print()

    if f["index_missing"] or f["index_dead"]:
        print(f"▸ INDEX drift — missing:{c['index_missing']} dead:{c['index_dead']}")
        for m in f["index_missing"][:top]:
            print(f"    missing: {m}")
        for d in f["index_dead"][:top]:
            print(f"    dead:    {d['index']} → {d['target']}")
        print()

    if f["stale_review"]:
        print(f"▸ STALE_REVIEW — orphan + aged (review, not prune) ({c['stale_review']})")
        for s in f["stale_review"][:top]:
            print(f"    {s['page']:<46} {s['updated']} ({s['age_days']}d)")
        print()

    # single highest-value next action
    intra_dupes = [d for d in f["duplicate_slugs"] if d["scope"] == "intra-wiki"]
    if intra_dupes:
        tip = (f"resolve {len(intra_dupes)} intra-wiki duplicate slug(s) — they make "
               f"[[links]] ambiguous (e.g. `{intra_dupes[0]['slug']}`)")
    elif f["dangling"]:
        t = f["dangling"][0]
        tip = (f"write `{t['target']}` — {len(t['refs'])} page(s) already link to it"
               if len(t["refs"]) > 1 else
               "review the dangling backlog; write the high-ref targets first")
    elif f["orphans"]:
        tip = f"cross-link or cold-store {c['orphans']} orphan page(s)"
    else:
        tip = "tidy INDEX drift"
    print(f"Top action: {tip}")
    print("No files changed.")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
