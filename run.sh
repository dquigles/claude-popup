#!/usr/bin/env bash
# claude-popup: run.sh
# Single entry point. Manages a shared `claude-code` tmux session and either
# attaches the current terminal to it (interactive shells) or opens a
# Terminal/iTerm popup window attached to it (non-interactive callers like
# Claude Code's Notification hook). Also supports --stop, --status, --reset,
# and pass-through args after `--`.

SESSION="claude-code"
USER_TAG="/tmp/claude-popup-${USER}"
LOG="/tmp/claude-popup-debug.log"
ATTACHED_HOST_FILE="$USER_TAG.attached-host"

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
    rm -f "$USER_TAG.win-id" "$USER_TAG.prev-app" "$USER_TAG.term" "$ATTACHED_HOST_FILE" "$USER_TAG.here-app"
  fi
}

# Frontmost macOS app name; empty on non-mac / on failure.
frontmost_app() {
  [[ "$OSTYPE" == "darwin"* ]] || { echo ""; return; }
  osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null
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

  if [[ -f "$ATTACHED_HOST_FILE" ]]; then
    echo "Attached host: $(cat "$ATTACHED_HOST_FILE")"
  else
    echo "Attached host: (none)"
  fi

  if [[ -f "$USER_TAG.here-app" ]]; then
    echo "Here-mode target: $(cat "$USER_TAG.here-app")"
  fi

  local client_count
  client_count=$(tmux list-clients -t "$SESSION" 2>/dev/null | wc -l | tr -d ' ')
  echo "Attached clients: ${client_count:-0}"
}

# Create the tmux session if missing, or report that it's being reused.
# Args after function name (if any) are appended to the `claude` command
# only when a fresh session is created.
ensure_session() {
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "→ Session '$SESSION' already running."
    return 0
  fi
  echo "→ Starting new '$SESSION' tmux session with Claude Code..."
  tmux new-session -d -s "$SESSION" -c "$PWD" -x 220 -y 50
  # Tear down the session once the last client detaches (unless opted out).
  # Defer until first attach so the freshly-created detached session isn't
  # killed before the caller can connect.
  if [[ "${CLAUDE_POPUP_KEEP_ALIVE:-0}" != "1" ]]; then
    tmux set-hook -t "$SESSION" client-attached \
      "set-option -t $SESSION destroy-unattached on" >/dev/null 2>&1
  fi
  local CLAUDE_CMD="claude"
  if (( $# > 0 )); then
    CLAUDE_CMD="claude $(printf '%q ' "$@")"
  fi
  tmux send-keys -t "$SESSION" "$CLAUDE_CMD" Enter
}

# Attach the current terminal to the session. The host app (e.g. "Code",
# "Cursor", "iTerm2") is recorded so the Notification hook can stay quiet
# when that app is frontmost.
do_attach() {
  if [[ -n "$TMUX" ]]; then
    echo "claude-popup: already inside a tmux session ($TMUX)."
    echo "Detach first (Ctrl+B D), then re-run from a plain shell."
    exit 1
  fi

  detect_term > "$USER_TAG.term"
  local host
  host=$(frontmost_app)
  [[ -z "$host" && "$OSTYPE" != "darwin"* ]] && host="linux"
  [[ -n "$host" ]] && echo "$host" > "$ATTACHED_HOST_FILE"

  ensure_session "${EXTRA_ARGS[@]}"
  echo "→ Attaching this terminal to '$SESSION'..."

  # Clear the host marker when this client detaches, regardless of how.
  trap 'rm -f "$ATTACHED_HOST_FILE"' EXIT INT TERM
  tmux attach-session -t "$SESSION"
  rm -f "$ATTACHED_HOST_FILE"
}

# Attach the current terminal to the session, but treat it AS the popup
# target — write win-id (when possible) and a here-app marker, and skip
# the attached-host suppression marker. The popup hooks will then refocus
# this same window/app on Notification and the prev app on PostToolUse.
do_here() {
  if [[ -n "$TMUX" ]]; then
    echo "claude-popup: already inside a tmux session ($TMUX)."
    echo "Detach first (Ctrl+B D), then re-run from a plain shell."
    exit 1
  fi
  if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "claude-popup --here is currently macOS-only."
    exit 1
  fi

  local term_kind app host win_id
  term_kind=$(detect_term)
  host=$(frontmost_app)
  [[ -z "$host" ]] && host="$TERM_PROGRAM"

  case "$term_kind" in
    terminal) app="Terminal" ;;
    iterm)    app="iTerm" ;;
  esac

  if [[ -n "$app" ]]; then
    win_id=$(osascript -e "tell application \"$app\" to id of front window" 2>/dev/null)
  fi

  echo "$term_kind" > "$USER_TAG.term"
  if [[ -n "$win_id" ]]; then
    echo "$win_id" > "$USER_TAG.win-id"
  else
    rm -f "$USER_TAG.win-id"
  fi
  echo "${host:-$app}" > "$USER_TAG.here-app"
  rm -f "$ATTACHED_HOST_FILE"

  ensure_session "${EXTRA_ARGS[@]}"
  echo "→ Using this terminal as popup target: ${host:-$app}${win_id:+ (window $win_id)}"

  trap 'rm -f "$USER_TAG.here-app" "$USER_TAG.win-id"' EXIT INT TERM
  tmux attach-session -t "$SESSION"
  rm -f "$USER_TAG.here-app" "$USER_TAG.win-id"
}

# Open (or refocus) a Terminal/iTerm window attached to the session.
do_popup_window() {
  detect_term > "$USER_TAG.term"
  ensure_session "${EXTRA_ARGS[@]}"
  "$(dirname "$0")/hooks/open-window.sh" "$SESSION"
  echo "✓ Claude Code window opened."
  echo "  Stop:    claude-popup --stop"
  echo "  Status:  claude-popup --status"
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
    # --inline is an undocumented alias to force the attach path
    # (useful for callers without a TTY who still want inline behavior).
    --inline)      LIFECYCLE="attach" ;;
    --popup)       LIFECYCLE="popup" ;;
    --here)        LIFECYCLE="here" ;;
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
    rm -f "$USER_TAG.win-id" "$USER_TAG.prev-app" "$USER_TAG.term" "$ATTACHED_HOST_FILE" "$USER_TAG.here-app"
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
    rm -f "$USER_TAG.win-id" "$USER_TAG.prev-app" "$USER_TAG.term" "$ATTACHED_HOST_FILE" "$USER_TAG.here-app"
    ;;
esac

# Dispatch:
#   --inline (alias 'attach')  → always attach this terminal
#   --popup                    → always open a popup window
#   no flag + interactive TTY  → attach this terminal
#   no flag + non-interactive  → open a popup window (hook callers)
if [[ "$LIFECYCLE" == "attach" ]]; then
  do_attach
elif [[ "$LIFECYCLE" == "popup" ]]; then
  do_popup_window
elif [[ "$LIFECYCLE" == "here" ]]; then
  do_here
elif [[ -t 0 && -t 1 ]]; then
  do_attach
else
  do_popup_window
fi
