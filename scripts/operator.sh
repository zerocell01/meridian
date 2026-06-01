#!/usr/bin/env bash
#
# operator.sh — runs the Meridian "operator" (training) agent once.
#
# It feeds operator/PROMPT.md to an AI coding CLI (Codex by default, Claude Code
# optional) which reviews Meridian's performance and applies SAFE tuning
# (lessons / evolve / signal weights) or proposes RISKY changes via a PR branch.
#
# It NEVER trades — guardrails live in operator/PROMPT.md.
#
# Schedule it (see README "Operator"), e.g. cron every 6h:
#   0 */6 * * * cd /home/USER/meridian && bash scripts/operator.sh >> logs/operator.cron.log 2>&1
#
# Configurable via env:
#   RUNNER        codex | claude        (default: codex)
#   OPERATOR_MODEL model/combo name     (default: nousresearch/hermes-4-405b)
#   REPO_DIR      path to repo          (default: parent dir of this script)
#   CODEX_FLAGS   extra codex flags     (default: --full-auto)
#   CLAUDE_FLAGS  extra claude flags    (default: --permission-mode acceptEdits)
#
set -euo pipefail

RUNNER="${RUNNER:-codex}"
OPERATOR_MODEL="${OPERATOR_MODEL:-nousresearch/hermes-4-405b}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(dirname "$SCRIPT_DIR")}"
PROMPT_FILE="$REPO_DIR/operator/PROMPT.md"

cd "$REPO_DIR"
mkdir -p logs
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="logs/operator-$STAMP.log"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "operator: prompt not found at $PROMPT_FILE" >&2
  exit 1
fi

# Preflight: warn (don't fail) if 9Router isn't reachable.
NINEROUTER_URL="${LLM_BASE_URL:-http://localhost:20128/v1}"
if ! curl -fsS --max-time 5 "${NINEROUTER_URL%/}/models" >/dev/null 2>&1; then
  echo "operator: WARNING — 9Router not reachable at $NINEROUTER_URL (is 'pm2 start 9router' running?)" | tee -a "$LOG"
fi

PROMPT="$(cat "$PROMPT_FILE")"
echo "operator: starting run $STAMP via '$RUNNER' (model: $OPERATOR_MODEL)" | tee -a "$LOG"

case "$RUNNER" in
  codex)
    # codex exec = non-interactive. --full-auto = auto-approve edits/commands in a
    # workspace sandbox. Verify flags against your installed Codex version.
    # 9Router needs no real key, but Codex expects the env var to exist.
    export NINEROUTER_API_KEY="${NINEROUTER_API_KEY:-9router}"
    codex exec ${CODEX_FLAGS:---full-auto} --cd "$REPO_DIR" -m "$OPERATOR_MODEL" "$PROMPT" 2>&1 | tee -a "$LOG"
    ;;
  claude)
    # Claude Code headless. The operator subagent + tool allowlist live in .claude/.
    claude -p "$PROMPT" --model "$OPERATOR_MODEL" ${CLAUDE_FLAGS:---permission-mode acceptEdits} 2>&1 | tee -a "$LOG"
    ;;
  *)
    echo "operator: unknown RUNNER '$RUNNER' (use 'codex' or 'claude')" >&2
    exit 1
    ;;
esac

echo "operator: run $STAMP complete — log at $LOG" | tee -a "$LOG"
