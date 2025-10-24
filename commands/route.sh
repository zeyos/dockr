#!/usr/bin/env bash

route_usage() {
  cat <<'USAGE'
Usage: dockr route <list|add|remove|edit> [options]

Options:
  --host <name>             Host profile name (required)
  --name <route-name>       Route identifier (for add/remove)
  --rule <rule>             Traefik rule, e.g. Host(`app.example.com`)
  --service <service>       Service name
  --service-url <url>       Upstream URL, e.g. http://app:8080
  --middlewares <list>      Comma-separated middlewares
  -h, --help                Show help
USAGE
}

dockr_cmd_route() {
  if [[ $# -lt 1 ]]; then
    route_usage
    return 1
  fi
  local action="$1"; shift
  local host="" name="" rule="" service="" service_url="" middlewares=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        host="$2"; shift 2 ;;
      --name)
        name="$2"; shift 2 ;;
      --rule)
        rule="$2"; shift 2 ;;
      --service)
        service="$2"; shift 2 ;;
      --service-url)
        service_url="$2"; shift 2 ;;
      --middlewares)
        middlewares="$2"; shift 2 ;;
      -h|--help)
        route_usage
        return 0 ;;
      *)
        log_error "Unknown option for route: $1"
        route_usage
        return 1 ;;
    esac
  done

  if [[ -z "$host" ]]; then
    log_fatal "--host is required"
  fi

  case "$action" in
    list)
      routes_list "$host"
      ;;
    add)
      if [[ -z "$name" || -z "$rule" || -z "$service" || -z "$service_url" ]]; then
        log_fatal "--name, --rule, --service, and --service-url are required for add"
      fi
      routes_add "$host" "$name" "$rule" "$service" "$service_url" "$middlewares"
      log_info "Route '$name' added"
      ;;
    remove)
      if [[ -z "$name" ]]; then
        log_fatal "--name required for remove"
      fi
      routes_remove "$host" "$name"
      log_info "Route '$name' removed"
      ;;
    edit)
      routes_open_editor "$host"
      ;;
    *)
      log_error "Unsupported route action: $action"
      route_usage
      return 1 ;;
  esac
}

