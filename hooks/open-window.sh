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

# ── Here-mode (--here): refocus the existing terminal/app; never spawn ───────
HERE_APP_FILE="$USER_TAG.here-app"
if [[ -f "$HERE_APP_FILE" && "$OSTYPE" == "darwin"* ]]; then
  HERE_APP=$(cat "$HERE_APP_FILE")
  case "$TERM_KIND" in
    terminal|iterm)
      TARGET_APP="Terminal"
      [[ "$TERM_KIND" == "iterm" ]] && TARGET_APP="iTerm"
      if [[ -f "$WIN_ID_FILE" ]]; then
        WIN_ID=$(cat "$WIN_ID_FILE")
        osascript 2>/dev/null <<EOF
tell application "$TARGET_APP"
  activate
  try
    set index of (first window whose id is $WIN_ID) to 1
  end try
end tell
EOF
        echo "[$(date '+%H:%M:%S')] open-window.sh: here-mode refocused $TARGET_APP window $WIN_ID" >> "$LOG"
        exit 0
      fi
      ;;
  esac
  osascript -e "tell application \"$HERE_APP\" to activate" 2>/dev/null
  echo "[$(date '+%H:%M:%S')] open-window.sh: here-mode activated $HERE_APP" >> "$LOG"
  exit 0
fi

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
set wasRunning to application "Terminal" is running
tell application "Terminal"
  activate
  if wasRunning then
    do script "TMUX= tmux attach-session -t '$SESSION'"
  else
    repeat 40 times
      if (count of windows) > 0 then exit repeat
      delay 0.05
    end repeat
    do script "TMUX= tmux attach-session -t '$SESSION'" in window 1
  end if
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
set wasRunning to application "iTerm" is running
tell application "iTerm"
  activate
  if wasRunning then
    set newWin to (create window with default profile command "TMUX= tmux attach-session -t '$SESSION'")
  else
    repeat 40 times
      if (count of windows) > 0 then exit repeat
      delay 0.05
    end repeat
    tell current window to tell current session to write text "TMUX= tmux attach-session -t '$SESSION'"
    set newWin to current window
  end if
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
