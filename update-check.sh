#!/usr/bin/env bash
# claude-popup: update-check.sh
# Sourced by run.sh. Compares the installed commit SHA against main HEAD on
# GitHub once per day and offers to refresh script files in place.

CLAUDE_POPUP_REPO="${CLAUDE_POPUP_REPO:-dquigles/claude-popup}"
CLAUDE_POPUP_RAW_URL="https://raw.githubusercontent.com/${CLAUDE_POPUP_REPO}/main"
CLAUDE_POPUP_API_URL="https://api.github.com/repos/${CLAUDE_POPUP_REPO}/commits/main"
CLAUDE_POPUP_UPDATE_THROTTLE="${CLAUDE_POPUP_UPDATE_THROTTLE:-86400}"

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

maybe_check_update() {
  local force="${1:-0}"
  local install_dir
  install_dir=$(_uc_install_dir)
  local version_file="$install_dir/.version"
  local stamp_file="$install_dir/.update-check"

  local now last
  now=$(date +%s)
  if [[ "$force" != "1" && -f "$stamp_file" ]]; then
    last=$(cat "$stamp_file" 2>/dev/null || echo 0)
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    if (( now - last < CLAUDE_POPUP_UPDATE_THROTTLE )); then
      _uc_log "throttled (last=$last now=$now)"
      return 0
    fi
  fi

  # Write the stamp upfront so transient failures don't re-prompt today.
  echo "$now" > "$stamp_file" 2>/dev/null || true

  local remote_sha
  remote_sha=$(curl -fsSL --max-time 5 "$CLAUDE_POPUP_API_URL" 2>>"${LOG:-/dev/null}" \
               | jq -r '.sha // empty' 2>>"${LOG:-/dev/null}")
  if [[ -z "$remote_sha" || "$remote_sha" == "null" ]]; then
    _uc_log "fetch failed"
    return 0
  fi

  local local_sha=""
  [[ -f "$version_file" ]] && local_sha=$(cat "$version_file" 2>/dev/null | tr -d '[:space:]')
  if [[ -z "$local_sha" ]]; then
    # First check with no baseline — silently adopt current remote SHA.
    echo "$remote_sha" > "$version_file"
    _uc_log "seeded baseline $remote_sha"
    return 0
  fi

  if [[ "$local_sha" == "$remote_sha" ]]; then
    _uc_log "up to date ($local_sha)"
    return 0
  fi

  local short_l="${local_sha:0:7}" short_r="${remote_sha:0:7}"
  echo "claude-popup: update available (${short_l} → ${short_r})" >&2
  local ans=""
  # Prompt via /dev/tty so a piped stdin can't auto-confirm. If the tty is
  # unreachable, treat as decline — never download without explicit consent.
  if ! { read -rp "Update now? [Y/n] " ans </dev/tty; } 2>/dev/null; then
    _uc_log "no tty for prompt; skipping update"
    return 0
  fi
  case "$ans" in
    n|N|no|NO|No)
      _uc_log "user declined $remote_sha"
      return 0
      ;;
  esac

  _uc_do_update "$remote_sha" "$install_dir"
}
