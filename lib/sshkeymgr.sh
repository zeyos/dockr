#!/usr/bin/env bash

SSHKEYMGR_DIR=/opt/sshkeymgr
SSHKEYMGR_REPO=https://github.com/zeyosinc/sshkeymgr.git
SSHKEYMGR_CRON=/etc/cron.d/zeyos-sshkeymgr
SSHKEYMGR_CRON_CONTENT="# /etc/cron.d/zeyos-sshkeymgr
# Updates authorized_keys hourly via sshkeymgr
0 * * * *   root   /opt/sshkeymgr/sshkeymgr.sh zeyon hetzner-cloud >/dev/null 2>&1
"

install_sshkeymgr() {
  if [[ ! -d "$SSHKEYMGR_DIR" ]]; then
    log_info "Cloning sshkeymgr"
    apt_install_packages git
    git clone "$SSHKEYMGR_REPO" "$SSHKEYMGR_DIR"
  else
    log_info "sshkeymgr already present"
  fi
  chmod +x "$SSHKEYMGR_DIR/sshkeymgr.sh"
  ensure_file_contents "$SSHKEYMGR_CRON" "$SSHKEYMGR_CRON_CONTENT" 644 root root
}

