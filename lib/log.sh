#!/usr/bin/env bash

# Logging helpers with optional color output.
_dockr_log_init() {
  if [[ -n "${_DOCKR_LOG_INITIALIZED:-}" ]]; then
    return
  fi
  if command -v tput >/dev/null 2>&1 && [[ -t 2 ]]; then
    local bold="$(tput bold)" reset="$(tput sgr0)"
    DOCKR_COLOR_INFO="${bold}[*]${reset}"
    DOCKR_COLOR_WARN="${bold}[!]${reset}"
    DOCKR_COLOR_ERROR="${bold}[x]${reset}"
  else
    DOCKR_COLOR_INFO='[i]'
    DOCKR_COLOR_WARN='[!]'
    DOCKR_COLOR_ERROR='[x]'
  fi
  _DOCKR_LOG_LEVEL=${DOCKR_LOG_LEVEL:-info}
  _DOCKR_LOG_INITIALIZED=1
}

_dockr_log() {
  local level="$1"; shift
  local symbol message
  _dockr_log_init
  case "$level" in
    info)
      symbol="$DOCKR_COLOR_INFO"
      ;;
    warn)
      symbol="$DOCKR_COLOR_WARN"
      ;;
    error|fatal)
      symbol="$DOCKR_COLOR_ERROR"
      ;;
    *)
      symbol="[$level]"
      ;;
  esac
  message="$*"
  printf '%s %s\n' "$symbol" "$message" >&2
}

log_info() {
  _dockr_log info "$@"
}

log_warn() {
  _dockr_log warn "$@"
}

log_error() {
  _dockr_log error "$@"
}

log_fatal() {
  _dockr_log fatal "$@"
  exit 1
}
