#!/usr/bin/env bash

set -o pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log_fatal "dockr must run as root; re-run with sudo or as root user."
  fi
}

ensure_directory() {
  local dir="$1" perms="${2:-}" owner="${3:-}" group="${4:-}"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
  fi
  if [[ -n "$perms" ]]; then
    chmod "$perms" "$dir"
  fi
  if [[ -n "$owner" || -n "$group" ]]; then
    chown "${owner:-root}:${group:-${owner:-root}}" "$dir"
  fi
}

run_cmd() {
  local description="$1"; shift
  log_info "$description"
  "$@"
}

confirm() {
  local prompt="$1" default_yes="${2:-false}"
  if [[ "${DOCKR_ASSUME_YES:-0}" -eq 1 ]]; then
    return 0
  fi
  local yn
  if [[ "$default_yes" == true ]]; then
    read -r -p "$prompt [Y/n] " yn
    yn=${yn:-Y}
  else
    read -r -p "$prompt [y/N] " yn
    yn=${yn:-N}
  fi
  case "$yn" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

require_command() {
  local cmd="$1" package_hint="${2:-}" extra="${3:-}";
  if ! command_exists "$cmd"; then
    if [[ -n "$package_hint" ]]; then
      log_fatal "Command '$cmd' not found. Install package '$package_hint'. $extra"
    else
      log_fatal "Command '$cmd' not found in PATH."
    fi
  fi
}

ensure_file_contents() {
  local path="$1" content="$2" perms="${3:-}" owner="${4:-}" group="${5:-}"
  local tmp
  tmp="$(mktemp)"
  printf '%s
' "$content" >"$tmp"
  if [[ ! -f "$path" ]] || ! cmp -s "$tmp" "$path"; then
    log_info "Updating $path"
    install -m "${perms:-644}" -o "${owner:-root}" -g "${group:-root}" "$tmp" "$path"
  fi
  rm -f "$tmp"
}

json_merge() {
  local jq_expr="$1" file="$2"
  require_command jq jq
  local tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    jq "$jq_expr" "$file" >"$tmp"
  else
    jq "$jq_expr" <<<'{}' >"$tmp"
  fi
  mv "$tmp" "$file"
}

current_timestamp() {
  date '+%Y%m%d%H%M%S'
}

