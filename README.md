# dockr CLI

`dockr` is a modular Bash toolkit for provisioning secure Docker hosts on Ubuntu, managing TLS certificates, installing Traefik, orchestrating Traefik routes, and wrapping docker-compose deployments. The CLI follows the architecture described in `SPEC.md` and aims to be dependency-light while remaining automation-friendly for CI/CD pipelines.

## 1. Prerequisites

- Ubuntu 20.04 LTS or newer with `systemd` and network access to Docker/ACME repositories.
- Root or sudo privileges when running `dockr` (certificate generation, firewall rules, and system services require it).
- `jq` and other base packages are installed automatically by `dockr init`, but on a development workstation you may also want `shellcheck` for linting.

## 2. Installation

Clone the repository onto the target host (or bundle it via configuration management) and add `bin/` to your `PATH`:

```bash
git clone https://example.com/dockr.git
cd dockr
sudo install -m 755 bin/dockr /usr/local/bin/dockr
```

You can also execute from the repo directly using `sudo ./bin/dockr ...`.

## 3. Getting Started

1. **Bootstrap a host**
   ```bash
   sudo dockr init \
     --host prod01 \
     --addr 203.0.113.10 \
     --domain example.com \
     --email ops@example.com \
     --with-traefik
   ```
   This installs Docker (remote API on TCP/2376 with TLS), configures UFW, generates certificates, and persists a host profile to `~/.dockr/hosts/prod01.yml`.

2. **Install Traefik**
   ```bash
   sudo dockr traefik install --host prod01 --dashboard-user admin --dashboard-password changeme
   ```
   Traefik configuration and ACME storage are written under `/opt/traefik`.

3. **Define routes**
   ```bash
   sudo dockr route add \
     --host prod01 \
     --name app \
     --rule "Host(`app.example.com`)" \
     --service app \
     --service-url http://app:8080
   ```
   Route definitions live at `~/.dockr/routes/prod01.yml` and are consumed by Traefik's file provider.

4. **Deploy a compose stack**
   ```bash
   sudo dockr deploy up --compose-file deploy/docker-compose.yml --project prod01 --pull
   ```
   Wraps `docker compose` with consistent flags and project naming suitable for CI.

5. **Check health**
   ```bash
   dockr health
   dockr health --json
   ```
   Displays Docker service status, UFW state, Traefik stack status, and TLS expiry.

## 4. Host Profiles & State

`dockr init` maintains state under `~/.dockr/` (configurable via `DOCKR_STATE_DIR`). Important paths:
- `hosts/<name>.yml` — persisted data: address, domain, email, enabled features.
- `routes/<name>.yml` — Traefik file-provider configuration for the host.
- `logs/` — room for future per-run logs.
- `backups/` — archives created by `dockr cert docker backup`.
- `/root/docker-certs/` — Docker TLS bundle (CA, server, client certs/keys).

Use `dockr cert docker info/rotate/backup` to inspect or manage TLS assets; these commands read profile defaults when `--host` is provided.

## 5. Command Reference

### `dockr init`
Bootstrap an Ubuntu host with Docker, TLS, firewall rules, and optional extras.

Key flags:
- `--host <name>` *(required)* — logical host identifier used for profiles.
- `--addr <ip>` — primary IP for SANs; defaults to first non-loopback address.
- `--domain <fqdn>` / `--email <address>` — populate host profile and Traefik defaults.
- `--remote-port <port>` — Docker TLS port (default 2376). `--no-remote-api` disables TCP listener.
- `--sshkeymgr` — install Hetzner `sshkeymgr` helper and cron job.
- `--with-traefik` — mark host with Traefik feature (install separately via `dockr traefik install`).
- `--tls-days <n>` — certificate validity window (default 365).
- `--dry-run` — log actions without executing (best-effort).

### `dockr cert docker`
Manage Docker TLS lifecycle.
- `info` — display subject, issuer, validity, fingerprint of server certificate.
- `rotate` — regenerate server/client certs while preserving the CA; restarts Docker.
  - Supports `--host`, `--addr`, `--domain`, `--client-name`, `--days` overrides.
- `backup` — archive `/root/docker-certs` into `~/.dockr/backups/docker-certs-<timestamp>.tar.gz`.

### `dockr traefik`
Install or manage Traefik reverse proxy assets under `/opt/traefik`.
- `install` — render static/dynamic configs, configure ACME, optional dashboard basic auth, create Docker network `traefik_proxy`, and run `docker compose up -d`.
  - Flags: `--host`, `--email`, `--staging`, `--image`, `--dashboard-user`, `--dashboard-password`.
- `status` — run `docker compose ps` for the Traefik stack.
- `remove` — `docker compose down` without deleting configs.

### `dockr route`
Operate on Traefik file-provider YAML.
- `list` — tabular output of routers/rules/services.
- `add` — create router/service entries (defaults to `entryPoints: websecure`).
- `remove` — delete router and associated service.
- `edit` — open route file in `$EDITOR` (defaults to `nano`).

### `dockr deploy`
Wrapper around `docker compose` for consistent deployments.
- `up` — `docker compose up -d`; supports `--pull`, `--remove-orphans`, `--project`, `--compose-file`.
- `down` — `docker compose down` with same targeting options.

### `dockr health`
Print summary of Docker, UFW, Traefik status, and Docker TLS expiry. With `--json`, emits machine-readable output (useful in CI).

## 6. CI/CD Integration

`templates/gitlab-ci.yml` demonstrates how to materialize TLS certificates from CI variables, authenticate to your registry, and deploy via docker-compose. To adopt `dockr` in GitLab:
1. Add a deploy job stage pulling the repo (or vendored artifact).
2. Materialize TLS certs under `$DOCKER_CERT_PATH` as shown.
3. Run `dockr health --json` to fail fast if the host is unhealthy.
4. Use `dockr deploy up --compose-file deploy/docker-compose.yml --project $CI_ENVIRONMENT_SLUG --pull`.
5. Optionally export route files and apply them with `dockr route` commands or manage via Git.

Use `templates/github-actions.yml` as a starting point for GitHub Actions. It checks out the repo, installs prerequisites, materializes TLS certificates from secrets, runs a health check, and triggers `dockr deploy up`.

For GitHub Actions, follow that pattern with `sudo` within the runner and secrets for PEM content.

## 7. Development & Testing

- Run `shellcheck` across the codebase: `shellcheck bin/dockr lib/*.sh commands/*.sh`.
- Static analysis: `bash -n` on scripts to catch syntax errors.
- Manual verification: execute `dockr init` twice on the same host to confirm idempotency, validate Traefik routes, and inspect TLS expiry dates before/after rotation.
- Add integration or unit tests as you expand functionality; `bats` or Python-based harnesses are good options when mocking system calls.

## 8. Troubleshooting

- **Docker daemon fails to restart**: Check `/var/log/syslog` and `/etc/docker/daemon.json` for JSON syntax. `dockr` validates via `jq` when available.
- **Traefik ACME issues**: Inspect `/opt/traefik/log` and `docker logs traefik`. Verify DNS records and that ports 80/443 are reachable.
- **UFW blocks remote API**: Ensure `dockr init` ran with remote API enabled or manually run `ufw allow 2376/tcp`.
- **Certificates not trusted in CI**: Download `~/.dockr/backups` archive or use `docker cert docker rotate --client-name ci` to generate dedicated client bundles.

## 9. Contributing

Review `AGENTS.md` for contributor guidelines, coding style, and pull request expectations. Always update `SPEC.md` when new modules or behaviours diverge from the architecture plan.
