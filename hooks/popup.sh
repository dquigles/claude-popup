#!/usr/bin/env bash
# Claude Code tmux popup hook
# Fires on Notification events — pops up the claude session when input is needed

# Drain stdin (Claude Code's Notification payload) — we don't need to inspect
# it, since this hook is only registered for Notification events.
cat >/dev/null

SESSION="claude-code"

# Make sure the session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  exit 0
fi

# Don't open a second popup if one is already showing.
# tmux has no native "is a popup open?" check, so use an atomic mkdir lock.
# The command we hand to the terminal removes the lock when it closes.
LOCK="${TMPDIR:-/tmp}/claude-popup-${USER}.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  exit 0
fi

# Marker file — detach.sh checks for this so it only auto-detaches popup
# attaches (and leaves manual `tmux attach` alone).
MARKER="${TMPDIR:-/tmp}/claude-popup-${USER}.active"

# Command the new terminal/popup will run: mark popup active, attach to the
# session, then clean up marker + lock when the user detaches. TMUX= clears
# the parent env var so tmux doesn't refuse the nested attach.
ATTACH_CMD="touch '$MARKER'; TMUX= tmux attach-session -t '$SESSION'; rm -f '$MARKER'; rmdir '$LOCK' 2>/dev/null"

# Pick a mechanism:
#   - If any tmux client is already attached on this server, overlay a popup
#     on it (lighter, no new window).
#   - Otherwise spawn a real OS terminal window so the user actually sees it.
if [[ -n "$(tmux list-clients 2>/dev/null)" ]]; then
  tmux display-popup -E -w 85% -h 75% "$ATTACH_CMD"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS: open a new Terminal.app window
  osascript <<EOF >/dev/null 2>&1
tell application "Terminal"
  activate
  do script "$ATTACH_CMD; exit"
end tell
EOF
else
  # Linux: best-effort across common terminal emulators
  for term in x-terminal-emulator gnome-terminal konsole xfce4-terminal alacritty kitty xterm; do
    if command -v "$term" &>/dev/null; then
      case "$term" in
        gnome-terminal) "$term" -- bash -c "$ATTACH_CMD" &>/dev/null & ;;
        *)              "$term" -e bash -c "$ATTACH_CMD" &>/dev/null & ;;
      esac
      break
    fi
  done
fi
