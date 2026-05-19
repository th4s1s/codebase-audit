# `/codebase-audit:deploy` — Live Instance Setup

**Purpose**: Make sure a live instance of the audit target is reachable so that later phases (deep audit live-PoC, fpcheck spot-checks, verify forks) have a reproduction target. The instance may be **locally managed** (we bring it up via Docker / make / ad-hoc command) or **externally provided** (already running — e.g. on a staging server, remote VM, customer-hosted environment). Either way, produce a single repo-memory artifact so subagents and forks can find it.

**Entry**: Recon complete (or invoked independently to set up a target).
**Exit**: Live instance reachable, endpoints documented in `/memories/repo/<project>-live-instance.md`, user gate before audit.

---

## Step 0 — Pick the deployment mode

Before touching anything, decide which mode applies. Ask the user explicitly if it isn't obvious:

| Mode | When to use | What we control | Capabilities for verify forks |
|---|---|---|---|
| **`local-managed`** | No instance exists yet; user wants us to bring one up from the repo | Lifecycle, config files, restart, bind mounts | Full — can back up / edit / restart |
| **`external-provided`** | Instance is already running somewhere we don't own (staging, customer VM, remote host) | Only HTTP-reachable surface | Read-only at the HTTP layer; **no config edits, no restart** |

If a `/memories/repo/<project>-live-instance.md` already exists, read it first — it tells you the mode and target. If the documented instance is still reachable (probe per Step 3), skip directly to Step 5.

For **`external-provided`**, collect from the user (do not assume defaults):

- **Base URL(s)** (e.g. `https://audit.example.com`, `http://10.0.5.12:8080`) — one per logical endpoint (proxy, admin/API, metrics, etc.)
- **Auth material** the auditor may use (test accounts, sample tokens, header overrides) — placeholder/sample only, never real production secrets
- **What's off-limits** — paths/methods the operator does not want hit (e.g. write endpoints, admin destructive routes)
- **Liveness check command** the operator considers authoritative (might be just `curl -f <base-url>/health`, might be something else — do not assume `/health` or `127.0.0.1`)
- **Restart/redeploy contact** — who to ping if the instance goes down (so we never assume `docker compose restart` works)

For **`local-managed`**, proceed to Step 1.

## Step 1 — (local-managed only) Detect existing deploy assets

Search the workspace in parallel for:

- `Dockerfile`, `docker-compose.yml`, `compose.yaml`, `.docker/` directory
- `Makefile` targets (`make run`, `make serve`, `make dev`)
- `install.sh`, `bootstrap.sh`, `quickstart.sh`
- `package.json` scripts (`npm start`, `pnpm dev`)
- Language-specific runners (`go run`, `cargo run`, `python -m`, `mvn spring-boot:run`)
- Sample config dirs (`.docker_compose/`, `examples/`, `quickstart/`, `dev/`)

Pick the **highest-fidelity** option that produces a network-reachable instance similar to a production deployment. Order of preference:

1. Project-provided docker-compose with sample config (production-like, hermetic)
2. Single Dockerfile + ad-hoc command (still hermetic)
3. `make run` / `npm start` / similar (less hermetic but standard)
4. Manual build + run (last resort)

## Step 2 — Attempt deploy and capture failures

Run the chosen deploy command via `execution_subagent` (so output is filtered and the orchestrator context stays small). Common failure classes:

- **Missing Dockerfile referenced by compose** → check `.dockerignore` / `.docker/` dirs for the real file name; edit the compose file to point at it.
- **Schema validation failures on empty env vars** → identify the offending block, remove or fill it.
- **Port already bound** → check `docker compose ps` / `lsof -i`; choose a free port.
- **Missing build dependencies** → install via apt/brew/pip; pin versions if reproducibility matters.

For each non-trivial change to project files (e.g., editing `docker-compose.yml`), **record what you changed and why** — this goes into the live-instance note so the audit team can reproduce.

## Step 3 — Verify reachability

Probe every documented endpoint using the **base URL recorded for this instance** (do NOT hardcode `127.0.0.1` — it may be a remote host, a hostname, or HTTPS):

```bash
curl -sS -o /dev/null -w "%{http_code} %{url_effective}\n" \
  <base-url>/<liveness-path> \
  <base-url>/<known-endpoint>
```

Use the **operator-supplied liveness command** for `external-provided` mode if one was given — do not invent a `/health` path that may not exist.

Confirm expected status codes for at least one auth-required and one anonymous endpoint. For `local-managed` mode you can additionally use container introspection (`docker compose ps`, `lsof -i`, etc.); for `external-provided` mode HTTP probes are the only signal available.

## Step 4 — Write the live-instance repo memory note

Use [../references/live-instance-template.md](../references/live-instance-template.md). Save to **`/memories/repo/<project>-live-instance.md`** (NOT session — must survive across audits).

Required sections (mark sections N/A rather than deleting them if the mode doesn't apply):

- **Deployment mode**: `local-managed` or `external-provided` (most-read field — forks branch behavior on it)
- **Capabilities**: can-back-up-config / can-edit-config / can-restart-service / can-tail-logs (yes/no each)
- Workspace path (local-managed) OR operator contact (external-provided)
- Purpose (this is the audit target)
- Stack (compose file location, service names, restart policies) — N/A for external-provided
- **All endpoints as full base URLs and what they serve** — proxy, admin/API, metrics, tracing UI, etc. Do not assume `127.0.0.1`; use whatever scheme/host/port the instance actually exposes.
- **Liveness check command** (exact command verify forks should run to confirm the instance is up)
- Bind-mounted config files (local-managed only — list what testers may edit / restore)
- **Changes made vs upstream** (local-managed only — for reproducibility)
- **Off-limits surface** (external-provided — paths/methods the operator forbids hitting)
- "Verified working YYYY-MM-DD" with a quick-check command result
- Common ops (start, stop, rebuild, restart, logs) — local-managed only
- Audit-specific notes (default credentials, sample tokens, anonymous-allowed test routes)

## Step 5 — Update the resume note

Add a "Live instance" reference line pointing at the repo-memory note. Mark deploy DONE.

## Step 6 — USER GATE

Present:

> Live instance is reachable: <mode> at <base-url(s)>. Live-instance note saved to repo memory.
>
> Capabilities for verify forks: backup=<y/n>, edit-config=<y/n>, restart=<y/n>, logs=<y/n>.
>
> Next: `/codebase-audit:audit` to ingest prior CVEs and run parallel deep audits.
>
> Say **go audit** to proceed.

If mode is `external-provided`, explicitly call out in the gate message that any finding requiring config changes, service restart, or filesystem access will be marked INCONCLUSIVE by verify forks unless the operator coordinates the change out-of-band.

## Quality Checks

- [ ] All claimed endpoints actually respond (curl spot-check passes)
- [ ] Live-instance note exists in **repo memory**, not session memory
- [ ] Note documents every file edit made (and why) so the deploy is reproducible
- [ ] Bind-mounted config files are listed (later verify forks need to know what to back up before PoC)
- [ ] Restart command is documented (verify forks will use it)

## Common Pitfalls

- **`local-managed`: don't deploy to a public host or shared port.** Default to `127.0.0.1`.
- **`external-provided`: never assume the instance is local.** Don't substitute `127.0.0.1` for a remote host in any probe, PoC, or backup command — the loopback probe will appear to succeed against an unrelated service on your own machine and silently invalidate the entire phase.
- **`external-provided`: never run lifecycle commands.** No `docker compose ...`, no `systemctl restart`, no kill/send-signal. If a finding needs a restart, mark INCONCLUSIVE and document the required operator action.
- **Don't invent liveness paths.** `/health` may 404 or may be a sensitive admin path. Use the operator-supplied liveness command verbatim (`external-provided`) or the one documented by the project (`local-managed`).
- **Don't enable destructive admin features.** Keep test fixtures minimal.
- **Don't bake real secrets into the instance.** Use placeholder/sample credentials so PoCs can be shared.
- **Tracing/metrics ports often fail startup if the provider env var is empty** (`local-managed`) — explicitly remove or set the variable rather than leaving it blank.
