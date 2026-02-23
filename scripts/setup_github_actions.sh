#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  bash scripts/setup_github_actions.sh [options]

Options:
  --repo OWNER/REPO              Target repo (auto-detected from origin if omitted)
  --gemini-api-key KEY           Gemini API Key (or env GEMINI_API_KEY)
  --stock-list LIST              Stock list, e.g. 600519,300750,AAPL
  --telegram-bot-token TOKEN     Telegram Bot Token
  --telegram-chat-id ID          Telegram Chat ID
  --telegram-thread-id ID        Telegram Topic ID (optional)
  --tavily-api-keys KEYS         Tavily API Key (optional)
  --report-type TYPE             simple or full (default: simple)
  --mode MODE                    Workflow mode: full/market-only/stocks-only (default: full)
  --no-run                       Configure only, do not trigger workflow
  -h, --help                     Show help
USAGE
}

REPO=""
GEMINI_API_KEY="${GEMINI_API_KEY:-}"
STOCK_LIST="${STOCK_LIST:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_MESSAGE_THREAD_ID="${TELEGRAM_MESSAGE_THREAD_ID:-}"
TAVILY_API_KEYS="${TAVILY_API_KEYS:-}"
REPORT_TYPE="${REPORT_TYPE:-simple}"
MODE="full"
RUN_NOW="true"
RETRY_MAX="${RETRY_MAX:-5}"
RETRY_BASE_DELAY="${RETRY_BASE_DELAY:-2}"

parse_repo_from_git_remote() {
  local remote
  remote="$(git config --get remote.origin.url || true)"
  if [[ "$remote" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    return
  fi
  echo ""
}

retry_eval() {
  local desc="$1"
  local cmd="$2"
  local attempt=1
  local delay="$RETRY_BASE_DELAY"
  local rc=0

  while true; do
    if eval "$cmd"; then
      return 0
    fi
    rc=$?
    if (( attempt >= RETRY_MAX )); then
      echo "ERROR: $desc failed after $attempt attempts"
      return "$rc"
    fi
    echo "WARN: $desc failed (attempt $attempt/$RETRY_MAX), retry in ${delay}s..."
    sleep "$delay"
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --gemini-api-key)
      GEMINI_API_KEY="$2"
      shift 2
      ;;
    --stock-list)
      STOCK_LIST="$2"
      shift 2
      ;;
    --telegram-bot-token)
      TELEGRAM_BOT_TOKEN="$2"
      shift 2
      ;;
    --telegram-chat-id)
      TELEGRAM_CHAT_ID="$2"
      shift 2
      ;;
    --telegram-thread-id)
      TELEGRAM_MESSAGE_THREAD_ID="$2"
      shift 2
      ;;
    --tavily-api-keys)
      TAVILY_API_KEYS="$2"
      shift 2
      ;;
    --report-type)
      REPORT_TYPE="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --no-run)
      RUN_NOW="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not found. Install: https://cli.github.com/"
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO="$(parse_repo_from_git_remote)"
fi

if [[ -z "$REPO" ]]; then
  echo "ERROR: cannot detect target repo, please pass --repo OWNER/REPO"
  exit 1
fi

if ! gh auth status -h github.com >/dev/null 2>&1; then
  echo "ERROR: gh auth is invalid, please run: gh auth login -h github.com"
  exit 1
fi

if ! retry_eval "GitHub API connectivity check" "gh api rate_limit >/dev/null 2>&1"; then
  echo "Hint: check network/proxy first, then rerun."
  exit 1
fi

if ! retry_eval "Repo access check" "gh api \"repos/$REPO\" >/dev/null 2>&1"; then
  echo "ERROR: cannot access repo $REPO"
  echo "Hint: make sure the repo exists and your account has admin permission."
  echo "If you haven't forked yet, run: gh repo fork ZhuLinsen/daily_stock_analysis --clone=false --remote=false"
  exit 1
fi

if [[ -z "$GEMINI_API_KEY" ]]; then
  read -r -s -p "Enter GEMINI_API_KEY: " GEMINI_API_KEY
  echo ""
fi

if [[ -z "$STOCK_LIST" ]]; then
  read -r -p "Enter STOCK_LIST (comma-separated): " STOCK_LIST
fi

if [[ -z "$STOCK_LIST" ]]; then
  STOCK_LIST="600519"
  echo "WARN: STOCK_LIST is empty, using default: $STOCK_LIST"
fi

if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
  read -r -s -p "Enter TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
  echo ""
fi

if [[ -z "$TELEGRAM_CHAT_ID" ]]; then
  read -r -p "Enter TELEGRAM_CHAT_ID: " TELEGRAM_CHAT_ID
fi

if [[ -z "$GEMINI_API_KEY" || -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
  echo "ERROR: missing required fields (GEMINI_API_KEY / TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID)"
  exit 1
fi

set_secret() {
  local key="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    retry_eval "set secret $key" "printf '%s' \"$value\" | gh secret set \"$key\" --repo \"$REPO\" >/dev/null 2>&1"
    echo "OK: secret set -> $key"
  fi
}

set_variable() {
  local key="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    retry_eval "set variable $key" "gh variable set \"$key\" --body \"$value\" --repo \"$REPO\" >/dev/null 2>&1"
    echo "OK: variable set -> $key"
  fi
}

printf "\nConfiguring repo: %s\n" "$REPO"

set_secret "GEMINI_API_KEY" "$GEMINI_API_KEY"
set_secret "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"
set_secret "TELEGRAM_CHAT_ID" "$TELEGRAM_CHAT_ID"
set_secret "TELEGRAM_MESSAGE_THREAD_ID" "$TELEGRAM_MESSAGE_THREAD_ID"
set_secret "TAVILY_API_KEYS" "$TAVILY_API_KEYS"

set_variable "STOCK_LIST" "$STOCK_LIST"
set_variable "REPORT_TYPE" "$REPORT_TYPE"
set_variable "REALTIME_SOURCE_PRIORITY" "tencent,akshare_sina,efinance,akshare_em"

printf "\nDone: GitHub Actions config completed.\n"

if [[ "$RUN_NOW" == "true" ]]; then
  WORKFLOW_REF="daily_analysis.yml"
  if ! gh workflow view "$WORKFLOW_REF" --repo "$REPO" >/dev/null 2>&1; then
    WORKFLOW_REF="$(gh api "repos/$REPO/actions/workflows" --jq '.workflows[] | select(.path | endswith("/daily_analysis.yml")) | .id' | head -n 1 || true)"
  fi

  if [[ -z "$WORKFLOW_REF" ]]; then
    WORKFLOW_REF="$(gh api "repos/$REPO/actions/workflows" --jq '.workflows[] | select(.name=="每日股票分析" or .name=="Daily Stock Analysis") | .id' | head -n 1 || true)"
  fi

  if [[ -z "$WORKFLOW_REF" ]]; then
    echo "ERROR: workflow not found in repo $REPO"
    echo "Hint: ensure .github/workflows/daily_analysis.yml exists on the default branch."
    echo "Hint: if this is a fresh fork, sync default branch and enable Actions once in web UI."
    echo "Available workflows:"
    gh workflow list --repo "$REPO" || true
    exit 1
  fi

  retry_eval "workflow trigger" "gh workflow run \"$WORKFLOW_REF\" --repo \"$REPO\" -f mode=\"$MODE\" >/dev/null 2>&1"
  echo "OK: workflow triggered -> $WORKFLOW_REF (mode=$MODE)"
  printf "\nLatest runs:\n"
  retry_eval "workflow run list" "gh run list --repo \"$REPO\" --limit 3"
else
  echo "Skip: workflow trigger skipped (--no-run)"
fi
