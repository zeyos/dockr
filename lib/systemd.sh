#!/usr/bin/env bash

systemd_daemon_reload() {
  log_info "Reloading systemd daemon"
  systemctl daemon-reload
}

systemd_restart_service() {
  local service="$1"
  log_info "Restarting service: $service"
  systemctl restart "$service"
}

systemd_enable_service() {
  local service="$1"
  log_info "Enabling service: $service"
  systemctl enable "$service"
}

systemd_status() {
  systemctl status "$1"
}

