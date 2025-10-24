#!/usr/bin/env bash

deploy_usage() {
  cat <<'USAGE'
Usage: dockr deploy <up|down> [options]

Options:
  --compose-file <file>      Path to docker-compose file (default: deploy/docker-compose.yml)
  --project <name>           Compose project name (default: route host or 'dockr')
  --host <host>              Host profile to derive defaults
  --pull                     Pull latest images before up
  --no-pull                  Skip pulling images (default)
  --remove-orphans           Remove orphan containers on up (default)
  --keep-orphans             Keep orphan containers
  -h, --help                 Show help
USAGE
}

dockr_cmd_deploy() {
  if [[ $# -lt 1 ]]; then
    deploy_usage
    return 1
  fi
  local action="$1"; shift
  local compose_file="deploy/docker-compose.yml" project="dockr" pull=false remove_orphans=true host=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --compose-file)
        compose_file="$2"; shift 2 ;;
      --project)
        project="$2"; shift 2 ;;
      --host)
        host="$2"; shift 2 ;;
      --pull)
        pull=true; shift ;;
      --no-pull)
        pull=false; shift ;;
      --remove-orphans)
        remove_orphans=true; shift ;;
      --keep-orphans)
        remove_orphans=false; shift ;;
      -h|--help)
        deploy_usage
        return 0 ;;
      *)
        log_error "Unknown option for deploy: $1"
        deploy_usage
        return 1 ;;
    esac
  done

  if [[ -n "$host" && "$project" == "dockr" ]]; then
    project="$host"
  fi

  if [[ ! -f "$compose_file" ]]; then
    log_fatal "Compose file not found: $compose_file"
  fi

  case "$action" in
    up)
      deploy_compose_up "$compose_file" "$project" "$pull" "$remove_orphans"
      ;;
    down)
      deploy_compose_down "$compose_file" "$project"
      ;;
    *)
      log_error "Unsupported deploy action: $action"
      deploy_usage
      return 1 ;;
  esac
}

