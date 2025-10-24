#!/usr/bin/env bash

parse_global_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y)
        DOCKR_ASSUME_YES=1
        shift
        ;;
      --json)
        DOCKR_OUTPUT_FORMAT=json
        shift
        ;;
      --debug)
        DOCKR_LOG_LEVEL=debug
        shift
        ;;
      --help|-h)
        DOCKR_PRINT_HELP=1
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done
  printf '%s
' "$#"
}

print_global_help() {
  cat <<'HELP'
dockr - CLI for managing Docker hosts with TLS, firewall, Traefik, and deploy tooling.

Usage:
  dockr [global options] <command> [command options]

Global options:
  -y, --yes          Assume "yes" for prompts.
  --json             Emit JSON output where supported.
  --debug            Increase log verbosity.
  -h, --help         Show help.

Commands:
  init               Bootstrap an Ubuntu host with Docker, TLS, UFW, and optional extras.
  cert docker ...    Manage Docker TLS certificates (info, rotate, backup).
  traefik ...        Install or manage Traefik reverse proxy.
  route ...          Manage Traefik routes.
  deploy ...         Manage docker-compose deployments.
  health             Run host health checks.
HELP
}

