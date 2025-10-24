#!/usr/bin/env bash

TRAEFIK_ROOT=/opt/traefik
TRAEFIK_CONFIG_ROOT="$TRAEFIK_ROOT/config"
TRAEFIK_STATIC_DIR="$TRAEFIK_CONFIG_ROOT/static"
TRAEFIK_DYNAMIC_DIR="$TRAEFIK_CONFIG_ROOT/dynamic"
TRAEFIK_ACME_DIR="$TRAEFIK_ROOT/letsencrypt"
TRAEFIK_ACME_FILE="$TRAEFIK_ACME_DIR/acme.json"
TRAEFIK_LOG_DIR="$TRAEFIK_ROOT/log"
TRAEFIK_COMPOSE="$TRAEFIK_ROOT/docker-compose.yml"
TRAEFIK_NETWORK=traefik_proxy
TRAEFIK_IMAGE_DEFAULT="traefik:latest"

ensure_traefik_dirs() {
  ensure_directory "$TRAEFIK_ROOT" 755 root root
  ensure_directory "$TRAEFIK_CONFIG_ROOT" 755 root root
  ensure_directory "$TRAEFIK_STATIC_DIR" 755 root root
  ensure_directory "$TRAEFIK_DYNAMIC_DIR" 755 root root
  ensure_directory "$TRAEFIK_ACME_DIR" 700 root root
  ensure_directory "$TRAEFIK_LOG_DIR" 750 root root
  if [[ ! -f "$TRAEFIK_ACME_FILE" ]]; then
    touch "$TRAEFIK_ACME_FILE"
    chmod 600 "$TRAEFIK_ACME_FILE"
  fi
}

ensure_traefik_network() {
  if ! docker network inspect "$TRAEFIK_NETWORK" >/dev/null 2>&1; then
    log_info "Creating Docker network $TRAEFIK_NETWORK"
    docker network create "$TRAEFIK_NETWORK"
  fi
}

render_traefik_static() {
  local email="$1" ca_server="$2"
  render_template "$PROVIDERS_DIR/traefik/static/traefik.yml" "$TRAEFIK_STATIC_DIR/traefik.yml" \
    ACME_EMAIL "$email" \
    ACME_CA_SERVER "$ca_server"
  cp "$PROVIDERS_DIR/traefik/dynamic/security.yml" "$TRAEFIK_DYNAMIC_DIR/security.yml"
}

render_traefik_compose() {
  local image="$1"
  render_template "$TEMPLATE_DIR/traefik-compose.yml" "$TRAEFIK_COMPOSE" \
    TRAEFIK_IMAGE "$image" \
    TRAEFIK_CONFIG_DIR "$TRAEFIK_CONFIG_ROOT" \
    TRAEFIK_ACME_DIR "$TRAEFIK_ACME_DIR" \
    TRAEFIK_LOG_DIR "$TRAEFIK_LOG_DIR"
}

traefik_basic_auth() {
  local user="$1" password="$2" file="$TRAEFIK_DYNAMIC_DIR/dashboard-auth.yml"
  if [[ -z "$user" || -z "$password" ]]; then
    rm -f "$file"
    return
  fi
  local hash
  hash=$(printf '%s:%s' "$user" "$(openssl passwd -apr1 "$password")")
  cat <<YAML >"$file"
http:
  middlewares:
    dashboard-auth:
      basicAuth:
        users:
          - "$hash"
YAML
}

traefik_install() {
  local email="$1" staging="$2" image="$3" user="$4" password="$5"
  ensure_root
  ensure_state_tree
  ensure_traefik_dirs
  local ca_server="https://acme-v02.api.letsencrypt.org/directory"
  if [[ "$staging" == true ]]; then
    ca_server="https://acme-staging-v02.api.letsencrypt.org/directory"
  fi
  render_traefik_static "$email" "$ca_server"
  render_traefik_compose "$image"
  traefik_basic_auth "$user" "$password"
  ensure_traefik_network
  (cd "$TRAEFIK_ROOT" && docker compose up -d)
  log_info "Traefik deployed using $TRAEFIK_COMPOSE"
}

traefik_status() {
  docker compose -f "$TRAEFIK_COMPOSE" ps
}

traefik_remove() {
  ensure_root
  if [[ -f "$TRAEFIK_COMPOSE" ]]; then
    docker compose -f "$TRAEFIK_COMPOSE" down
    log_info "Stopped Traefik stack"
  fi
}

