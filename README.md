# claude-tmux-popup

Claude Code runs in the background. A floating terminal pops up automatically whenever it needs your input — then disappears when you're done.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/dquigles/claude-popup/main/install.sh | bash
```

The installer will:

- Check and install missing dependencies (`tmux`, `jq`) via Homebrew (Mac) or apt/dnf/pacman (Linux)
- Download the hook and run scripts to `~/.claude-tmux-popup/`
- Register the `Notification` hook in your Claude Code settings (globally or per-project — your choice)
- Optionally add a `claude-popup` shell alias

## Run

```bash
~/.claude-tmux-popup/run.sh
# or, if you added the alias:
claude-popup
```

Claude Code starts in a background tmux session. Whenever it needs input, a popup appears. Give your input, then press **Ctrl+D** to dismiss the popup and go back to whatever you were doing.

## Manual attach

```bash
tmux attach -t claude-code
```

## Reset / restart session

```bash
~/.claude-tmux-popup/run.sh --reset
```

## Requirements

- macOS or Linux
- [`claude` CLI](https://docs.anthropic.com/en/docs/claude-code/overview) installed (`npm install -g @anthropic-ai/claude-code`)
- `tmux` and `jq` (auto-installed if missing)

## How it works

Claude Code's `Notification` hook fires whenever Claude needs user input. The hook script calls `tmux display-popup`, which opens a floating terminal window attached to the background Claude session. When you submit your input and press Ctrl+D, the popup closes (the `-E` flag on `display-popup` ensures this) and focus returns to whatever you were doing.
