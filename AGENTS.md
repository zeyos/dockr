# Repository Guidelines

## Project Structure & Module Organization
- `docker-init.sh` is the current entrypoint for provisioning TLS-enabled Docker hosts and installing Hetzner sshkeymgr. Extend it with discrete functions or a future `lib/` directory to keep the script readable.
- `SPEC.md` captures the target architecture (Traefik integration, state layout, CI touchpoints). Update it when behaviour changes or when directories such as `providers/` or `etc/` appear.
- `gitlab-ci.yml` documents the GitLab stages, registry naming, and certificate materialisation flow. Reuse these variable names and directory shapes when adding new automation.

## Build, Test, and Development Commands
Run with Bash on Ubuntu hosts that provide `systemd` services.
```bash
bash docker-init.sh              # Run the bootstrap flow end-to-end (interactive prompts not yet implemented)
shellcheck docker-init.sh        # Lint for POSIX/Bash compliance before opening a PR
```

## Coding Style & Naming Conventions
- Target POSIX shell where possible, but leverage Bash features already present (functions, `[[ ]]`).
- Indent with four spaces inside functions to match the existing script, keep function names snake_case, and prefer descriptive variable names (`SERVER_CERT`, `DOCKER_TCP_PORT`).
- Source helper files with `.`/`source` relative paths once `lib/` exists, and gate external dependencies (`jq`, `git`) with availability checks as seen in the script.

## Testing Guidelines
- Run `bash -n docker-init.sh` and `shellcheck docker-init.sh` before committing.
- Validate idempotency by running the script twice on the same host; subsequent runs should report "already exists" instead of failing.
- For automated coverage, add Bats tests under `tests/` that mock `systemctl`, `openssl`, and filesystem writes, and capture expected side effects in fixtures.

## Commit & Pull Request Guidelines
- No commit history exists yet, so adopt Conventional Commits (`feat: add traefik installer`, `fix: harden ufw defaults`) to keep the log searchable.
- Reference the relevant SPEC section in your commit or PR description when expanding scope, and call out any deviations explicitly.
- PRs should include: purpose summary, test evidence (commands above or Bats output), manual verification notes, and links to issues or tickets.

## Security & Configuration Tips
- Treat certificate material written to `/root/docker-certs` and `$DOCKER_CERT_PATH` as secrets; never commit them. Use masked CI variables for PEM content as in `gitlab-ci.yml`.
- When adding new commands, require explicit flags (`--yes`, `--force`) before mutating remote hosts, and surface safe defaults (UFW deny, TLS verify true).
- Document default ports and firewall openings in SPEC updates so operators can review changes quickly.
