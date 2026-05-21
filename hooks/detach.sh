#!/usr/bin/env bash
# Refocus the app that was frontmost before the popup opened.
# Fires on UserPromptSubmit / PreToolUse — i.e. right after the user responded.

cat >/dev/null  # drain Claude's payload

# Only act when this hook is running inside the claude-popup tmux session.
if [[ -z "$TMUX" ]] || [[ "$(tmux display-message -p '#S' 2>/dev/null)" != "claude-code" ]]; then
  exit 0
fi

echo "[$(date '+%H:%M:%S')] detach.sh fired" >> /tmp/claude-popup-debug.log

PREV_APP_FILE="/tmp/claude-popup-${USER}.prev-app"

[[ -f "$PREV_APP_FILE" ]] || exit 0

PREV_APP=$(cat "$PREV_APP_FILE")
rm -f "$PREV_APP_FILE"

if [[ -n "$PREV_APP" && "$PREV_APP" != "Terminal" && "$PREV_APP" != "iTerm2" && "$OSTYPE" == "darwin"* ]]; then
  echo "[$(date '+%H:%M:%S')] refocusing $PREV_APP" >> /tmp/claude-popup-debug.log
  osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
fi

exit 0
