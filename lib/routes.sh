#!/usr/bin/env bash

routes_file() {
  local host="$1"
  ensure_state_tree
  printf '%s/%s.yml\n' "$DOCKR_ROUTES_DIR" "$host"
}

ensure_routes_file() {
  local host="$1" file
  file=$(routes_file "$host")
  if [[ ! -f "$file" ]]; then
    cat <<'YAML' >"$file"
http:
  routers: {}
  services: {}
  middlewares: {}
YAML
    chmod 600 "$file"
  fi
  printf '%s\n' "$file"
}

routes_list() {
  local host="$1" file
  file=$(ensure_routes_file "$host")
  python3 - <<PY
import yaml, sys
with open('$file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
http = data.get('http', {})
routers = http.get('routers', {})
if not routers:
    print('No routes defined')
    sys.exit(0)
print(f"{'NAME':20} {'RULE':40} {'SERVICE':20} {'MIDDLEWARES'}")
for name, router in routers.items():
    rule = router.get('rule', '')
    service = router.get('service', '')
    middlewares = ','.join(router.get('middlewares', []) or [])
    print(f"{name:20} {rule:40} {service:20} {middlewares}")
PY
}

routes_add() {
  local host="$1" name="$2" rule="$3" service="$4" service_url="$5" middlewares="$6"
  local file
  file=$(ensure_routes_file "$host")
  python3 - <<PY
import yaml
from pathlib import Path
file = Path('$file')
with file.open('r', encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
http = data.setdefault('http', {})
routers = http.setdefault('routers', {})
services = http.setdefault('services', {})
if '$name' in routers:
    raise SystemExit('Router name already exists: $name')
routers['$name'] = {
    'entryPoints': ['websecure'],
    'rule': '$rule',
    'service': '$service'
}
if '$middlewares':
    routers['$name']['middlewares'] = [m.strip() for m in '$middlewares'.split(',') if m.strip()]
services['$service'] = {
    'loadBalancer': {
        'servers': [{'url': '$service_url'}]
    }
}
with file.open('w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, sort_keys=False)
PY
}

routes_remove() {
  local host="$1" name="$2"
  local file
  file=$(ensure_routes_file "$host")
  python3 - <<PY
import yaml
from pathlib import Path
file = Path('$file')
with file.open('r', encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
http = data.get('http', {})
routers = http.get('routers', {})
services = http.get('services', {})
router = routers.pop('$name', None)
if router is None:
    raise SystemExit('Router not found: $name')
service_name = router.get('service')
if service_name in services:
    services.pop(service_name)
with file.open('w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, sort_keys=False)
PY
}

routes_open_editor() {
  local host="$1" file editor
  file=$(ensure_routes_file "$host")
  editor="${EDITOR:-nano}"
  "$editor" "$file"
}

