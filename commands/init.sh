#!/usr/bin/env bash

init_usage() {
  cat <<'USAGE'
Usage: dockr init [options]

Options:
  --host <name>            Host profile name (required)
  --addr <ip-or-host>      Primary IP or hostname for TLS SANs
  --domain <fqdn>          Traefik/ACME primary domain
  --email <email>          Contact email for ACME certificates
  --remote-port <port>     Docker TLS port (default: 2376)
  --no-remote-api          Disable Docker remote API listener
  --sshkeymgr              Install sshkeymgr helper
  --with-traefik           Install Traefik after bootstrap
  --tls-days <days>        Validity period for generated certs (default: 365)
  --dry-run                Print planned actions without executing (partial support)
  -h, --help               Show this help
USAGE
}

plan_or_run() {
  local dry_run="$1"
  shift
  if [[ "$dry_run" == true ]]; then
    log_info "[dry-run] $*"
  else
    "$@"
  fi
}

run_or_skipped() {
  local dry_run="$1"
  shift
  if [[ "$dry_run" == true ]]; then
    log_info "[dry-run] $*"
  else
    "$@"
  fi
}

apply_init_packages() {
  local dry_run="$1"
  local packages=(jq curl ca-certificates gnupg lsb-release software-properties-common ufw python3 python3-yaml apache2-utils)
  if command_exists git; then
    :
  else
    packages+=(git)
  fi
  if [[ "$dry_run" == true ]]; then
    log_info "[dry-run] Would ensure packages: ${packages[*]}"
  else
    apt_install_packages "${packages[@]}"
  fi
}

init_host_profile_summary() {
  local host="$1" addr="$2" domain="$3" email="$4" remote_api="$5" features="$6" port="$7"
  cat <<SUMMARY
Host profile saved to $(host_profile_path "$host"):
  name: $host
  address: ${addr:-auto}
  domain: ${domain:-none}
  email: ${email:-none}
  remote_api: $remote_api (port $port)
  features: ${features//\n/, }
SUMMARY
}

dockr_cmd_init() {
  local host="" addr="" domain="" email="" remote_api=true port=2376 install_sshkeymgr=false enable_traefik=false tls_days=365 dry_run=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        host="$2"; shift 2 ;;
      --addr)
        addr="$2"; shift 2 ;;
      --domain)
        domain="$2"; shift 2 ;;
      --email|--acme-email)
        email="$2"; shift 2 ;;
      --remote-port)
        port="$2"; shift 2 ;;
      --no-remote-api)
        remote_api=false; shift ;;
      --remote-api)
        remote_api=true; shift ;;
      --sshkeymgr|--install-sshkeymgr)
        install_sshkeymgr=true; shift ;;
      --with-traefik)
        enable_traefik=true; shift ;;
      --tls-days)
        tls_days="$2"; shift 2 ;;
      --dry-run)
        dry_run=true; shift ;;
      -h|--help)
        init_usage
        return 0 ;;
      *)
        log_error "Unknown option for init: $1"
        init_usage
        return 1 ;;
    esac
  done

  if [[ -z "$host" ]]; then
    log_fatal "--host is required"
  fi

  if [[ "$dry_run" == false ]]; then
    ensure_root
  fi

  log_info "Bootstrapping host '$host'"

  apply_init_packages "$dry_run"

  if [[ "$dry_run" == false ]]; then
    install_docker_engine
    ensure_docker_certificates "$host" "$addr" "$domain" "dockr" "$tls_days"
    configure_docker_daemon true "$remote_api" "$port"
    configure_ufw_defaults
    if [[ "$remote_api" == true ]]; then
      ensure_ufw_remote_api "$port"
    fi
    ufw_enable_if_needed
  else
    log_info "[dry-run] Would install Docker engine"
    log_info "[dry-run] Would generate TLS certificates in $DOCKER_CERT_DIR"
    log_info "[dry-run] Would configure Docker daemon with remote API=$remote_api"
    log_info "[dry-run] Would configure UFW defaults and remote API port $port"
  fi

  local features_list="  - base"
  if [[ "$remote_api" == true ]]; then
    features_list+=$'\n  - remote_api'
  fi
  if [[ "$install_sshkeymgr" == true ]]; then
    features_list+=$'\n  - sshkeymgr'
    if [[ "$dry_run" == false ]]; then
      install_sshkeymgr
    else
      log_info "[dry-run] Would install sshkeymgr"
    fi
  fi
  if [[ "$enable_traefik" == true ]]; then
    features_list+=$'\n  - traefik'
  fi

  if [[ "$dry_run" == false ]]; then
    save_host_profile "$host" "$addr" "$domain" "$email" "$remote_api" "$features_list"
    init_host_profile_summary "$host" "$addr" "$domain" "$email" "$remote_api" "$features_list" "$port"
  else
    log_info "[dry-run] Would save host profile"
  fi

  if [[ "$enable_traefik" == true ]]; then
    log_info "Traefik installation requested; run 'dockr traefik install --host $host' once init completes."
  fi

  log_info "dockr init complete"
}
