#!/usr/bin/env bash

configure_ufw_defaults() {
  if ! command_exists ufw; then
    apt_install_packages ufw
  fi
  if ! ufw status >/dev/null 2>&1; then
    log_warn "UFW not configured; enabling with defaults"
  fi

  ufw default deny incoming
  ufw default allow outgoing

  local ports=(22 80 443)
  for port in "${ports[@]}"; do
    ufw allow "$port"/tcp >/dev/null
  done
}

ensure_ufw_remote_api() {
  local port="$1"
  ufw allow "$port"/tcp >/dev/null
}

ufw_enable_if_needed() {
  local status
  status=$(ufw status | head -n1)
  if [[ "$status" == "Status: inactive" ]]; then
    echo "y" | ufw enable
  fi
}

