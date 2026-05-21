# claude-popup

Claude Code runs in the background. A floating terminal pops up automatically whenever it needs your input — then disappears when you're done.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/dquigles/claude-popup/main/install.sh | bash
```

The installer will:

- Check and install missing dependencies (`tmux`, `jq`) via Homebrew (Mac) or apt/dnf/pacman (Linux)
- Download the hook and run scripts to `~/.claude-popup/`
- Register the `Notification` hook in your Claude Code settings (globally or per-project — your choice)
- Optionally add a `claude-popup` shell alias

## Run

```bash
~/.claude-popup/run.sh
# or, if you added the alias:
claude-popup
```

Claude Code starts in a background tmux session and a window opens automatically, attached to it. The window uses the same terminal emulator you launched `claude-popup` from (Terminal.app or iTerm2 on macOS — anything else falls back to Terminal.app). The tmux session inherits your current working directory, so Claude opens in the right project.

Whenever Claude needs input later, that same window is refocused. Press **Ctrl+D** (or close the window) to send it back to the background.

## Usage

```bash
claude-popup                 # start (or refocus) Claude
claude-popup --status        # show session, window, and emulator state
claude-popup --stop          # kill the session and clean up tracking files
claude-popup --reset         # kill the session, then start a fresh one
claude-popup -- --resume     # everything after `--` is passed to `claude`
```

### Environment variables

- `CLAUDE_POPUP_TERMINAL=iterm|terminal` — force a specific emulator instead of auto-detect.
- `CLAUDE_POPUP_NOTIFY=0` — suppress the macOS notification banner when Claude needs input.
- `CLAUDE_POPUP_KEEP_ALIVE=1` — keep the tmux session running after the popup window closes (default: closing the window ends the session).

## Manual attach (optional)

If the popup window was closed and you want to reattach without restarting:

```bash
tmux attach -t claude-code
```

## Requirements

- macOS or Linux
- [`claude` CLI](https://docs.anthropic.com/en/docs/claude-code/overview) installed (`npm install -g @anthropic-ai/claude-code`)
- `tmux` and `jq` (auto-installed if missing)

## How it works

`run.sh` starts Claude Code inside a background tmux session (rooted at `$PWD`) and opens a window attached to it via a shared helper (`hooks/open-window.sh`). The detected emulator (`terminal` or `iterm`) and the window id are persisted under `/tmp/claude-popup-${USER}.*` so subsequent events can refocus the same window in the same app. Claude Code's `Notification` hook calls the same helper whenever Claude needs your input — if the window is still alive it just gets refocused, otherwise a new one is opened. When you submit input, the `UserPromptSubmit`/`PostToolUse` hooks (`detach.sh`) restore focus to whatever app was frontmost before the popup appeared.
