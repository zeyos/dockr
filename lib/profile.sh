#!/usr/bin/env bash

DOCKR_STATE_DIR=${DOCKR_STATE_DIR:-/root/.dockr}
DOCKR_HOSTS_DIR="$DOCKR_STATE_DIR/hosts"
DOCKR_LOGS_DIR="$DOCKR_STATE_DIR/logs"
DOCKR_ROUTES_DIR="$DOCKR_STATE_DIR/routes"
DOCKR_BACKUPS_DIR="$DOCKR_STATE_DIR/backups"

ensure_state_tree() {
  ensure_directory "$DOCKR_STATE_DIR" 700 root root
  ensure_directory "$DOCKR_HOSTS_DIR" 700 root root
  ensure_directory "$DOCKR_LOGS_DIR" 700 root root
  ensure_directory "$DOCKR_ROUTES_DIR" 700 root root
  ensure_directory "$DOCKR_BACKUPS_DIR" 700 root root
}

host_profile_path() {
  local host="$1"
  printf '%s/%s.yml\n' "$DOCKR_HOSTS_DIR" "$host"
}

save_host_profile() {
  local host="$1" addr="$2" domain="$3" email="$4" remote_api="$5" features="$6"
  ensure_state_tree
  local path
  path=$(host_profile_path "$host")
  local yaml
  yaml=$(cat <<YAML
name: "$host"
address: "$addr"
domain: "$domain"
email: "$email"
remote_api: $remote_api
features:
$(printf '%s' "$features")
YAML
)
  ensure_file_contents "$path" "$yaml" 600 root root
}

load_host_profile() {
  local host="$1"
  local path
  path=$(host_profile_path "$host")
  if [[ ! -f "$path" ]]; then
    log_fatal "Host profile '$host' not found (expected $path)"
  fi
  cat "$path"
}

host_profile_get() {
  local host="$1" key="$2"
  local path
  path=$(host_profile_path "$host")
  if [[ ! -f "$path" ]]; then
    log_fatal "Host profile '$host' not found"
  fi
  python3 - <<PY
import sys
try:
    import yaml
except ImportError:
    sys.stderr.write("python3-yaml is required to parse host profiles\n")
    sys.exit(1)

with open("$path", "r", encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

value = data
for part in "$key".split('.'):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if value is None:
    sys.exit(0)

if isinstance(value, (list, tuple)):
    for item in value:
        print(item)
elif isinstance(value, bool):
    print(str(value).lower())
else:
    print(value)
PY
}
