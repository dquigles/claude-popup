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
PREV_APP_FILE="/tmp/claude-popup-${USER}.prev-app"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[$(date '+%H:%M:%S')] EXIT: tmux session '$SESSION' not found" >> /tmp/claude-popup-debug.log
  exit 0
fi

# Remember the frontmost app (macOS only) so detach.sh can restore focus to it.
# Skip if Terminal or iTerm is already frontmost (it's our own popup).
if [[ "$OSTYPE" == "darwin"* ]]; then
  PREV_APP=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null)
  if [[ -n "$PREV_APP" && "$PREV_APP" != "Terminal" && "$PREV_APP" != "iTerm2" ]]; then
    echo "$PREV_APP" > "$PREV_APP_FILE"
    echo "[$(date '+%H:%M:%S')] captured prev app: $PREV_APP" >> /tmp/claude-popup-debug.log
  fi

  if [[ "${CLAUDE_POPUP_NOTIFY:-1}" != "0" ]]; then
    osascript -e 'display notification "Claude needs input" with title "claude-popup"' 2>/dev/null
  fi
fi

"$(dirname "$0")/open-window.sh" "$SESSION"
