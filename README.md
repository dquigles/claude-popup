# claude-popup

Picture-in-picture for Claude Code. One command — `claude-popup` — that you use instead of `claude`. It runs Claude in a shared background tmux session, so:

- Running it in your editor terminal **attaches that terminal** to the session — works just like plain `claude`.
- When Claude needs your input and you're somewhere else, a floating Terminal/iTerm window **pops up attached to the same live conversation**, then disappears when you're done.
- Any extra terminal you run `claude-popup` in joins the same session too. Type in one, watch it appear in the others.

It's not a fork of `claude` — it's plain Claude Code running inside tmux, with a thin wrapper that handles the window choreography and a notification hook.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/dquigles/claude-popup/main/install.sh | bash
```

The installer will:

- Check and install missing dependencies (`tmux`, `jq`) via Homebrew (Mac) or apt/dnf/pacman (Linux)
- Download the hook and run scripts to `~/.claude-popup/`
- Register the `Notification` hook in your Claude Code settings (globally or per-project — your choice)
- Optionally add a `claude-popup` shell alias

## Use it

In any terminal where you'd normally run `claude`:

```bash
claude-popup
```

That's it. The wrapper figures out what to do from where it was called:

| Where you ran it | What happens |
|---|---|
| Your editor's integrated terminal (or any interactive shell) | This terminal attaches to the shared session. Use Claude exactly like normal. |
| Triggered by Claude's Notification hook from elsewhere | A floating window opens attached to the same session. |
| A second interactive terminal while one is already attached | Joins as another live view — both terminals mirror each other. |

Closing the floating window or pressing **Ctrl+D** in any attached terminal detaches that view; the session keeps running until the last viewer leaves (or `--stop`).

### Lifecycle flags

```bash
claude-popup --status        # show session, window, attached-host state
claude-popup --stop          # kill the session and close the tracked window
claude-popup --reset         # kill and re-create
claude-popup --help          # show all flags (also -h)
claude-popup -- --resume     # everything after `--` is passed to `claude` on first start
```

### Updates

`claude-popup` never checks for updates on its own. Run the update on demand:

```bash
claude-popup --update            # fetch the latest main and refresh the scripts
claude-popup --update --force    # re-download even if already up to date
```

It compares the installed commit SHA against `main` on GitHub; if they match it reports "already up to date" and does nothing. Updates only refresh files in `~/.claude-popup/` — they don't touch your Claude settings or shell rc.

### `--here`: use this terminal as the popup

By default, running `claude-popup` from an interactive shell attaches inline and **suppresses** popup focus when the host app (e.g. `Code`, `Cursor`) is frontmost — the assumption is that you're already in your editor and don't want a popup.

`--here` flips that: it attaches the current terminal *as* the popup target. When Claude needs your input, focus comes to this window; when you grant permission or finish responding, focus returns to whichever app was previously frontmost (Discord, browser, etc.). No separate window ever opens.

```bash
claude-popup --here          # use this terminal/window as the popup target
```

- Best supported in **Terminal.app** and **iTerm2** — the front window's id is captured and refocused precisely.
- From **VSCode / Cursor / other terminals**, the whole host app is activated on focus events (no window-level precision).
- macOS only.

### Suppression rules

The Notification hook won't pop a window when:

- a popup window from a previous trigger is still open, or
- a terminal is attached inline **and** that terminal's app (e.g. `Code`, `Cursor`) is currently frontmost — you're already looking at Claude.

### Environment variables

- `CLAUDE_POPUP_TERMINAL=iterm|terminal` — force a specific emulator instead of auto-detect.
- `CLAUDE_POPUP_NOTIFY=0` — suppress the macOS notification banner when Claude needs input.
- `CLAUDE_POPUP_KEEP_ALIVE=1` — keep the tmux session running after the last view closes (default: the session ends with its last viewer).

## Requirements

- macOS or Linux
- [`claude` CLI](https://docs.anthropic.com/en/docs/claude-code/overview) installed (`npm install -g @anthropic-ai/claude-code`)
- `tmux` and `jq` (auto-installed if missing)

## Limitations

**The PiP view only works for sessions you started through `claude-popup`.** If you have a plain `claude` running in another terminal, claude-popup can't attach to it — Unix PTYs can't be shared with a process that wasn't started inside a multiplexer. That plain `claude` keeps running on its own, completely independent; it just isn't a PiP-capable session.

Other `claude` instances are fine to run alongside claude-popup — the Notification hook only fires inside a `claude-code-*` tmux session, so the VS Code Claude extension, scripts that shell out to `claude`, and any other claude workflows are unaffected.

**One session per directory.** Each `$PWD` gets its own `claude-code-<hash>` tmux session. You can have independent PiP sessions for different projects running at the same time. Each can be attached from many terminals, and each has its own popup window. Use `claude-popup --status` to see all running sessions, and `claude-popup --stop --all` to kill them all.

If you'd like `claude-popup` to be your default, alias it: `alias claude=claude-popup` in your shell rc.

## How it works

`run.sh` starts Claude Code inside a background tmux session rooted at `$PWD`. It then dispatches based on whether stdin/stdout are TTYs:

- **Interactive (`[[ -t 0 && -t 1 ]]`)**: `tmux attach-session` against the current terminal. The frontmost app at attach time is recorded in `/tmp/claude-popup-${USER}-<hash>.attached-host` so the Notification hook knows when to stay quiet.
- **Non-interactive** (hook callers, scripts): `hooks/open-window.sh` opens or refocuses a Terminal/iTerm window attached to the session. Window id and emulator kind are persisted under `/tmp/claude-popup-${USER}-<hash>.*` so subsequent triggers refocus the same window in the same app.

Claude Code's `Notification` hook calls `hooks/popup.sh`, which derives the current session name from `$TMUX` and delegates to the same window helper — refocusing if alive, opening if not. After you respond, `UserPromptSubmit`/`PostToolUse` hooks (`detach.sh`) restore focus to whichever app was frontmost before the popup interrupted you.

All hooks early-exit unless they're firing inside a `claude-code-*` tmux session, so plain `claude` running anywhere else is left alone.
