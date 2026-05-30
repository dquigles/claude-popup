#!/usr/bin/env bash
# claude-popup: update-check.sh
# Sourced by run.sh for the `--update` flag. Compares the installed commit SHA
# against main HEAD on GitHub and refreshes the script files in place on demand.

CLAUDE_POPUP_REPO="${CLAUDE_POPUP_REPO:-dquigles/claude-popup}"
CLAUDE_POPUP_RAW_URL="https://raw.githubusercontent.com/${CLAUDE_POPUP_REPO}/main"
CLAUDE_POPUP_API_URL="https://api.github.com/repos/${CLAUDE_POPUP_REPO}/commits/main"

_uc_log() {
  local log="${LOG:-/tmp/claude-popup-debug.log}"
  echo "[update-check $(date +%H:%M:%S)] $*" >> "$log" 2>/dev/null || true
}

_uc_install_dir() {
  local d="${INSTALL_DIR:-}"
  [[ -n "$d" ]] && { echo "$d"; return; }
  # Fall back to the directory containing this script.
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

_uc_do_update() {
  local new_sha="$1" install_dir="$2"
  local tmp
  tmp=$(mktemp -d 2>/dev/null) || { _uc_log "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  local files=( run.sh update-check.sh uninstall.sh \
                hooks/popup.sh hooks/detach.sh hooks/open-window.sh )
  mkdir -p "$tmp/hooks"

  local f
  for f in "${files[@]}"; do
    if ! curl -fsSL --max-time 10 "$CLAUDE_POPUP_RAW_URL/$f" -o "$tmp/$f" 2>>"${LOG:-/dev/null}"; then
      echo "claude-popup: download of $f failed; aborting update." >&2
      _uc_log "download failed: $f"
      return 1
    fi
    if [[ ! -s "$tmp/$f" ]]; then
      echo "claude-popup: empty download for $f; aborting update." >&2
      _uc_log "empty: $f"
      return 1
    fi
    if ! head -1 "$tmp/$f" | grep -q '^#!'; then
      echo "claude-popup: $f missing shebang; aborting update." >&2
      _uc_log "no shebang: $f"
      return 1
    fi
  done

  for f in "${files[@]}"; do
    chmod +x "$tmp/$f"
    if ! mv "$tmp/$f" "$install_dir/$f"; then
      echo "claude-popup: failed to install $f; partial update." >&2
      _uc_log "mv failed: $f"
      return 1
    fi
  done

  echo "$new_sha" > "$install_dir/.version"
  echo "claude-popup: updated to ${new_sha:0:7}." >&2
  _uc_log "updated to $new_sha"
}

# On-demand update (the `--update` flag). Fetches main HEAD, and if it differs
# from the installed baseline, refreshes the script files in place. Pass "1" to
# force a re-download even when already up to date.
run_update() {
  local force="${1:-0}"
  local install_dir
  install_dir=$(_uc_install_dir)
  local version_file="$install_dir/.version"

  local remote_sha
  remote_sha=$(curl -fsSL --max-time 5 "$CLAUDE_POPUP_API_URL" 2>>"${LOG:-/dev/null}" \
               | jq -r '.sha // empty' 2>>"${LOG:-/dev/null}")
  if [[ -z "$remote_sha" || "$remote_sha" == "null" ]]; then
    echo "claude-popup: could not reach GitHub to check for updates." >&2
    _uc_log "fetch failed"
    return 1
  fi

  local local_sha=""
  [[ -f "$version_file" ]] && local_sha=$(cat "$version_file" 2>/dev/null | tr -d '[:space:]')

  if [[ "$force" != "1" && -n "$local_sha" && "$local_sha" == "$remote_sha" ]]; then
    echo "claude-popup: already up to date (${local_sha:0:7})."
    _uc_log "up to date ($local_sha)"
    return 0
  fi

  if [[ -n "$local_sha" ]]; then
    echo "claude-popup: updating ${local_sha:0:7} → ${remote_sha:0:7}..."
  else
    echo "claude-popup: installing latest (${remote_sha:0:7})..."
  fi

  _uc_do_update "$remote_sha" "$install_dir"
}
