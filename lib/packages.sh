#!/usr/bin/env bash

APT_UPDATED=0

apt_update_once() {
  if [[ $APT_UPDATED -eq 0 ]]; then
    log_info "Running apt-get update"
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    APT_UPDATED=1
  fi
}

apt_install_packages() {
  local packages=("$@")
  local to_install=()
  for pkg in "${packages[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      continue
    fi
    to_install+=("$pkg")
  done
  if [[ ${#to_install[@]} -eq 0 ]]; then
    return
  fi
  apt_update_once
  log_info "Installing packages: ${to_install[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${to_install[@]}"
}

