#!/usr/bin/env bash
# Auto-detach companion to popup.sh.
# Fires on UserPromptSubmit / PreToolUse — i.e. right after the user has
# responded to a prompt or granted permission. If a popup is active (marker
# file present), detach all clients so the popup terminal closes itself.

# Drain stdin (Claude Code hook payload — we don't need to inspect it).
cat >/dev/null

SESSION="claude-code"
MARKER="${TMPDIR:-/tmp}/claude-popup-${USER}.active"

# Only act if popup.sh marked an active popup. Manual attaches are left alone.
if [[ -f "$MARKER" ]]; then
  rm -f "$MARKER"
  tmux detach-client -s "$SESSION" 2>/dev/null
fi

exit 0
