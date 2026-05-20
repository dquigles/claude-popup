#!/usr/bin/env bash
# Claude Code tmux popup hook
# Fires on Notification events — pops up the claude session when input is needed

INPUT=$(cat)

# Only trigger on awaiting_input notifications
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // ""')
if [[ "$TRIGGER" != "awaiting_input" ]]; then
  exit 0
fi

SESSION="claude-code"

# Make sure the session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  exit 0
fi

# Don't open a second popup if one is already showing
if tmux display-message -p "#{window_name}" 2>/dev/null | grep -q "popup"; then
  exit 0
fi

# Pop up a floating window attached to the claude session
# -E: close popup when the command exits (i.e. when you detach)
# -w/-h: size of the popup (percentage of terminal)
tmux display-popup \
  -E \
  -w 85% \
  -h 75% \
  "tmux attach-session -t $SESSION"
