#!/usr/bin/env bash
# bootstrap.sh — fresh-machine setup for an OpenClaw agent-harness stack.
#
# Idempotent. Safe to re-run. Each step checks current state before acting.
# Order: prereqs (brew/bun/ollama/npm) → system dirs → repos → bun link →
# deploy snapshots back to live paths → LaunchAgents → openclaw doctor →
# handoff to restore-gbrain.sh / restore-qmd.sh.
#
# This script does NOT restore secrets. See secrets/README.md for the manual
# enumeration. Run this script first, then populate secrets, then run the
# restore-*.sh scripts.
#
# OPENCLAW_HOME is the .openclaw install dir itself (defaults to $HOME/.openclaw).
# Scripts live at ${OPENCLAW_HOME}/bin, config at ${OPENCLAW_HOME}/config, etc.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----- args -----
#   --home PATH    set OPENCLAW_HOME (wins over the $OPENCLAW_HOME env var)
#   --agents LIST  accepted for CLI symmetry with adapt.py / the docs, but a
#                  no-op here: bootstrap derives its component set from the
#                  workspaces manifest, not from an agent list.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --home)     OPENCLAW_HOME="${2:?--home needs a path}"; shift 2 ;;
    --home=*)   OPENCLAW_HOME="${1#*=}"; shift ;;
    --agents)   shift 2 ;;
    --agents=*) shift ;;
    *)          shift ;;
  esac
done
: "${OPENCLAW_HOME:=$HOME/.openclaw}"
OPENCLAW_HOME="${OPENCLAW_HOME/#\~/$HOME}"
# The repo ships templates; restore-workspaces uses the .template manifest.
MANIFEST="$SCRIPT_DIR/workspaces.manifest.yaml.template"

# ----- output helpers -----
c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
step() { printf '\n%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()   { printf '   %s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '   %s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
err()  { printf '   %s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }
abort(){ err "$1"; exit 1; }

# ===== Preflight =====
step "Preflight"
[[ "$(uname -s)" == "Darwin" ]] || abort "macOS only — detected $(uname -s)"
ok "macOS detected ($(sw_vers -productVersion))"

ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then BREW_PREFIX="/opt/homebrew"; else BREW_PREFIX="/usr/local"; fi
ok "Architecture: $ARCH  (brew prefix: $BREW_PREFIX)"

# ===== 1. Homebrew =====
step "Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found — installing"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  ok "brew already installed ($(brew --version | head -1))"
fi
eval "$($BREW_PREFIX/bin/brew shellenv)"

# ===== 2. Brew formulae =====
# We check `command -v` first to avoid installing a duplicate when the binary
# already exists on PATH from another brew prefix (some setups have both
# /opt/homebrew and /usr/local). Falls back to `brew list` in case the binary
# name doesn't match the formula name (e.g. postgresql@17 → psql).
step "Brew formulae"
declare -A brew_check_cmd=(
  [postgresql@17]=psql
  [node]=node
  [gh]=gh
  [jq]=jq
  [ollama]=ollama
)
for pkg in postgresql@17 node gh jq ollama; do
  probe="${brew_check_cmd[$pkg]}"
  if command -v "$probe" >/dev/null 2>&1; then
    ok "$pkg present on PATH ($(command -v "$probe"))"
  elif brew list --formula --versions "$pkg" >/dev/null 2>&1; then
    ok "$pkg installed via brew (not on PATH yet)"
  else
    warn "$pkg missing — installing"
    brew install "$pkg" || abort "brew install $pkg failed"
  fi
done

if ! command -v psql >/dev/null 2>&1; then
  brew link --force postgresql@17 || warn "brew link postgresql@17 failed"
fi

if ! brew services list | grep -qE '^postgresql@17\s+started'; then
  brew services start postgresql@17 || warn "brew services start postgresql@17 failed"
else
  ok "postgresql@17 service running"
fi

if ! brew services list | grep -qE '^ollama\s+started'; then
  brew services start ollama || warn "brew services start ollama failed"
else
  ok "ollama service running"
fi

# ===== 3. Bun runtime (gbrain is a Bun TypeScript app) =====
step "Bun runtime"
if ! command -v bun >/dev/null 2>&1 && [[ ! -x "$HOME/.bun/bin/bun" ]]; then
  warn "bun missing — installing"
  curl -fsSL https://bun.sh/install | bash || abort "bun install failed"
fi
export PATH="$HOME/.bun/bin:$PATH"
ok "bun: $(bun --version 2>/dev/null || echo unknown)"

# Add bun to PATH in ~/.zshrc if not present
ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"
if ! grep -q '.bun/bin' "$ZSHRC"; then
  printf '\n# Bun\nexport PATH="$HOME/.bun/bin:$PATH"\n' >> "$ZSHRC"
  ok "Added bun to ~/.zshrc PATH"
fi

# ===== 4. Ollama embedding model =====
step "Ollama embedding model (bge-m3)"
# gbrain's ~/.gbrain/config.json sets embedding_model=ollama:bge-m3
if ollama list 2>/dev/null | awk '{print $1}' | grep -q '^bge-m3'; then
  ok "bge-m3 already pulled"
else
  warn "Pulling bge-m3 (1.2 GB) — first time only"
  ollama pull bge-m3 || warn "ollama pull bge-m3 failed (gbrain embeddings won't work until fixed)"
fi

# ===== 5. Global npm packages =====
step "Global npm packages"
npm_pkgs=(openclaw "@tobilu/qmd" "@openai/codex" clawpatch)
for pkg in "${npm_pkgs[@]}"; do
  if npm ls -g --depth=0 2>/dev/null | grep -qE "[├└]── (${pkg//\//\\/}@|${pkg//\//\\/} )"; then
    ok "$pkg already installed globally"
  else
    warn "$pkg missing — installing"
    npm install -g "$pkg" || abort "npm install -g $pkg failed"
  fi
done

# ===== 6. System directories =====
step "System directories"
dirs=(
  "$OPENCLAW_HOME"
  "$OPENCLAW_HOME/bin"
  "$OPENCLAW_HOME/logs"
  "$OPENCLAW_HOME/credentials"
  "$OPENCLAW_HOME/credentials/auth-profiles"
  "$OPENCLAW_HOME/service-env"
  "$HOME/.gbrain"
  "$HOME/.gbrain/logs"
  "$HOME/.gbrain-backups"
  "$HOME/Library/LaunchAgents"
)
for d in "${dirs[@]}"; do
  mkdir -p "$d"
done
ok "Created/verified ${#dirs[@]} system directories"

# ===== 7. QMD XDG dirs + alias =====
step "QMD config"
QMD_XDG_CONFIG="$OPENCLAW_HOME/agents/main/qmd/xdg-config"
QMD_XDG_CACHE="$OPENCLAW_HOME/agents/main/qmd/xdg-cache"
mkdir -p "$QMD_XDG_CONFIG/qmd" "$QMD_XDG_CACHE"

if grep -q 'alias qmd=' "$ZSHRC" 2>/dev/null; then
  ok "qmd alias already present in ~/.zshrc"
else
  cat >> "$ZSHRC" <<'EOF'

# QMD — alias to use OpenClaw's index (not the default ~/.cache one)
alias qmd='XDG_CONFIG_HOME="$HOME/.openclaw/agents/main/qmd/xdg-config" XDG_CACHE_HOME="$HOME/.openclaw/agents/main/qmd/xdg-cache" command qmd'
EOF
  ok "Added qmd alias to ~/.zshrc"
fi

if [[ -f "$SCRIPT_DIR/qmd/index.yml" && ! -f "$QMD_XDG_CONFIG/qmd/index.yml" ]]; then
  cp "$SCRIPT_DIR/qmd/index.yml" "$QMD_XDG_CONFIG/qmd/index.yml"
  ok "Installed qmd/index.yml"
elif [[ -f "$QMD_XDG_CONFIG/qmd/index.yml" ]]; then
  ok "qmd/index.yml already in place"
else
  warn "no qmd/index.yml in DR bundle — restore-qmd.sh will need one"
fi

# ===== 8. GitHub auth =====
step "GitHub auth"
if gh auth status >/dev/null 2>&1; then
  ok "gh authenticated as $(gh api user --jq .login)"
else
  warn "gh not authenticated — running 'gh auth login'"
  gh auth login || abort "gh auth login failed"
fi

# ===== 9. Clone workspaces =====
step "Clone workspaces"
"$SCRIPT_DIR/restore-workspaces.sh" || warn "restore-workspaces.sh reported failures — review above"

# ===== 10. Bun link gbrain =====
step "Link gbrain CLI"
if [[ -d "$HOME/gbrain" ]]; then
  if [[ -L "$HOME/.bun/install/global/node_modules/gbrain" ]]; then
    ok "gbrain already bun-linked"
  else
    warn "Running: cd ~/gbrain && bun install && bun link"
    (cd "$HOME/gbrain" && bun install && bun link) || warn "bun link gbrain failed — gbrain service won't start"
  fi
else
  warn "~/gbrain not cloned — skipping bun link"
fi

# ===== 11. Deploy bin/ scripts to ${OPENCLAW_HOME}/bin/ =====
# The repo groups scripts into bin/<category>/ for readability; on install they
# FLATTEN into ${OPENCLAW_HOME}/bin/ (basename only — they're uniquely named and
# reference each other as ${OPENCLAW_HOME}/bin/<basename>). Recurse over bin/**.
# adapt.py-rendered output keeps the same bin/<category>/ tree, so this loop
# flattens whether SCRIPT_DIR points at the repo or at a rendered bundle.
step "Deploy ${OPENCLAW_HOME}/bin/ scripts"
BIN_SRC="$SCRIPT_DIR/bin"
[[ -d "$BIN_SRC" ]] || BIN_SRC="$SCRIPT_DIR/../bin"
bin_count=0
if [[ -d "$BIN_SRC" ]]; then
  while IFS= read -r -d '' src; do
    name="$(basename "$src")"
    dest="$OPENCLAW_HOME/bin/$name"
    cp "$src" "$dest"
    chmod +x "$dest"
    bin_count=$((bin_count+1))
  done < <(find "$BIN_SRC" -type f -print0)
fi
ok "Deployed $bin_count scripts to $OPENCLAW_HOME/bin/"

# ===== 12. Deploy gbrain/ scripts and config to ~/.gbrain/ =====
step "Deploy ~/.gbrain/ scripts + config"
gbrain_count=0
if [[ -d "$SCRIPT_DIR/gbrain" ]]; then
  for src in "$SCRIPT_DIR"/gbrain/*; do
    [[ -f "$src" ]] || continue
    name="$(basename "$src")"
    dest="$HOME/.gbrain/$name"
    cp "$src" "$dest"
    [[ "$name" == *.sh ]] && chmod +x "$dest"
    gbrain_count=$((gbrain_count+1))
  done
  for subdir in migrations evals; do
    src="$SCRIPT_DIR/gbrain/$subdir"
    if [[ -d "$src" ]]; then
      cp -R "$src" "$HOME/.gbrain/"
      ok "Deployed gbrain/$subdir/"
    fi
  done
fi
ok "Deployed $gbrain_count files to ~/.gbrain/"

# ===== 13. Deploy service-env wrapper =====
step "Deploy service-env wrapper"
if [[ -d "$SCRIPT_DIR/../config/service-env" ]]; then
  for src in "$SCRIPT_DIR"/../config/service-env/*; do
    [[ -f "$src" ]] || continue
    dest="$OPENCLAW_HOME/service-env/$(basename "$src")"
    cp "$src" "$dest"
    [[ "$src" == *.sh ]] && chmod +x "$dest"
  done
  ok "Deployed service-env files"
fi

# ===== 13b. Deploy skills to ${OPENCLAW_HOME}/skills/ =====
# Skills keep their directory structure (SKILL.md + bin/ + references/). jobs.yaml
# references e.g. ${OPENCLAW_HOME}/skills/wiki-lint/bin/wiki-lint.py, so the tree
# must be preserved (not flattened).
step "Deploy ${OPENCLAW_HOME}/skills/"
SKILLS_SRC="$SCRIPT_DIR/skills"
[[ -d "$SKILLS_SRC" ]] || SKILLS_SRC="$SCRIPT_DIR/../skills"
if [[ -d "$SKILLS_SRC" ]]; then
  mkdir -p "$OPENCLAW_HOME/skills"
  cp -R "$SKILLS_SRC"/. "$OPENCLAW_HOME/skills/"
  # Restore the executable bit on any shipped skill helpers.
  find "$OPENCLAW_HOME/skills" -type f \( -name '*.sh' -o -name '*.py' \) -path '*/bin/*' -exec chmod +x {} +
  ok "Deployed skills/ tree to $OPENCLAW_HOME/skills/"
else
  warn "no skills/ dir found — skipping"
fi

# ===== 13c. Deploy config templates to ${OPENCLAW_HOME}/config/ =====
# Renders *.template (expanding ${OPENCLAW_HOME}) and copies plain config files.
# openclaw.json itself is handled separately below (step 14).
step "Deploy ${OPENCLAW_HOME}/config/"
CONFIG_SRC="$SCRIPT_DIR/config"
[[ -d "$CONFIG_SRC" ]] || CONFIG_SRC="$SCRIPT_DIR/../config"
if [[ -d "$CONFIG_SRC" ]]; then
  mkdir -p "$OPENCLAW_HOME/config"
  for src in "$CONFIG_SRC"/*; do
    [[ -f "$src" ]] || continue
    base="$(basename "$src")"
    [[ "$base" == openclaw.json.template ]] && continue   # handled in step 14
    if [[ "$base" == *.template ]]; then
      dest="$OPENCLAW_HOME/config/${base%.template}"
      sed "s|\${OPENCLAW_HOME}|$OPENCLAW_HOME|g" "$src" > "$dest"
    else
      cp "$src" "$OPENCLAW_HOME/config/$base"
    fi
  done
  ok "Deployed config/ to $OPENCLAW_HOME/config/"
else
  warn "no config/ dir found — skipping"
fi
# Note: the gateway env wrapper is auto-generated by `openclaw doctor --fix`
# on first run, so we don't snapshot it.

# ===== 14. Restore openclaw config from template =====
step "Restore openclaw config"
LIVE_CONFIG="$OPENCLAW_HOME/openclaw.json"
TEMPLATE="$SCRIPT_DIR/../config/openclaw.json.template"
if [[ -f "$LIVE_CONFIG" ]]; then
  ok "openclaw.json already exists — not overwriting"
elif [[ -f "$TEMPLATE" ]]; then
  # Expand ${OPENCLAW_HOME} so the live config has concrete paths.
  sed "s|\${OPENCLAW_HOME}|$OPENCLAW_HOME|g" "$TEMPLATE" > "$LIVE_CONFIG"
  ok "Rendered template → $LIVE_CONFIG"
  warn "Edit and replace remaining \${VAR} placeholders (see $SCRIPT_DIR/secrets/README.md)"
else
  warn "no openclaw.json.template found at $TEMPLATE"
fi

# ===== 15. LaunchAgents =====
step "LaunchAgents"
if [[ -f "$SCRIPT_DIR/../launchd/install-launchagents.sh" ]]; then
  "$SCRIPT_DIR/../launchd/install-launchagents.sh" || warn "install-launchagents.sh reported failures"
else
  warn "launchd/install-launchagents.sh not found — install LaunchAgents manually"
fi

# ===== 16. openclaw doctor =====
step "openclaw doctor"
# Only run doctor if all referenced ${VAR}s have real values in env block.
ph_unresolved=$(python3 - "$LIVE_CONFIG" 2>/dev/null <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
PAT = re.compile(r'\$\{([A-Z_][A-Z0-9_]*)\}')
ref = set()
def walk(o):
    if isinstance(o, dict):
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
    elif isinstance(o, str):
        for m in PAT.finditer(o): ref.add(m.group(1))
walk(d)
env = d.get('env', {}) or {}
print(",".join(v for v in sorted(ref) if not env.get(v) or env.get(v,'').startswith('${')))
PY
)
if [[ -n "$ph_unresolved" ]]; then
  warn "Unresolved placeholders: $ph_unresolved"
  warn "Fill in secrets first, then run: openclaw doctor --fix"
else
  openclaw doctor --fix || warn "openclaw doctor returned non-zero"
fi

# ===== handoff =====
step "Next steps"
cat <<EOF
Bootstrap complete. Remaining manual work:

  1. Fill in \${VAR} placeholders in ~/.openclaw/openclaw.json
     See $SCRIPT_DIR/secrets/README.md

  2. Open a new terminal so qmd alias and bun PATH load:
     exec zsh

  3. Restore gbrain database:
     $SCRIPT_DIR/restore-gbrain.sh

  4. Refresh gbrain auth tokens:
     ~/.openclaw/bin/gbrain-token-refresh.sh

  5. Rebuild QMD index (~30 min, downloads model weights):
     $SCRIPT_DIR/restore-qmd.sh

  6. Re-create the openclaw cron jobs (see launchd/jobs.yaml +
     docs/disaster-recovery.md "cron restore")

  7. Health check:
     $SCRIPT_DIR/smoke-test.sh
EOF
