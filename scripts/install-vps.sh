#!/usr/bin/env bash
#
# install-vps.sh — one-command installer for Meridian + 9Router on Ubuntu/Debian.
#
# Usage (on a fresh VPS):
#   curl -fsSL https://raw.githubusercontent.com/zerocell01/meridian/main/scripts/install-vps.sh | bash
#
# Or after cloning:  bash scripts/install-vps.sh
#
# Env toggles:
#   INSTALL_OPERATOR=1   also install Codex CLI for the operator/training agent
#   INSTALL_DISCORD=1    also install the Discord signal listener dependencies
#   REPO_URL=...         override repo URL (default: zerocell01/meridian)
#   BRANCH=...           branch to clone (default: main)
#   TARGET_DIR=...       where to clone (default: $HOME/meridian)
#
# It installs system packages, Node 20, PM2 + 9Router, clones Meridian, installs
# deps, and starts 9Router under PM2. It does NOT run the interactive setup wizard
# (that needs your wallet/RPC input) — it prints the next steps instead.
#
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/zerocell01/meridian.git}"
BRANCH="${BRANCH:-main}"
TARGET_DIR="${TARGET_DIR:-$HOME/meridian}"
INSTALL_OPERATOR="${INSTALL_OPERATOR:-0}"
INSTALL_DISCORD="${INSTALL_DISCORD:-0}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1;36m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    warn "Not root and sudo not found — system package steps may fail."
  fi
fi

if ! command -v apt-get >/dev/null 2>&1; then
  warn "This installer targets Ubuntu/Debian (apt). Detected a non-apt system."
  warn "Install Node 18+, pm2, and 9router manually, then run 'npm install' + 'npm run setup'."
  exit 1
fi

step "1/6 Installing system packages (git, curl, build tools)"
$SUDO apt-get update -y
$SUDO apt-get install -y git curl ca-certificates build-essential jq

step "2/6 Ensuring Node.js 18+ is installed"
NEED_NODE=1
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [[ "$NODE_MAJOR" -ge 18 ]]; then NEED_NODE=0; bold "Node $(node -v) already present."; fi
fi
if [[ "$NEED_NODE" -eq 1 ]]; then
  bold "Installing Node.js 20 via NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash -
  $SUDO apt-get install -y nodejs
fi

step "3/6 Installing PM2 + 9Router globally"
$SUDO npm install -g pm2 9router
if [[ "$INSTALL_OPERATOR" == "1" ]]; then
  bold "Installing Codex CLI (operator)..."
  $SUDO npm install -g @openai/codex || warn "Codex install failed — install it manually later."
fi

step "4/6 Cloning / updating Meridian"
if [[ -d "$TARGET_DIR/.git" ]]; then
  bold "Repo already at $TARGET_DIR — pulling latest ($BRANCH)."
  git -C "$TARGET_DIR" fetch origin "$BRANCH"
  git -C "$TARGET_DIR" checkout "$BRANCH"
  git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH" || warn "Could not fast-forward; resolve manually."
else
  git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi
cd "$TARGET_DIR"

step "5/6 Installing Meridian dependencies"
npm install
if [[ "$INSTALL_DISCORD" == "1" ]]; then
  bold "Installing Discord listener dependencies..."
  npm install --prefix discord-listener || warn "Discord listener deps failed — run 'npm run discord:install' later."
fi

step "6/6 Starting 9Router under PM2"
pm2 start 9router --name 9router -- start || warn "9Router may already be running under PM2."
pm2 save || true

cat <<EOF

$(bold "Base install complete.")  Repo: $TARGET_DIR

Next steps (manual — these need your input):

  1) Configure 9Router providers (dashboard on port 20128). From your laptop:
        ssh -L 20128:localhost:20128 $USER@<this-vps-ip>
     then open http://localhost:20128 and connect your providers + pick a model.

  2) Run the Meridian setup wizard (enter wallet key, RPC, choose "9Router"):
        cd "$TARGET_DIR" && npm run setup

  3) Keep DRY_RUN=true in .env until you've verified a few cycles. Then start Meridian:
        cd "$TARGET_DIR" && npm run pm2:start && pm2 save

  4) Make PM2 survive reboots (run the command it prints):
        pm2 startup

EOF

if [[ "$INSTALL_OPERATOR" == "1" ]]; then
cat <<EOF
  5) (Operator) Wire Codex to 9Router + Hermes:
        mkdir -p ~/.codex && cp "$TARGET_DIR/operator/codex-config.example.toml" ~/.codex/config.toml
     Test once:
        cd "$TARGET_DIR" && npm run operate
     Then schedule it (every 6h):
        (crontab -l 2>/dev/null; echo "0 */6 * * * cd $TARGET_DIR && bash scripts/operator.sh >> logs/operator.cron.log 2>&1") | crontab -

EOF
fi

if [[ "$INSTALL_DISCORD" == "1" ]]; then
cat <<EOF
  6) (Discord, ADVANCED) Add these to "$TARGET_DIR/.env" then re-run pm2:
        DISCORD_USER_TOKEN=...      # WARNING: selfbot = against Discord ToS (ban risk)
        DISCORD_GUILD_ID=...
        DISCORD_CHANNEL_IDS=id1,id2
     Then start it (PM2 auto-includes it once configured + installed):
        cd "$TARGET_DIR" && npm run pm2:start && pm2 save

EOF
fi

bold "Check status anytime with:  pm2 status   and   pm2 logs meridian"
