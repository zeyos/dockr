#!/usr/bin/env bash

deploy_compose_up() {
  local compose_file="$1" project="$2" pull="$3" remove_orphans="$4"
  ensure_root
  local cmd=(docker compose -f "$compose_file" up -d)
  if [[ "$remove_orphans" == true ]]; then
    cmd+=(--remove-orphans)
  fi
  if [[ "$pull" == true ]]; then
    docker compose -f "$compose_file" pull
  fi
  COMPOSE_PROJECT_NAME="$project" "${cmd[@]}"
}

deploy_compose_down() {
  local compose_file="$1" project="$2"
  ensure_root
  COMPOSE_PROJECT_NAME="$project" docker compose -f "$compose_file" down
}
