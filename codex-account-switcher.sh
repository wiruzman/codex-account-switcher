#!/usr/bin/env bash
set -euo pipefail

umask 077

# The July 2026 desktop update keeps Codex's bundle identifier but renames the
# application bundle and executable from Codex to ChatGPT.
CODEX_APP_PATH="${CODEX_APP_PATH:-}"
SWITCHER_HOME="${SWITCHER_HOME:-$HOME/Library/Application Support/CodexAccountSwitcher}"
PROFILES_DIR="$SWITCHER_HOME/profiles"
ACTIVE_FILE="$SWITCHER_HOME/active-profile"
LOCK_DIR="$SWITCHER_HOME/.lock"

CODEX_AUTH_FILE="${CODEX_AUTH_FILE:-$HOME/.codex/auth.json}"
CODEX_APP_SUPPORT="${CODEX_APP_SUPPORT:-$HOME/Library/Application Support/Codex}"

usage() {
  cat <<'USAGE'
Codex Account Switcher

Usage:
  codex-account-switcher.sh capture <profile>
  codex-account-switcher.sh switch <profile> [--no-open]
  codex-account-switcher.sh list [--plain]
  codex-account-switcher.sh active
  codex-account-switcher.sh open-folder

Environment overrides:
  SWITCHER_HOME       Profile storage directory
  CODEX_AUTH_FILE     Codex CLI auth file, default ~/.codex/auth.json
  CODEX_APP_SUPPORT   Codex Desktop state directory, default ~/Library/Application Support/Codex
  CODEX_APP_PATH      Codex/ChatGPT app bundle path, for non-standard installations
USAGE
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*" >&2
}

ensure_store() {
  mkdir -p "$PROFILES_DIR"
}

with_lock() {
  ensure_store
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    fail "another switch is already running"
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
}

validate_profile_name() {
  local name="${1:-}"
  [[ -n "$name" ]] || fail "profile name is required"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || \
    fail "profile name may only contain letters, numbers, dot, dash, and underscore"
}

profile_dir() {
  printf '%s/%s\n' "$PROFILES_DIR" "$1"
}

profile_auth_file() {
  printf '%s/auth/auth.json\n' "$(profile_dir "$1")"
}

profile_app_support_dir() {
  printf '%s/app-support/Codex\n' "$(profile_dir "$1")"
}

active_profile() {
  if [[ -f "$ACTIVE_FILE" ]]; then
    sed -n '1p' "$ACTIVE_FILE"
  fi
}

bundle_value() {
  local app_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$app_path/Contents/Info.plist" 2>/dev/null || true
}

is_codex_bundle() {
  local app_path="$1"
  [[ "$(bundle_value "$app_path" "CFBundleIdentifier")" == "com.openai.codex" ]]
}

codex_app_path() {
  local candidate

  if [[ -n "$CODEX_APP_PATH" ]]; then
    [[ -d "$CODEX_APP_PATH" ]] || fail "CODEX_APP_PATH is not an app bundle: $CODEX_APP_PATH"
    printf '%s\n' "$CODEX_APP_PATH"
    return 0
  fi

  # Codex now updates in place as ChatGPT.app. Check its exact bundle
  # identifier so an unrelated ChatGPT installation is never selected.
  for candidate in "/Applications/ChatGPT.app" "$HOME/Applications/ChatGPT.app"; do
    if [[ -d "$candidate" ]] && is_codex_bundle "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

codex_app_name() {
  local app_path
  app_path="$(codex_app_path || true)"
  if [[ -n "$app_path" ]]; then
    bundle_value "$app_path" "CFBundleDisplayName"
    return 0
  fi
  printf '%s\n' "ChatGPT"
}

codex_process_name() {
  local app_path
  app_path="$(codex_app_path || true)"
  if [[ -n "$app_path" ]]; then
    bundle_value "$app_path" "CFBundleExecutable"
  fi
}

is_codex_running() {
  local process_name
  process_name="$(codex_process_name || true)"
  if [[ -n "$process_name" ]]; then
    pgrep -x "$process_name" >/dev/null 2>&1
    return
  fi

  # Fallback for a non-standard installation where only the display name is available.
  pgrep -x "ChatGPT" >/dev/null 2>&1
}

wait_for_codex_to_stop() {
  for _ in {1..40}; do
    if ! is_codex_running; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_for_codex_to_start() {
  for _ in {1..40}; do
    if is_codex_running; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

quit_application() {
  local app_name="$1"
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'tell application (item 1 of argv) to quit' \
    -e 'end run' \
    "$app_name" >/dev/null 2>&1 || true
}

copy_file_if_present() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$src" ]]; then
    cp -p "$src" "$dst"
    chmod 600 "$dst" 2>/dev/null || true
  else
    rm -f "$dst"
  fi
}

assert_safe_sync_target() {
  local dst="$1"
  case "$dst" in
    ""|"/"|"$HOME"|"$HOME/"|"$HOME/Library"|"$HOME/Library/Application Support")
      fail "refusing to sync into unsafe target: $dst"
      ;;
  esac
}

sync_dir_if_present() {
  local src="$1"
  local dst="$2"
  assert_safe_sync_target "$dst"

  if [[ -d "$src" && -d "$dst" ]]; then
    local src_real dst_real
    src_real="$(cd "$src" && pwd -P)"
    dst_real="$(cd "$dst" && pwd -P)"
    [[ "$src_real" != "$dst_real" ]] || fail "refusing to sync a directory onto itself: $src"
  fi

  mkdir -p "$(dirname "$dst")"
  if [[ ! -d "$src" ]]; then
    rm -rf "$dst"
    return 0
  fi

  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --checksum --delete \
      --exclude 'Cache/' \
      --exclude 'Code Cache/' \
      --exclude 'Crashpad/' \
      --exclude 'DawnGraphiteCache/' \
      --exclude 'DawnWebGPUCache/' \
      --exclude 'GPUCache/' \
      "$src"/ "$dst"/
  else
    local tmp="$dst.tmp.$$"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    cp -pR "$src"/. "$tmp"/
    rm -rf "$dst"
    mv "$tmp" "$dst"
  fi
}

capture_into_profile() {
  local name="$1"
  validate_profile_name "$name"
  ensure_store

  local dir
  dir="$(profile_dir "$name")"
  mkdir -p "$dir/auth" "$dir/app-support"

  copy_file_if_present "$CODEX_AUTH_FILE" "$(profile_auth_file "$name")"
  sync_dir_if_present "$CODEX_APP_SUPPORT" "$(profile_app_support_dir "$name")"

  {
    printf 'name=%s\n' "$name"
    printf 'captured_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'auth_file=%s\n' "$CODEX_AUTH_FILE"
    printf 'app_support=%s\n' "$CODEX_APP_SUPPORT"
  } > "$dir/profile.env"
}

cmd_capture() {
  local name="${1:-}"
  validate_profile_name "$name"
  with_lock
  log "quitting $(codex_app_name) before capture"
  quit_codex
  capture_into_profile "$name"
  printf '%s\n' "$name" > "$ACTIVE_FILE"
  log "captured current Codex state as '$name'"
}

quit_codex() {
  local app_name
  app_name="$(codex_app_name)"
  quit_application "$app_name"
  if ! wait_for_codex_to_stop; then
    log "warning: $app_name is still running; continuing anyway"
  fi
}

open_codex() {
  local app_path app_name
  app_path="$(codex_app_path || true)"
  app_name="$(codex_app_name)"

  if [[ -n "$app_path" ]]; then
    /usr/bin/open "$app_path" >/dev/null 2>&1 || fail "could not open $app_path"
  else
    /usr/bin/open -a "$app_name" >/dev/null 2>&1 || \
      fail "could not find the Codex app; set CODEX_APP_PATH to its .app bundle"
  fi

  if wait_for_codex_to_start; then
    return 0
  fi

  # A just-updated Electron app can still be clearing its old singleton when
  # the first launch request arrives. Submit one more request before reporting
  # a failure to the menu-bar app instead of silently swallowing it.
  log "retrying $app_name launch"
  if [[ -n "$app_path" ]]; then
    /usr/bin/open "$app_path" >/dev/null 2>&1 || fail "could not open $app_path"
  else
    /usr/bin/open -a "$app_name" >/dev/null 2>&1 || \
      fail "could not find the Codex app; set CODEX_APP_PATH to its .app bundle"
  fi

  wait_for_codex_to_start || fail "$app_name did not start; try opening it once, then switch again"
}

restore_profile() {
  local name="$1"
  local auth_src app_src
  auth_src="$(profile_auth_file "$name")"
  app_src="$(profile_app_support_dir "$name")"

  [[ -d "$(profile_dir "$name")" ]] || fail "profile '$name' does not exist"
  [[ -f "$auth_src" ]] || fail "profile '$name' has no auth.json; capture it after logging in"

  mkdir -p "$(dirname "$CODEX_AUTH_FILE")"
  cp -p "$auth_src" "$CODEX_AUTH_FILE"
  chmod 600 "$CODEX_AUTH_FILE" 2>/dev/null || true

  if [[ -d "$app_src" ]]; then
    sync_dir_if_present "$app_src" "$CODEX_APP_SUPPORT"
  else
    log "warning: profile '$name' has no Codex Desktop state; only auth.json was restored"
  fi
}

cmd_switch() {
  local name="${1:-}"
  local no_open="${2:-}"
  validate_profile_name "$name"
  [[ "$no_open" == "" || "$no_open" == "--no-open" ]] || fail "unknown option: $no_open"

  with_lock

  local current
  current="$(active_profile || true)"
  if [[ -z "$current" ]]; then
    fail "no active profile is recorded; run 'capture <profile>' for the current account first"
  fi
  validate_profile_name "$current"

  log "quitting $(codex_app_name)"
  quit_codex

  if [[ "$current" != "$name" ]]; then
    log "saving current Codex state into '$current'"
    capture_into_profile "$current"
  fi

  log "switching to '$name'"
  restore_profile "$name"
  printf '%s\n' "$name" > "$ACTIVE_FILE"

  if [[ "$no_open" != "--no-open" ]]; then
    log "opening $(codex_app_name)"
    open_codex
  fi
}

cmd_list() {
  local plain="${1:-}"
  [[ "$plain" == "" || "$plain" == "--plain" ]] || fail "unknown option: $plain"
  ensure_store
  local active
  active="$(active_profile || true)"

  find "$PROFILES_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort | while IFS= read -r dir; do
    local name
    name="$(basename "$dir")"
    if [[ "$plain" == "--plain" ]]; then
      printf '%s\n' "$name"
    elif [[ "$name" == "$active" ]]; then
      printf '* %s\n' "$name"
    else
      printf '  %s\n' "$name"
    fi
  done
}

cmd_active() {
  active_profile || true
}

cmd_open_folder() {
  ensure_store
  /usr/bin/open "$SWITCHER_HOME"
}

main() {
  local command="${1:-}"
  shift || true

  if [[ -n "$CODEX_APP_PATH" && ! -d "$CODEX_APP_PATH" ]]; then
    fail "CODEX_APP_PATH is not an app bundle: $CODEX_APP_PATH"
  fi

  case "$command" in
    capture) cmd_capture "$@" ;;
    switch) cmd_switch "$@" ;;
    list) cmd_list "$@" ;;
    active) cmd_active ;;
    open-folder) cmd_open_folder ;;
    -h|--help|help|"") usage ;;
    *) fail "unknown command: $command" ;;
  esac
}

main "$@"
