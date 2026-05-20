#!/usr/bin/env bash
# claude-tmux-popup: run.sh
# Starts (or reattaches to) the claude-code tmux session

SESSION="claude-code"

# Kill existing session if requested
if [[ "$1" == "--reset" ]]; then
  tmux kill-session -t "$SESSION" 2>/dev/null
  echo "Session reset."
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "→ Session '$SESSION' already running. Attaching..."
  tmux attach-session -t "$SESSION"
else
  echo "→ Starting new '$SESSION' tmux session with Claude Code..."
  tmux new-session -d -s "$SESSION" -x 220 -y 50

  # Start claude inside the session
  tmux send-keys -t "$SESSION" "claude" Enter

  echo "✓ Session started. Claude Code is running in the background."
  echo ""
  echo "  Claude will pop up automatically when it needs your input."
  echo "  To manually attach:  tmux attach -t $SESSION"
  echo "  To stop:             tmux kill-session -t $SESSION"
fi
