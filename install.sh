#!/usr/bin/env bash
# claude-popup installer
# One-command install: curl -fsSL https://raw.githubusercontent.com/dquigles/claude-popup/main/install.sh | bash

set -e

REPO_URL="https://raw.githubusercontent.com/dquigles/claude-popup/main"
INSTALL_DIR="$HOME/.claude-popup"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "╔══════════════════════════════════════╗"
echo "║        claude-popup installer        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Detect OS ────────────────────────────────────────────────────────────────
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "mac"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "linux"
  else
    echo "unknown"
  fi
}

OS=$(detect_os)
if [[ "$OS" == "unknown" ]]; then
  echo -e "${RED}✗ Unsupported OS: $OSTYPE${NC}"
  exit 1
fi
echo -e "  OS detected: ${GREEN}$OS${NC}"

# ── Dependency installer ──────────────────────────────────────────────────────
install_dep() {
  local pkg=$1
  echo -e "  ${YELLOW}→ Installing $pkg...${NC}"

  if [[ "$OS" == "mac" ]]; then
    if ! command -v brew &>/dev/null; then
      echo -e "  ${YELLOW}→ Homebrew not found. Installing Homebrew first...${NC}"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      # Homebrew doesn't add itself to the current shell's PATH — add it now.
      if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    fi
    brew install "$pkg"
  elif [[ "$OS" == "linux" ]]; then
    if command -v apt-get &>/dev/null; then
      sudo apt-get install -y "$pkg"
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y "$pkg"
    elif command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm "$pkg"
    else
      echo -e "${RED}✗ Could not detect package manager. Please install $pkg manually.${NC}"
      exit 1
    fi
  fi
}

# ── Check dependencies ────────────────────────────────────────────────────────
echo ""
echo "Checking dependencies..."

for dep in tmux jq curl; do
  if command -v "$dep" &>/dev/null; then
    echo -e "  ${GREEN}✓ $dep${NC}"
  else
    echo -e "  ${YELLOW}✗ $dep not found${NC}"
    install_dep "$dep"
    echo -e "  ${GREEN}✓ $dep installed${NC}"
  fi
done

# Check claude CLI
if command -v claude &>/dev/null; then
  echo -e "  ${GREEN}✓ claude${NC}"
else
  echo -e "  ${RED}✗ Claude Code CLI not found.${NC}"
  echo "    Install it with: npm install -g @anthropic-ai/claude-code"
  echo "    Then re-run this installer."
  exit 1
fi

# ── Download files ────────────────────────────────────────────────────────────
echo ""
echo "Installing claude-popup..."

mkdir -p "$INSTALL_DIR/hooks"

curl -fsSL "$REPO_URL/hooks/popup.sh"       -o "$INSTALL_DIR/hooks/popup.sh"
curl -fsSL "$REPO_URL/hooks/detach.sh"      -o "$INSTALL_DIR/hooks/detach.sh"
curl -fsSL "$REPO_URL/hooks/open-window.sh" -o "$INSTALL_DIR/hooks/open-window.sh"
curl -fsSL "$REPO_URL/run.sh"               -o "$INSTALL_DIR/run.sh"
curl -fsSL "$REPO_URL/uninstall.sh"         -o "$INSTALL_DIR/uninstall.sh"

chmod +x "$INSTALL_DIR/hooks/popup.sh" "$INSTALL_DIR/hooks/detach.sh" \
         "$INSTALL_DIR/hooks/open-window.sh" \
         "$INSTALL_DIR/run.sh" "$INSTALL_DIR/uninstall.sh"

echo -e "  ${GREEN}✓ Files installed to $INSTALL_DIR${NC}"

# ── Ask where to apply hook ───────────────────────────────────────────────────
echo ""
echo "Where should the hook apply?"
echo "  [1] Globally — all projects (recommended)"
echo "  [2] Per-project — only the current directory"
echo ""
read -rp "  Choice [1/2]: " HOOK_SCOPE </dev/tty

if [[ "$HOOK_SCOPE" == "2" ]]; then
  CLAUDE_SETTINGS="$(pwd)/.claude/settings.json"
  mkdir -p "$(pwd)/.claude"
  echo -e "  ${YELLOW}→ Applying hook to current project: $(pwd)${NC}"
else
  mkdir -p "$HOME/.claude"
  echo -e "  ${YELLOW}→ Applying hook globally${NC}"
fi

# ── Merge hooks into settings.json ───────────────────────────────────────────
# Ensure settings file is at least valid JSON before merging.
if [[ ! -s "$CLAUDE_SETTINGS" ]] || ! jq -e . "$CLAUDE_SETTINGS" &>/dev/null; then
  echo '{}' > "$CLAUDE_SETTINGS"
fi

# Register a (event, command) hook idempotently: strips any prior copies of
# the command under that event before adding it fresh.
register_hook() {
  local event="$1" cmd="$2"
  local entry updated
  entry=$(jq -nc --arg cmd "$cmd" \
    '{matcher:"", hooks:[{type:"command", command:$cmd}]}')
  updated=$(jq \
    --arg event "$event" \
    --argjson entry "$entry" \
    --arg cmd "$cmd" \
    '.hooks[$event] = (
       ((.hooks[$event] // [])
        | map(select(([(.hooks // [])[].command] | index($cmd)) | not)))
       + [$entry]
     )' "$CLAUDE_SETTINGS")
  echo "$updated" > "$CLAUDE_SETTINGS"
}

register_hook "Notification"     "$INSTALL_DIR/hooks/popup.sh"
register_hook "Stop"             "$INSTALL_DIR/hooks/popup.sh"
register_hook "UserPromptSubmit" "$INSTALL_DIR/hooks/detach.sh"
register_hook "PostToolUse"      "$INSTALL_DIR/hooks/detach.sh"

echo -e "  ${GREEN}✓ Hooks registered in $CLAUDE_SETTINGS${NC}"

# ── Shell alias (optional) ────────────────────────────────────────────────────
echo ""
read -rp "Add 'claude-popup' alias to your shell? [Y/n]: " ADD_ALIAS </dev/tty
if [[ "$ADD_ALIAS" != "n" && "$ADD_ALIAS" != "N" ]]; then
  SHELL_RC=""
  if [[ "$SHELL" == *"zsh"* ]]; then
    SHELL_RC="$HOME/.zshrc"
  elif [[ "$SHELL" == *"bash"* ]]; then
    SHELL_RC="$HOME/.bashrc"
  fi

  if [[ -n "$SHELL_RC" ]]; then
    if [[ -f "$SHELL_RC" ]] && grep -q "^alias claude-popup=" "$SHELL_RC"; then
      echo -e "  ${GREEN}✓ Alias already present in $SHELL_RC${NC}"
    else
      echo "" >> "$SHELL_RC"
      echo "# claude-popup" >> "$SHELL_RC"
      echo "alias claude-popup='$INSTALL_DIR/run.sh'" >> "$SHELL_RC"
      echo -e "  ${GREEN}✓ Alias added to $SHELL_RC${NC}"
      echo -e "  ${YELLOW}  Run: source $SHELL_RC  (or open a new terminal)${NC}"
    fi
  else
    echo -e "  ${YELLOW}  Could not detect shell rc file. Add this manually:${NC}"
    echo "    alias claude-popup='$INSTALL_DIR/run.sh'"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo "  Start Claude Code with popup support:"
echo -e "    ${GREEN}$INSTALL_DIR/run.sh${NC}"
echo ""
echo "  Or if you added the alias:"
echo -e "    ${GREEN}claude-popup${NC}"
echo ""
echo "  Claude will pop up automatically whenever it needs your input."
echo "  Press Ctrl+D or close the popup to send it back to the background."
echo ""
