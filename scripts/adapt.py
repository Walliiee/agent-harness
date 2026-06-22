#!/usr/bin/env python3
"""adapt.py — fit the agent-harness templates to your project.

Pure stdlib (Python 3.11+). No pip deps, no Jinja2 — a tiny ${VAR} substituter
runs anywhere. The flow is: probe → render → validate → report.

  probe()    detect an existing setup (openclaw.json / .claude / codex config),
             infer OPENCLAW_HOME and any existing agent ids.
  render()   walk *.template files + ${VAR} placeholders under bin/skills/config,
             substitute values, write to a staging dir (dry-run) or --out.
  validate() check no ${VAR} placeholders remain and that scrub-audit patterns
             don't reappear from user-supplied input.
  report()   print files written, vars used, and next steps.

Default is DRY-RUN: nothing is written to your real home; a staging dir gets the
rendered files and a diff-style listing is printed. Pass --apply to write for
real. See docs/getting-started.md.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Roots we copy into the user's setup. Under each, *.template files are rendered
# (placeholders substituted) and renamed (suffix stripped); every OTHER file is
# copied VERBATIM — so shell scripts keep their own ${VAR} expansions untouched.
RENDER_ROOTS = ["bin", "skills", "config", "launchd", "dr"]

# The harness placeholders adapt.py owns. These are the ONLY ${VAR} tokens it
# substitutes or treats as "must be filled" — shell/JSON variables that happen to
# share the ${...} syntax in copied files are left alone.
HARNESS_VARS = {"OPENCLAW_HOME", "HOME", "GH_ORG", "HARNESS_TG_CHAT_ID"}
# Optional vars: if the user leaves them unset, we fill with empty (inert) rather
# than reporting them as "must provide". Everything else is required.
OPTIONAL_VARS = {"HARNESS_TG_CHAT_ID"}
PLACEHOLDER_RE = re.compile(
    r"\$\{(" + "|".join(sorted(HARNESS_VARS)) + r")\}"
)

# Patterns that must never appear in rendered output, even from user input.
# Mirrors scripts/scrub-audit.sh — keeps the engine from re-introducing a leak
# via a careless --gh-org or --telegram-chat-id value.
LEAK_PATTERNS = [
    r"/Users/[a-z][a-z0-9_-]*",          # someone's absolute home path
    r"\bsk-[A-Za-z0-9]{20,}\b",          # OpenAI-style key
    r"\b[a-f0-9]{40,}\b",                 # long hex secret
]


# ----------------------------------------------------------------------------- probe
def probe() -> dict:
    """Detect an existing target setup; return inferred defaults."""
    found: dict = {"home": None, "agents": [], "sources": []}
    home_env = os.environ.get("OPENCLAW_HOME")
    candidates = [
        Path(home_env) if home_env else None,
        Path.home() / ".openclaw",
    ]
    for cand in candidates:
        if cand and (cand / "openclaw.json").is_file():
            found["home"] = str(cand)
            try:
                cfg = json.loads((cand / "openclaw.json").read_text())
                agents = cfg.get("agents", {}).get("list", [])
                found["agents"] = [a.get("id") for a in agents if isinstance(a, dict) and a.get("id")]
            except (json.JSONDecodeError, OSError):
                pass
            break

    # Secondary signals: Claude Code / Codex configs hint the home exists.
    for hint in (Path.home() / ".claude" / "settings.json",
                 Path.home() / ".codex" / "config.toml",
                 Path.cwd() / ".claude" / "settings.json"):
        if hint.is_file() and not found["home"]:
            found["home"] = str(Path.home() / ".openclaw")

    return found


# ----------------------------------------------------------------------------- vars
def build_vars(args, probed: dict) -> dict:
    """Resolve the substitution map from probe results + CLI args (args win)."""
    home = args.home or probed.get("home") or str(Path.home() / ".openclaw")
    home = os.path.expanduser(home)
    v = {
        "OPENCLAW_HOME": home,
        "HOME": str(Path.home()),
        "GH_ORG": args.gh_org or "",
        "HARNESS_TG_CHAT_ID": args.telegram_chat_id or "",
    }
    return v


def parse_agents(args, probed: dict) -> list[tuple[str, str, str]]:
    """Return [(id, workspace-dir, label)]. CLI > probe > default(main,dev)."""
    raw = args.agents
    if not raw and probed.get("agents"):
        raw = ",".join(probed["agents"])
    if not raw:
        raw = "main,dev"
    rows = []
    label_default = {"main": "Orchestrator", "dev": "Developer"}
    for aid in [a.strip() for a in raw.split(",") if a.strip()]:
        ws = "workspace" if aid == "main" else f"workspace-{aid}"
        rows.append((aid, ws, label_default.get(aid, aid.capitalize())))
    return rows


# ----------------------------------------------------------------------------- render
def substitute(text: str, vars: dict) -> tuple[str, set[str]]:
    """Replace ${VAR} tokens. Returns (rendered, set-of-unfilled-var-names)."""
    unfilled: set[str] = set()

    def repl(m: re.Match) -> str:
        name = m.group(1)
        val = vars.get(name)
        if val:                       # non-empty value → substitute
            return val
        if name in OPTIONAL_VARS:     # optional + unset → fill empty (inert)
            return ""
        unfilled.add(name)
        return m.group(0)             # leave token in place for validate() to catch

    return PLACEHOLDER_RE.sub(repl, text), unfilled


def render(vars: dict, agents: list, out_dir: Path) -> dict:
    """Copy RENDER_ROOTS into out_dir, substituting only *.template files.

    *.template files: substitute harness ${VAR}s and drop the suffix.
    Everything else: copy byte-for-byte (shell ${VAR} expansions untouched).
    Returns {"written": [rel_paths], "unfilled": {var: [files]}, "rendered": [rel]}
    where "rendered" lists only files produced FROM a *.template (the only ones
    whose ${VAR}s adapt.py is responsible for filling).
    """
    written: list[str] = []
    rendered_files: list[str] = []
    unfilled: dict[str, list[str]] = {}

    for root in RENDER_ROOTS:
        base = REPO / root
        if not base.exists():
            continue
        for src in base.rglob("*"):
            if src.is_dir() or "/.git/" in str(src):
                continue
            rel = src.relative_to(REPO)
            is_template = rel.name.endswith(".template")
            dest_rel = Path(str(rel)[: -len(".template")]) if is_template else rel
            dest = out_dir / dest_rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            if is_template:
                try:
                    raw = src.read_text()
                except (UnicodeDecodeError, OSError):
                    dest.write_bytes(src.read_bytes())  # binary template: copy as-is
                    written.append(str(dest_rel))
                    continue
                rendered, miss = substitute(raw, vars)
                for var in miss:
                    unfilled.setdefault(var, []).append(str(dest_rel))
                dest.write_text(rendered)
                rendered_files.append(str(dest_rel))
            else:
                dest.write_bytes(src.read_bytes())       # verbatim copy
            written.append(str(dest_rel))

    # agents.map is special: synthesize it from the parsed roster.
    agents_map = out_dir / "config" / "agents.map"
    agents_map.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# agents.map — generated by scripts/adapt.py", "# <id> <workspace-dir> <persona-label>", ""]
    lines += [f"{aid}\t{ws}\t{label}" for aid, ws, label in agents]
    agents_map.write_text("\n".join(lines) + "\n")
    if "config/agents.map" not in written:
        written.append("config/agents.map")
    rendered_files.append("config/agents.map")

    return {
        "written": sorted(set(written)),
        "unfilled": unfilled,
        "rendered": sorted(set(rendered_files)),
    }


# ----------------------------------------------------------------------------- validate
def validate(out_dir: Path, rendered: list[str], vars: dict | None = None) -> list[str]:
    """Return a list of problems: unfilled harness placeholders or leaks.

    Two distinct checks:
      * Leftover ${VAR}: only meaningful in files we RENDERED from a *.template.
        Verbatim-copied bin/skill files legitimately keep ${OPENCLAW_HOME} for
        runtime env resolution, so they are NOT checked for placeholders.
      * Leaks: scanned across ALL output. The configured OPENCLAW_HOME / HOME are
        expected (they replace placeholders), so only OTHER absolute home paths
        are flagged.
    """
    problems: list[str] = []
    leak_res = [re.compile(p) for p in LEAK_PATTERNS]
    rendered_set = set(rendered)
    allowed_paths = set()
    if vars:
        for key in ("OPENCLAW_HOME", "HOME"):
            if vars.get(key):
                allowed_paths.add(vars[key])
    for f in out_dir.rglob("*"):
        if f.is_dir():
            continue
        try:
            text = f.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        rel = f.relative_to(out_dir)
        if str(rel) in rendered_set:
            for m in PLACEHOLDER_RE.finditer(text):
                problems.append(f"unfilled ${{{m.group(1)}}} in {rel}")
        for rex in leak_res:
            for m in rex.finditer(text):
                hit = m.group(0)
                # A /Users/... path that is exactly (a prefix of) the configured
                # home is intentional; anything else is a foreign path leak.
                if any(hit == p or p.startswith(hit + "/") or hit.startswith(p) for p in allowed_paths):
                    continue
                problems.append(f"possible leak '{hit}' in {rel}")
    # De-dup while keeping order.
    seen, out = set(), []
    for p in problems:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


# ----------------------------------------------------------------------------- report
def report(vars: dict, agents: list, result: dict, problems: list, apply: bool, out_dir: Path) -> int:
    mode = "APPLY" if apply else "DRY-RUN"
    print(f"\n=== agent-harness adapt — {mode} ===\n")
    print("Variables used:")
    for k, val in vars.items():
        shown = val if val else "(unset)"
        print(f"  ${{{k}}} = {shown}")
    print("\nAgents:")
    for aid, ws, label in agents:
        print(f"  {aid:<10} {ws:<22} {label}")

    print(f"\nFiles rendered ({len(result['written'])}) → {out_dir}")
    for rel in result["written"]:
        print(f"  {'write' if apply else 'stage'}: {rel}")

    if result["unfilled"]:
        print("\nUnfilled variables (you must provide these):")
        for var, files in sorted(result["unfilled"].items()):
            print(f"  ${{{var}}} — needed by {len(files)} file(s), e.g. {files[0]}")

    if problems:
        print(f"\n✗ validate FAILED ({len(problems)} issue(s)):")
        for p in problems[:40]:
            print(f"    {p}")
        if len(problems) > 40:
            print(f"    ... and {len(problems) - 40} more")
        print("\nFix the inputs (--gh-org, --home, agents.map) and re-run.")
        return 1

    print("\n✓ validate clean — no unfilled placeholders, no leaks.")
    if apply:
        print("\nNext steps:")
        print("  1. bash launchd/install-launchagents.sh --home <your home>   # install schedulers")
        print("  2. bash dr/smoke-test.sh                         # verify DR wiring")
        print("  3. bash scripts/scrub-audit.sh                   # confirm no leaks")
    else:
        print("\nDry-run only — nothing written to your real setup.")
        print("Re-run with --apply --out <dir> to write for real.")
    return 0


# ----------------------------------------------------------------------------- main
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Fit the agent-harness to your project.")
    ap.add_argument("--home", help="OPENCLAW_HOME (default: probe, else ~/.openclaw)")
    ap.add_argument("--gh-org", help="GitHub org/owner for workspace remotes (${GH_ORG})")
    ap.add_argument("--agents", help="comma-separated agent ids (default: main,dev)")
    ap.add_argument("--telegram-chat-id", help="optional notification channel id")
    ap.add_argument("--out", help="output dir (default: a temp staging dir on dry-run)")
    ap.add_argument("--apply", action="store_true", help="write for real (default: dry-run)")
    ap.add_argument("--probe-only", action="store_true", help="print what was detected and exit")
    args = ap.parse_args(argv)

    probed = probe()
    if args.probe_only:
        print(json.dumps(probed, indent=2))
        return 0

    vars = build_vars(args, probed)
    agents = parse_agents(args, probed)

    if args.out:
        out_dir = Path(os.path.expanduser(args.out))
    elif args.apply:
        out_dir = Path(vars["OPENCLAW_HOME"])
    else:
        out_dir = Path(tempfile.mkdtemp(prefix="agent-harness-staging-"))
    out_dir.mkdir(parents=True, exist_ok=True)

    result = render(vars, agents, out_dir)
    problems = validate(out_dir, result["rendered"], vars)
    return report(vars, agents, result, problems, args.apply, out_dir)


if __name__ == "__main__":
    sys.exit(main())
