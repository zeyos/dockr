#!/usr/bin/env bash

cert_usage() {
  cat <<'USAGE'
Usage: dockr cert docker <subcommand> [options]

Subcommands:
  info                 Show current Docker TLS certificate details
  rotate               Reissue Docker server/client certificates (keeps CA)
  backup               Archive current Docker TLS bundle to state backups

Common options:
  --host <name>        Host profile to read defaults (optional)
  --addr <addr>        Override host address for SANs when rotating
  --domain <fqdn>      Override domain for SANs when rotating
  --client-name <cn>   Client certificate CN (default: dockr)
  --days <n>           Validity in days (default: 365)
  -h, --help           Show help
USAGE
}

print_cert_info() {
  local cert="$1"
  if [[ ! -f "$cert" ]]; then
    log_fatal "Certificate not found: $cert"
  fi
  openssl x509 -in "$cert" -noout -subject -issuer -startdate -enddate -serial -fingerprint -sha256
}

dockr_cmd_cert() {
  if [[ $# -lt 1 ]]; then
    cert_usage
    return 1
  fi

  local namespace="$1"
  shift

  case "$namespace" in
    docker)
      dockr_cert_docker "$@"
      ;;
    *)
      log_error "Unsupported cert namespace: $namespace"
      cert_usage
      return 1
      ;;
  esac
}

dockr_cert_docker() {
  local action="" host="" addr="" domain="" client_name="dockr" days=365
  if [[ $# -lt 1 ]]; then
    cert_usage
    return 1
  fi
  action="$1"; shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        host="$2"; shift 2 ;;
      --addr)
        addr="$2"; shift 2 ;;
      --domain)
        domain="$2"; shift 2 ;;
      --client-name)
        client_name="$2"; shift 2 ;;
      --days)
        days="$2"; shift 2 ;;
      -h|--help)
        cert_usage
        return 0 ;;
      *)
        log_error "Unknown option for cert docker: $1"
        return 1 ;;
    esac
  done

  case "$action" in
    info)
      print_cert_info "$DOCKER_CERT_DIR/server-cert.pem"
      ;;
    rotate)
      ensure_root
      if [[ -n "$host" ]]; then
        addr=${addr:-$(host_profile_get "$host" address || true)}
        domain=${domain:-$(host_profile_get "$host" domain || true)}
        days=${days:-365}
      fi
      ensure_docker_certificates "${host:-$(hostname)}" "$addr" "$domain" "$client_name" "$days"
      systemd_restart_service docker
      log_info "Docker certificates rotated"
      ;;
    backup)
      ensure_root
      ensure_state_tree
      local ts archive
      ts=$(current_timestamp)
      archive=$(backup_docker_certs "$DOCKR_BACKUPS_DIR" "$ts")
      log_info "Backup created: $archive"
      ;;
    *)
      log_error "Unsupported cert docker action: $action"
      cert_usage
      return 1 ;;
  esac
}

