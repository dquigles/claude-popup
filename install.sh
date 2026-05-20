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

curl -fsSL "$REPO_URL/hooks/popup.sh" -o "$INSTALL_DIR/hooks/popup.sh"
curl -fsSL "$REPO_URL/run.sh"         -o "$INSTALL_DIR/run.sh"

chmod +x "$INSTALL_DIR/hooks/popup.sh"
chmod +x "$INSTALL_DIR/run.sh"

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

# ── Merge hook into settings.json ────────────────────────────────────────────
HOOK_ENTRY=$(cat <<EOF
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "$INSTALL_DIR/hooks/popup.sh"
    }
  ]
}
EOF
)

if [[ -f "$CLAUDE_SETTINGS" ]]; then
  # File exists — merge the hook in with jq
  EXISTING=$(cat "$CLAUDE_SETTINGS")

  # Check if our hook is already registered
  if echo "$EXISTING" | jq -e '.hooks.Notification' &>/dev/null; then
    # Append to existing Notification array
    UPDATED=$(echo "$EXISTING" | jq \
      --argjson entry "$HOOK_ENTRY" \
      '.hooks.Notification += [$entry]')
  else
    # Add Notification key under hooks
    UPDATED=$(echo "$EXISTING" | jq \
      --argjson entry "$HOOK_ENTRY" \
      '.hooks.Notification = [$entry]')
  fi

  echo "$UPDATED" > "$CLAUDE_SETTINGS"
else
  # Create fresh settings.json
  cat > "$CLAUDE_SETTINGS" <<EOF
{
  "hooks": {
    "Notification": [
      $HOOK_ENTRY
    ]
  }
}
EOF
fi

echo -e "  ${GREEN}✓ Hook registered in $CLAUDE_SETTINGS${NC}"

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
    echo "" >> "$SHELL_RC"
    echo "# claude-popup" >> "$SHELL_RC"
    echo "alias claude-popup='$INSTALL_DIR/run.sh'" >> "$SHELL_RC"
    echo -e "  ${GREEN}✓ Alias added to $SHELL_RC${NC}"
    echo -e "  ${YELLOW}  Run: source $SHELL_RC  (or open a new terminal)${NC}"
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
