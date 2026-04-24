# Copilot Instructions for Dell iDRAC Fan Controller Docker

## Project Snapshot
- This repository runs a Bash-based fan controller inside Docker for Dell PowerEdge servers.
- The runtime loop reads temperatures via `ipmitool` and switches fan profiles based on thresholds.
- Safety behavior is the priority: if temperatures are too high, switch back to Dell dynamic fan control.
- On container exit, the script restores safe defaults through a graceful shutdown path.

## Key Files and Responsibilities
- `Dell_iDRAC_fan_controller.sh`: startup flow, trap setup, temperature loop, profile switching.
- `functions.sh`: all reusable logic, IPMI raw commands, parsing, conversion helpers, and safety exits.
- `constants.sh`: shared constants.
- `healthcheck.sh`: container liveness command using `ipmitool`.
- `Dockerfile`: runtime dependency install, default environment variables, and healthcheck config.
- `README.md`: user-facing setup, parameters, troubleshooting, and local testing examples.
- `.github/workflows/build_and_publish_docker_image.yml`: release-tag build and publish workflow.
- `.github/workflows/docker-publish.yml`: CI workflow for build/publish/sign flow.

## Runtime Model
- Local mode: `IDRAC_HOST=local` and mapped IPMI device (`/dev/ipmi0` or compatible path).
- LAN mode: `IDRAC_HOST=<ip>` with `IDRAC_USERNAME` and `IDRAC_PASSWORD`.
- `FAN_SPEED` can be decimal or hex and is normalized at startup.
- CPU threshold checks decide whether user profile or Dell default profile is active.

## Light Guardrails for Edits
- Keep hardware-facing behavior changes small and easy to review.
- Put IPMI command changes in `functions.sh`, not scattered across files.
- Keep trap-driven graceful shutdown intact.
- Keep overheating fallback behavior intact.
- If you add environment variables, update both `Dockerfile` defaults and `README.md` docs.
- Avoid enabling global strict mode (`set -euo pipefail`) unless fully tested on this project.

## Quick Validation After Changes
1. Build image locally.

   ```bash
   docker build -t ghcr.io/mevljas/dell_idrac_fan_controller_docker:dev .
   ```

2. Start a test container with realistic environment variables.
3. Confirm logs still show expected startup context (server model, target fan speed, threshold, interval).
4. Verify health check path still works.

   ```bash
   docker exec <container_name> /app/healthcheck.sh
   ```

5. For workflow edits, double-check trigger patterns, image names, and tag behavior.

## Reusable Prompt Starters
- Add a new environment variable with default and validation, then update docs and examples.
- Improve temperature parsing resilience while preserving current safety behavior.
- Refactor log formatting only, without changing fan-control decisions.
- Review fan profile switching logic for edge cases and propose minimal safe fixes.
- Update release workflow tag behavior and explain impact on GHCR publishing.

## Definition of Done for Typical PRs
- Change is minimal and localized.
- Safety behavior remains unchanged unless intentionally updated and documented.
- README and defaults stay in sync.
- Local build and basic runtime sanity checks were performed.