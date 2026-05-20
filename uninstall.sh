#!/usr/bin/env bash
# claude-popup uninstaller
# Removes the hook from settings.json, deletes ~/.claude-popup, and strips
# the shell alias. Safe to run multiple times.

set -e

INSTALL_DIR="$HOME/.claude-popup"
POPUP_CMD="$INSTALL_DIR/hooks/popup.sh"
DETACH_CMD="$INSTALL_DIR/hooks/detach.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "╔══════════════════════════════════════╗"
echo "║       claude-popup uninstaller       ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Kill running session ──────────────────────────────────────────────────────
if command -v tmux &>/dev/null && tmux has-session -t claude-code 2>/dev/null; then
  tmux kill-session -t claude-code
  echo -e "  ${GREEN}✓ Killed running tmux session 'claude-code'${NC}"
fi

# ── Strip hooks from settings files ───────────────────────────────────────────
# Removes any hook entries whose command matches one of ours, across every
# event array under .hooks. Also prunes now-empty event arrays and an
# eventually-empty .hooks object.
strip_hooks() {
  local settings="$1"
  [[ -s "$settings" ]] || return 0
  command -v jq &>/dev/null || return 0
  jq -e . "$settings" &>/dev/null || return 0

  # Bail early if neither command appears anywhere.
  if ! jq -e --arg p "$POPUP_CMD" --arg d "$DETACH_CMD" \
        '[.. | objects | .command? // empty] | any(. == $p or . == $d)' \
        "$settings" &>/dev/null; then
    return 0
  fi

  local updated
  updated=$(jq --arg p "$POPUP_CMD" --arg d "$DETACH_CMD" '
    (.hooks // {}) as $h
    | .hooks = (
        $h
        | with_entries(
            .value |= (
              map(select(([(.hooks // [])[].command]
                           | any(. == $p or . == $d)) | not))
            )
          )
        | with_entries(select(.value | length > 0))
      )
    | if (.hooks | length) == 0 then del(.hooks) else . end
  ' "$settings")
  echo "$updated" > "$settings"
  echo -e "  ${GREEN}✓ Removed hooks from $settings${NC}"
}

strip_hooks "$HOME/.claude/settings.json"
[[ -f "$(pwd)/.claude/settings.json" ]] && strip_hooks "$(pwd)/.claude/settings.json"

# ── Remove install dir ────────────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  echo -e "  ${GREEN}✓ Removed $INSTALL_DIR${NC}"
fi

# ── Strip alias from shell rc files ───────────────────────────────────────────
for SHELL_RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [[ -f "$SHELL_RC" ]] && grep -qE '^(# claude-popup$|alias claude-popup=)' "$SHELL_RC"; then
    # sed -i.bak works on both BSD (macOS) and GNU sed
    sed -i.bak -E '/^# claude-popup$/d; /^alias claude-popup=/d' "$SHELL_RC"
    rm -f "$SHELL_RC.bak"
    echo -e "  ${GREEN}✓ Removed alias from $SHELL_RC${NC}"
  fi
done

echo ""
echo -e "${GREEN}✓ claude-popup uninstalled.${NC}"
echo -e "  ${YELLOW}Open a new terminal (or 'source ~/.zshrc') to drop the alias from your current shell.${NC}"
echo ""
