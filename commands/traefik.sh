#!/usr/bin/env bash

traefik_usage() {
  cat <<'USAGE'
Usage: dockr traefik <install|status|remove> [options]

Options for install:
  --host <name>             Host profile to read defaults
  --email <email>           ACME email (required if not in host profile)
  --staging                 Use Let's Encrypt staging CA
  --image <image>           Traefik image (default: traefik:latest)
  --dashboard-user <user>   Basic auth user for dashboard
  --dashboard-password <pw> Basic auth password
  -h, --help                Show help
USAGE
}

dockr_cmd_traefik() {
  if [[ $# -lt 1 ]]; then
    traefik_usage
    return 1
  fi
  local action="$1"; shift
  local host="" email="" staging=false image="$TRAEFIK_IMAGE_DEFAULT" dash_user="" dash_pass=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        host="$2"; shift 2 ;;
      --email|--acme-email)
        email="$2"; shift 2 ;;
      --staging)
        staging=true; shift ;;
      --image)
        image="$2"; shift 2 ;;
      --dashboard-user)
        dash_user="$2"; shift 2 ;;
      --dashboard-password)
        dash_pass="$2"; shift 2 ;;
      -h|--help)
        traefik_usage
        return 0 ;;
      *)
        log_error "Unknown option for traefik: $1"
        traefik_usage
        return 1 ;;
    esac
  done

  case "$action" in
    install)
      if [[ -n "$host" ]]; then
        if [[ -z "$email" ]]; then
          email=$(host_profile_get "$host" email || true)
        fi
      fi
      if [[ -z "$email" ]]; then
        log_fatal "ACME email required (--email or host profile)"
      fi
      traefik_install "$email" "$staging" "$image" "$dash_user" "$dash_pass"
      ;;
    status)
      if [[ -f "$TRAEFIK_COMPOSE" ]]; then
        traefik_status
      else
        log_warn "Traefik compose file not found at $TRAEFIK_COMPOSE"
      fi
      ;;
    remove)
      traefik_remove
      ;;
    *)
      log_error "Unsupported traefik action: $action"
      traefik_usage
      return 1 ;;
  esac
}

