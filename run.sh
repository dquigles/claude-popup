#!/usr/bin/env bash
# claude-popup: run.sh
# Starts/reuses the claude-code tmux session and opens a Terminal/iTerm
# window attached to it. Also supports --stop, --status, --reset, and
# pass-through args to `claude` after `--`.

SESSION="claude-code"
USER_TAG="/tmp/claude-popup-${USER}"
LOG="/tmp/claude-popup-debug.log"

rotate_log() {
  [[ -f "$LOG" ]] || return 0
  local size
  size=$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)
  if (( size > 1048576 )); then
    mv "$LOG" "$LOG.1"
  fi
}

detect_term() {
  local override="${CLAUDE_POPUP_TERMINAL:-}"
  case "$override" in
    iterm|terminal) echo "$override"; return ;;
  esac
  case "$TERM_PROGRAM" in
    iTerm.app) echo "iterm" ;;
    *)         echo "terminal" ;;
  esac
}

cleanup_stale() {
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    rm -f "$USER_TAG.win-id" "$USER_TAG.prev-app" "$USER_TAG.term"
  fi
}

print_status() {
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION': running"
  else
    echo "Session '$SESSION': not running"
    return
  fi

  if [[ -f "$USER_TAG.term" ]]; then
    echo "Emulator: $(cat "$USER_TAG.term")"
  else
    echo "Emulator: (unknown — no .term file)"
  fi

  if [[ -f "$USER_TAG.win-id" ]]; then
    local win_id app alive
    win_id=$(cat "$USER_TAG.win-id")
    app="Terminal"
    [[ "$(cat "$USER_TAG.term" 2>/dev/null)" == "iterm" ]] && app="iTerm"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      alive=$(osascript 2>/dev/null <<EOF
tell application "$app"
  try
    get id of window id $win_id
    return "alive"
  on error
    return "stale"
  end try
end tell
EOF
)
      echo "Window id $win_id ($app): ${alive:-unknown}"
    else
      echo "Window id $win_id"
    fi
  else
    echo "Window: (none tracked)"
  fi

  if [[ -f "$USER_TAG.prev-app" ]]; then
    echo "Previous app (pending refocus): $(cat "$USER_TAG.prev-app")"
  fi
}

# ── parse args ────────────────────────────────────────────────────────────────
EXTRA_ARGS=()
LIFECYCLE=""
SEEN_DD=0
for arg in "$@"; do
  if [[ "$SEEN_DD" == "1" ]]; then
    EXTRA_ARGS+=("$arg")
    continue
  fi
  case "$arg" in
    --)            SEEN_DD=1 ;;
    --stop|--kill) LIFECYCLE="stop" ;;
    --status)      LIFECYCLE="status" ;;
    --reset)       LIFECYCLE="reset" ;;
    *)             EXTRA_ARGS+=("$arg") ;;
  esac
done

rotate_log
cleanup_stale

case "$LIFECYCLE" in
  stop)
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      tmux kill-session -t "$SESSION"
      echo "Stopped session '$SESSION'."
    else
      echo "No session to stop."
    fi
    win_id=""
    app="Terminal"
    if [[ "$OSTYPE" == "darwin"* && -f "$USER_TAG.win-id" ]]; then
      win_id=$(cat "$USER_TAG.win-id")
      [[ "$(cat "$USER_TAG.term" 2>/dev/null)" == "iterm" ]] && app="iTerm"
    fi
    rm -f "$USER_TAG.win-id" "$USER_TAG.prev-app" "$USER_TAG.term"
    if [[ -n "$win_id" ]]; then
      osascript 2>/dev/null <<OSEOF
tell application "$app"
  try
    close (first window whose id is $win_id) saving no
  end try
end tell
OSEOF
    fi
    exit 0
    ;;
  status)
    print_status
    exit 0
    ;;
  reset)
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      tmux kill-session -t "$SESSION"
      echo "Session reset."
    fi
    rm -f "$USER_TAG.win-id" "$USER_TAG.prev-app" "$USER_TAG.term"
    ;;
esac

# Persist detected terminal for open-window.sh and popup.sh
detect_term > "$USER_TAG.term"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "→ Session '$SESSION' already running."
else
  echo "→ Starting new '$SESSION' tmux session with Claude Code..."
  tmux new-session -d -s "$SESSION" -c "$PWD" -x 220 -y 50
  # When the popup window closes, tear down the session too (unless opted out).
  # Defer enabling destroy-unattached until a client has actually attached —
  # otherwise the freshly-created detached session is destroyed before
  # open-window.sh's `tmux attach-session` can connect.
  if [[ "${CLAUDE_POPUP_KEEP_ALIVE:-0}" != "1" ]]; then
    tmux set-hook -t "$SESSION" client-attached \
      "set-option -t $SESSION destroy-unattached on" >/dev/null 2>&1
  fi
  CLAUDE_CMD="claude"
  if (( ${#EXTRA_ARGS[@]} > 0 )); then
    CLAUDE_CMD="claude $(printf '%q ' "${EXTRA_ARGS[@]}")"
  fi
  tmux send-keys -t "$SESSION" "$CLAUDE_CMD" Enter
fi

"$(dirname "$0")/hooks/open-window.sh" "$SESSION"

echo "✓ Claude Code window opened."
echo "  Stop:    claude-popup --stop"
echo "  Status:  claude-popup --status"
