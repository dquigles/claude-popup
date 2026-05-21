#!/usr/bin/env bash
# Claude Code popup hook — Notification event
# Captures the frontmost app (so detach.sh can restore focus) and delegates
# window open/refocus to open-window.sh.

cat >/dev/null  # drain Claude's payload — we don't need to inspect it

SESSION="claude-code"

# Only act when this hook is running inside the claude-popup tmux session.
# Filters out VS Code's Claude extension and any other Claude session.
if [[ -z "$TMUX" ]] || [[ "$(tmux display-message -p '#S' 2>/dev/null)" != "$SESSION" ]]; then
  exit 0
fi

echo "[$(date '+%H:%M:%S')] popup.sh fired" >> /tmp/claude-popup-debug.log
USER_TAG="/tmp/claude-popup-${USER}"
PREV_APP_FILE="$USER_TAG.prev-app"
ATTACHED_HOST_FILE="$USER_TAG.attached-host"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[$(date '+%H:%M:%S')] EXIT: tmux session '$SESSION' not found" >> /tmp/claude-popup-debug.log
  exit 0
fi

FRONTMOST=""
if [[ "$OSTYPE" == "darwin"* ]]; then
  FRONTMOST=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null)
fi

# Suppression: if a terminal is attached inline and its host app is frontmost,
# the user is already looking at Claude — don't steal focus with a popup.
if [[ -f "$ATTACHED_HOST_FILE" && -n "$FRONTMOST" ]]; then
  ATTACHED_HOST=$(cat "$ATTACHED_HOST_FILE")
  if [[ "$FRONTMOST" == "$ATTACHED_HOST" ]]; then
    echo "[$(date '+%H:%M:%S')] SKIP: attached host '$ATTACHED_HOST' is frontmost" >> /tmp/claude-popup-debug.log
    exit 0
  fi
fi

# Remember the frontmost app (macOS only) so detach.sh can restore focus to it.
# Skip if Terminal or iTerm is already frontmost (it's our own popup).
if [[ "$OSTYPE" == "darwin"* ]]; then
  if [[ -n "$FRONTMOST" && "$FRONTMOST" != "Terminal" && "$FRONTMOST" != "iTerm2" ]]; then
    echo "$FRONTMOST" > "$PREV_APP_FILE"
    echo "[$(date '+%H:%M:%S')] captured prev app: $FRONTMOST" >> /tmp/claude-popup-debug.log
  fi

  if [[ "${CLAUDE_POPUP_NOTIFY:-1}" != "0" ]]; then
    osascript -e 'display notification "Claude needs input" with title "claude-popup"' 2>/dev/null
  fi
fi

"$(dirname "$0")/open-window.sh" "$SESSION"
