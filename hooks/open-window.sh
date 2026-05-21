#!/usr/bin/env bash
# claude-popup: open-window.sh
# Ensures a terminal-emulator window attached to the given tmux session is
# open. If a previously-spawned window is still alive, refocuses it; otherwise
# spawns a new one. Used by both run.sh (initial open) and popup.sh
# (Notification hook). Reads the persisted emulator kind from
# /tmp/claude-popup-${USER}.term — currently "terminal" or "iterm".

SESSION="${1:-claude-code}"
USER_TAG="/tmp/claude-popup-${USER}"
WIN_ID_FILE="$USER_TAG.win-id"
TERM_FILE="$USER_TAG.term"
LOG="/tmp/claude-popup-debug.log"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[$(date '+%H:%M:%S')] open-window.sh: tmux session '$SESSION' not found" >> "$LOG"
  exit 0
fi

TERM_KIND="terminal"
[[ -f "$TERM_FILE" ]] && TERM_KIND=$(cat "$TERM_FILE")
case "$TERM_KIND" in
  iterm|terminal) ;;
  *) TERM_KIND="terminal" ;;
esac

# ── macOS: Terminal.app ──────────────────────────────────────────────────────
open_terminal_app() {
  local alive=""
  if [[ -f "$WIN_ID_FILE" ]]; then
    local win_id
    win_id=$(cat "$WIN_ID_FILE")
    alive=$(osascript 2>/dev/null <<EOF
tell application "Terminal"
  try
    get id of window id $win_id
    return "yes"
  on error
    return ""
  end try
end tell
EOF
)
  fi

  if [[ -n "$alive" ]]; then
    echo "[$(date '+%H:%M:%S')] open-window.sh: refocusing existing Terminal window" >> "$LOG"
    osascript -e 'tell application "Terminal" to activate' 2>/dev/null
  else
    echo "[$(date '+%H:%M:%S')] open-window.sh: opening new Terminal window" >> "$LOG"
    local new_id
    new_id=$(osascript 2>>"$LOG" <<EOF
tell application "Terminal"
  activate
  do script "TMUX= tmux attach-session -t '$SESSION'"
  return id of front window
end tell
EOF
)
    [[ -n "$new_id" ]] && echo "$new_id" > "$WIN_ID_FILE"
  fi
}

# ── macOS: iTerm2 ────────────────────────────────────────────────────────────
open_iterm() {
  local alive=""
  if [[ -f "$WIN_ID_FILE" ]]; then
    local win_id
    win_id=$(cat "$WIN_ID_FILE")
    alive=$(osascript 2>/dev/null <<EOF
tell application "iTerm"
  try
    get id of window id $win_id
    return "yes"
  on error
    return ""
  end try
end tell
EOF
)
  fi

  if [[ -n "$alive" ]]; then
    echo "[$(date '+%H:%M:%S')] open-window.sh: refocusing existing iTerm window" >> "$LOG"
    osascript -e 'tell application "iTerm" to activate' 2>/dev/null
  else
    echo "[$(date '+%H:%M:%S')] open-window.sh: opening new iTerm window" >> "$LOG"
    local new_id
    new_id=$(osascript 2>>"$LOG" <<EOF
tell application "iTerm"
  activate
  set newWin to (create window with default profile command "TMUX= tmux attach-session -t '$SESSION'")
  return id of newWin
end tell
EOF
)
    [[ -n "$new_id" ]] && echo "$new_id" > "$WIN_ID_FILE"
  fi
}

if [[ "$OSTYPE" == "darwin"* ]]; then
  case "$TERM_KIND" in
    iterm)    open_iterm ;;
    terminal) open_terminal_app ;;
  esac
  exit 0
fi

# ── Linux fallback (no focus tracking) ───────────────────────────────────────
for term in x-terminal-emulator gnome-terminal konsole xfce4-terminal alacritty kitty xterm; do
  if command -v "$term" &>/dev/null; then
    case "$term" in
      gnome-terminal) "$term" -- bash -c "TMUX= tmux attach -t '$SESSION'" &>/dev/null & ;;
      *)              "$term" -e bash -c "TMUX= tmux attach -t '$SESSION'" &>/dev/null & ;;
    esac
    break
  fi
done
