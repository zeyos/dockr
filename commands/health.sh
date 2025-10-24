#!/usr/bin/env bash

health_usage() {
  cat <<'USAGE'
Usage: dockr health [--json]

Runs a set of host-level checks covering Docker, certificates, UFW, and Traefik.
USAGE
}

dockr_cmd_health() {
  local json=${DOCKR_OUTPUT_FORMAT:-text}
  local docker_status ufw_status traefik_status expiration

  if systemctl is-active --quiet docker; then
    docker_status="ok"
  else
    docker_status="failed"
  fi

  if command_exists ufw; then
    if ufw status | grep -q "Status: active"; then
      ufw_status="active"
    else
      ufw_status="inactive"
    fi
  else
    ufw_status="missing"
  fi

  if [[ -f "$TRAEFIK_COMPOSE" ]]; then
    if docker compose -f "$TRAEFIK_COMPOSE" ps traefik 2>/dev/null | grep -q Up; then
      traefik_status="up"
    else
      traefik_status="down"
    fi
  else
    traefik_status="not-installed"
  fi

  if [[ -f "$DOCKER_CERT_DIR/server-cert.pem" ]]; then
    expiration=$(openssl x509 -in "$DOCKER_CERT_DIR/server-cert.pem" -noout -enddate | cut -d= -f2)
  fi

  if [[ "$json" == "json" ]]; then
    python3 - <<PY
import json
print(json.dumps({
  "docker": "$docker_status",
  "ufw": "$ufw_status",
  "traefik": "$traefik_status",
  "docker_cert_expiry": "$expiration"
}))
PY
  else
    printf 'Docker: %s\n' "$docker_status"
    printf 'UFW: %s\n' "$ufw_status"
    printf 'Traefik: %s\n' "$traefik_status"
    if [[ -n "$expiration" ]]; then
      printf 'Docker TLS expires: %s\n' "$expiration"
    fi
  fi
}

