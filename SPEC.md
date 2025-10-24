# Implementation Specification for “dockr” - a CLI Suite for Managing Docker Hosts on Ubuntu

## Goals

- Provide a single, pleasant, dependency-light CLI (“dockr”) to:
- Bootstrap a secure Ubuntu Docker host with TLS and sane defaults.
- Configure UFW firewall.
- Install & configure Traefik as reverse proxy. (optional)
- Provision Let’s Encrypt certificates (via Traefik/ACME - optinal).
- Manage Traefik routes for many containers (list/add/edit/remove).
- Rotate/renew Docker TLS certs safely.
- Offer interactive UX and full non-interactive flags.
- Deliver best-practice example + CI/CD recipes for GitLab CI (based on the user’s provided pipeline) and GitHub Actions.

Non-goals:
- building images beyond standard docker buildx; 
- external dependencies (prefer pure Bash + standard Ubuntu packages;

## High-Level Architecture

- Language: Bash (POSIX where possible). Optional Python module for rich prompts/JSON edits if complexity requires it.
- Binary name: dockr (single entrypoint script).
- Structure:
  - dockr (dispatcher): subcommands + help.
  - lib/ shell functions (idempotent tasks, logging, color).
  - providers/traefik/ templates (static & dynamic config).
  - etc/ defaults (daemon.json template, UFW profile, ACME email prompt).
  - state/ per-host config under ~/.dockr/hosts/<host>.yaml (YAML or .env).
  - logs/ per-run logs under ~/.dockr/logs/.
- State & Config:
  - Host profiles (name, address, ssh_user, domain, email, acme_staging, docker_tls, ports, features).
  - Route specs kept as YAML (Traefik file provider) so they are easy to diff and edit.
  - Secrets via environment (masked in CI) or ~/.dockr/secrets.d/.

## UX & CLI Design

- Interactive mode: guided prompts, validation, confirmation gates, readable summaries. Use tput for color and simple spinners; avoid external UIs. If Python is allowed, optionally provide a curses editor for route YAML (fallback to $EDITOR).
- Non-interactive: every prompt has a flag; supports `--yes` and `--dry-run`.
- Common flags: `--host <name>`, `--addr <ip|fqdn>`, `--domain <fqdn>`, `--email <acme-email>`, `--no-color`, `--json`, `--verbose`, `--quiet`, `--sudo`.
- Output: human-friendly by default; `--json` returns machine-readable results (for CI).
- Safety: idempotent commands; explicit `--force` required to overwrite certs/ACME storage.

3.1 Subcommands (spec)

```
dockr init                   # Bootstrap Ubuntu host + Docker + TLS + UFW
dockr firewall …             # UFW rules (list/apply/open/close)
dockr traefik install …      # Install/upgrade Traefik stack
dockr traefik status         # Show Traefik, ACME, dashboard URL
dockr cert docker rotate     # Rotate Docker daemon/client TLS certs
dockr cert acme info         # Show ACME status (domains, expiry)
dockr route list             # List routes (routers/services/middlewares)
dockr route add              # Add a route (host/path/service/port)
dockr route edit             # Edit route (interactive or --file/--set key=val)
dockr route remove           # Remove route by name
dockr deploy up              # Compose up a stack with Traefik labels or file provider
dockr deploy down            # Compose down (with --remove-orphans)
dockr health                 # Quick checks (ports, certs, DNS, ACME)
dockr backup                 # Backup acme.json, traefik, TLS, compose dirs
dockr uninstall              # Optional teardown (prompted)
```

## Feature Specifications

### dockr init (Ubuntu host bootstrap)

- Assumptions: Ubuntu 20.04+/22.04+, root/sudo SSH access, DNS A record for a domain in case a proxy is required.
- Steps (idempotent):
  * System prep: apt update/upgrade; install ca-certificates gnupg curl ufw jq (avoid jq if possible; Python fallback if JSON needed).
  * Docker engine: install via Docker’s official repo (not docker.io), enable docker & containerd services, install Compose plugin.
  * Docker TLS: generate CA, server cert (CN=host addr, SANs include IP and FQDN), client cert; write daemon.json enabling tlscacert/tlscert/tlskey, listen on 2376 (optional flag `--remote-api`), restart docker.
  * User: create deploy user (optional), add to docker group; copy client certs to a safe location.
  * UFW: default deny incoming; allow 22/tcp, 80/tcp, 443/tcp, optional 2376/tcp if `--remote-api`; enable + log.
  * Hardening (optional flags): fail2ban, unattended-upgrades, SSH PasswordAuthentication no, PermitRootLogin prohibit-password.
  * Host profile: persisted under `~/.dockr/hosts/<name>.yaml`.
- Flags: `--name`, `--addr`, `--domain`, `--email`, `--remote-api`, `--no-remote-api`, `--acme-staging`, `--skip-hardening`.


### dockr firewall

- list: render current UFW rules with friendly names.
- apply: reconcile desired ruleset → UFW (transactional: compute diff, prompt).
- open/close: open/close port(s)/services (http, https, docker-tls, custom).
- audit: quick checks for shadowed or duplicate rules.

### dockr traefik install

- Runtime: Docker stack with persistent volumes: /var/lib/traefik (contains acme.json with 600 perms).
- Static config:
- Entrypoints web:80, websecure:443, docker provider optional (labels), file provider enabled for managed routes.
- Dashboard on :8080 with basic auth or IP allowlist.
- ACME (Let’s Encrypt):
- HTTP-01 on web → websecure; email from `--email`; acme.json persisted; `--acme-staging` flag.
- DNS-01 optional provider integration (flagged; user supplies creds via environment/secrets).
- Network: create traefik Docker network; managed apps attach to it.
- Output: dashboard URL, certificate status, next renewal.

### Traefik Route Management (dockr route …)

- Model: Managed via file provider YAML in ~/.dockr/hosts/<name>/routes/*.yaml (live-reloaded by Traefik).
- Create (add):
- Inputs: `--name`, `--rule 'Host(app.example.com)[ && PathPrefix(/api)]`, `--service-url http://container:PORT,` optional middlewares:
  - redirect-https
  - strip-prefix
  - rate-limit
  - headers (HSTS)
  - basic-auth
- Creates router, service, and any middlewares as needed; writes YAML; triggers reload.
- Edit:
- Interactive form (or --set key=value or --file <path.yaml>); validity checks.
- List / Remove:
- Present routers/services/middlewares with status (healthy/unhealthy) and TLS info.

### Docker TLS Certificate Rotation (dockr cert docker rotate)

- Process: generate new server/client certs (preserving CA or rotating CA if --rotate-ca), atomically swap, restart Docker, verify 2376 reachable, archive old certs with timestamp.
- Outputs: new bundle for CI (PEM strings), expiry dates, SANs.

### dockr deploy

- up: docker compose up -d --remove-orphans on a specified compose file/path; ensures network traefik attached.
- down: stop and optionally prune.
- Flags: --compose-file, --project-name, --env-file, --pull=always, --quiet-pull.

### Health, Backup, Uninstall

- health: DNS resolution, open ports (80/443/2376), ACME expiry, Traefik container state, Docker info.
- backup: tar/gzip acme.json, TLS dir, route YAMLs, Traefik static/dynamic config, optional compose dirs.
- uninstall: reversible teardown with confirmations; never deletes backups unless --purge.

## Security & Compliance Defaults

- Docker API TLS-only on 2376 (if enabled), verify-client certs, TLS v1.2+.
- UFW default deny; only SSH/HTTP/HTTPS (and 2376 if explicitly enabled).
- Traefik dashboard protected (basic auth + allowlist).
- ACME storage 600 perms.
- Secrets never echoed; redact on logs; --json omits secrets.

## Best-Practice Example (Reference Scenario)

- Goal: Host example.com with Traefik; deploy whoami service on whoami.example.com.
- Steps (operator):
  1.  dockr init --name prod --addr 203.0.113.10 --domain example.com --email ops@example.com --remote-api
  2.  dockr traefik install --host prod
  3.  dockr route add --host prod --name whoami --rule 'Host(whoami.example.com)' --service-url http://whoami:80 --headers hsts --redirect-https
  4.  dockr deploy up --host prod --compose-file ./compose.yaml
  5.  dockr health --host prod (confirm ACME issued for whoami.example.com)

Compose best practices (for the app):
- Attach to traefik network.
- Avoid exposing container ports on the host; let Traefik handle ingress.
- Use healthchecks; set resource limits; add Traefik labels only if you opt to manage via labels instead of file-provider.

## CI/CD Integration

### GitLab CI (based on provided pipeline)

- The provided pipeline builds images, pushes to registry, then deploys via docker-compose over a TLS-secured remote Docker host using CA/client certs injected as variables.  ￼
- Adaptation to dockr:
- Keep build jobs largely unchanged.
- Replace raw docker-compose deployment with dockr deploy up and dockr route … where desired.
- Continue to pass Docker TLS certs as masked variables (CA_PEM, CERT_PEM, KEY_PEM) and set:
- DOCKER_TLS_VERIFY=1
- DOCKER_HOST=tcp://<HOST>:2376
- DOCKER_CERT_PATH=/tmp/docker-certs/$CI_PIPELINE_IID (create and clean up)
- Optionally, use docker context create tls inside the job for clarity.

Suggested GitLab job sketch (deploy):
- Image: docker:26-cli (or similar) + curl (to fetch dockr) or add dockr to repo.
- Steps:
  1.  Materialize certs to $DOCKER_CERT_PATH.
  2.  dockr health --json (fail fast if host unhealthy).
  3.  dockr deploy up --compose-file deploy/docker-compose.yml --project-name $CI_COMMIT_REF_SLUG --pull=always --quiet-pull.
  4.  Optionally, dockr route list or dockr route apply --file ci/routes.yaml.

If you maintain the existing job design (re-creating certs under /tmp, login, compose up, prune), it remains compatible; simply substitute the compose calls with dockr equivalents and keep the cleanup pattern.  ￼

Variables & Protections:
- Protect variables for production (mask CA_PEM, CERT_PEM, KEY_PEM).
- Use environment-scoped variables per environment (stage/prod).
- Tag runners with docker.

### GitHub Actions (alternative)

- Workflow outline:
- on: [push] filtered to main/develop.
- Jobs:
- build: docker/setup-buildx-action, docker/login-action, docker/build-push-action targeting ${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }} and branch tags.
- deploy:
- Secrets: CA_PEM, CERT_PEM, KEY_PEM, DOCKER_HOST.
- Create $RUNNER_TEMP/certs and write PEMs.
- echo "DOCKER_TLS_VERIFY=1" >> $GITHUB_ENV
- echo "DOCKER_CERT_PATH=$RUNNER_TEMP/certs" >> $GITHUB_ENV
- Run dockr health --host <name> || exit 1
- Run dockr deploy up --compose-file deploy/docker-compose.yml --pull=always.
- Optional: dockr route apply --file .github/routes.yaml.
- Use actions/upload-artifact for logs (~/.dockr/logs).

## Telemetry, Observability, and Ops (Suggestions)

- Optional dockr observe install to deploy:
- cAdvisor + node-exporter on a private port; expose via Traefik with auth if needed.
- Watchtower for controlled image refresh (off by default; use manual deploys in CI for predictability).
- Log collection hints (e.g., docker logs tailing helpers).

## Error Handling & Idempotency

- Each task validates preconditions and prints a plan before applying.
- Non-zero exit codes on failure; --json outputs structured errors (code, message, hint).
- Network/ACME retries with backoff; clear guidance on DNS/HTTP-01 pitfalls.

## Uninstall / Recovery

- dockr uninstall removes Traefik stack, routes, UFW openings (except SSH), and optionally Docker TLS (with --purge).
- dockr cert docker rollback --ts <timestamp> restores previous cert bundle.
- Restore from dockr backup tarball.

## Deliverables

- dockr Bash script + lib/*.sh.
- Templates:
- providers/traefik/traefik.yml (static)
- providers/traefik/dynamic/*.yml (example routes)
- etc/daemon.json, etc/ufw-profile, etc/dashboard-auth
- Docs:
- README.md (quickstart + interactive and flags)
- docs/routes.md (route schema keys and examples)
- docs/ci-gitlab.md, docs/ci-github.md
- docs/security.md (TLS/ACME, renewals, rotations)

## Route Schema (file-provider YAML) — Keys

- router.name (unique), router.rule (Traefik rule), router.entrypoints (websecure), router.tls (true).
- service.loadBalancer.servers[0].url (http://container:port).
- middlewares: headers (HSTS, XFO, etc.), redirectscheme (http→https), stripprefix, ratelimit.
- certresolver: letsencrypt.

## Acceptance Criteria

- Running dockr init … on a fresh Ubuntu host results in:
- Docker installed; TLS remote API optionally enabled.
- UFW active with only 22/80/443 open (2376 only if requested).
- Traefik running, dashboard protected, ACME ready.
- dockr route add creates a live route within seconds (Traefik reload).
- dockr cert docker rotate replaces TLS certs with <30s impact and prints new expiry/SANs.
- CI examples function with only variables/secrets configured.

## Open Questions (answer inline or ignore and proceed with defaults)

- Preferred ACME challenge: strictly HTTP-01, or support DNS-01 providers out-of-the-box?
- Keep Docker’s remote API enabled by default or require --remote-api opt-in?
- Are we allowed to rely on jq for JSON, or should we prefer a tiny Python helper?
- Do you want the Traefik dashboard exposed behind basic auth, IP allowlist, or both by default?