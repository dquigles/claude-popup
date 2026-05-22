#!/usr/bin/env bash
# Refocus the app that was frontmost before the popup opened. Runs at
# UserPromptSubmit / PreToolUse / PostToolUse — the PREV_APP_FILE guard
# below makes subsequent fires in the same turn no-ops, so multi-tool
# turns don't flicker.

PAYLOAD=$(cat)

# Derive session name from the current tmux environment.
SESSION=$(tmux display-message -p '#S' 2>/dev/null)

# Only act when this hook is running inside a claude-popup tmux session.
if [[ -z "$TMUX" ]] || [[ "$SESSION" != claude-code-* ]]; then
  exit 0
fi

SESSION_KEY="${SESSION#claude-code-}"

EVENT=""
if command -v jq &>/dev/null; then
  EVENT=$(echo "$PAYLOAD" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
fi

echo "[$(date '+%H:%M:%S')] detach.sh fired event=${EVENT:-unknown} session=$SESSION" >> /tmp/claude-popup-debug.log

[[ "$OSTYPE" == "darwin"* ]] || exit 0

USER_TAG="/tmp/claude-popup-${USER}-${SESSION_KEY}"
PREV_APP_FILE="$USER_TAG.prev-app"
ATTACHED_HOST_FILE="$USER_TAG.attached-host"

[[ -f "$PREV_APP_FILE" ]] || exit 0

# In inline mode (your editor is attached to the session), don't refocus —
# the user is "in their editor" and there's no popup to unfocus from.
if [[ -f "$ATTACHED_HOST_FILE" ]]; then
  FRONTMOST=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null)
  ATTACHED_HOST=$(cat "$ATTACHED_HOST_FILE")
  if [[ -n "$ATTACHED_HOST" && "$FRONTMOST" == "$ATTACHED_HOST" ]]; then
    echo "[$(date '+%H:%M:%S')] SKIP refocus: user is in attached host ($ATTACHED_HOST)" >> /tmp/claude-popup-debug.log
    exit 0
  fi
fi

PREV_APP=$(cat "$PREV_APP_FILE")
rm -f "$PREV_APP_FILE"

if [[ -n "$PREV_APP" && "$PREV_APP" != "Terminal" && "$PREV_APP" != "iTerm2" ]]; then
  echo "[$(date '+%H:%M:%S')] refocusing $PREV_APP" >> /tmp/claude-popup-debug.log
  osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
fi

exit 0
