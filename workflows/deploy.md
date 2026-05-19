# `/codebase-audit:deploy` — Live Instance Deployment

**Purpose**: Bring up a local live instance of the audit target so that later phases (deep audit live-PoC, fpcheck spot-checks, verify forks) have a reproduction target. Document the deployment in **repo memory** so it survives across sessions.

**Entry**: Recon complete (or invoked independently to set up a target).
**Exit**: Live instance running, endpoints documented in `/memories/repo/<project>-live-instance.md`, user gate before audit.

---

## Step 1 — Detect existing deploy assets

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

Probe every documented endpoint:

```bash
curl -sS -o /dev/null -w "%{http_code} %{url_effective}\n" \
  http://127.0.0.1:<port>/health \
  http://127.0.0.1:<port>/<known-endpoint>
```

Confirm expected status codes for at least one auth-required and one anonymous endpoint.

## Step 4 — Write the live-instance repo memory note

Use [../references/live-instance-template.md](../references/live-instance-template.md). Save to **`/memories/repo/<project>-live-instance.md`** (NOT session — must survive across audits).

Required sections:

- Workspace path
- Purpose (this is the audit target)
- Stack (compose file location, container/service names, restart policies)
- **All endpoints with host:port and what they serve** — proxy, admin/API, metrics, tracing UI, etc.
- Bind-mounted config files (so testers know what to edit / restore)
- **Changes made vs upstream** (and the reasoning) — so this is reproducible
- "Verified working YYYY-MM-DD" with a quick-check command result
- Common ops (start, stop, rebuild, restart, logs)
- Audit-specific notes (default credentials, test routes, sample tokens)

## Step 5 — Update the resume note

Add a "Live instance" reference line pointing at the repo-memory note. Mark deploy DONE.

## Step 6 — USER GATE

Present:

> Live instance is up: <list endpoints>. Live-instance note saved to repo memory.
>
> Next: `/codebase-audit:audit` to ingest prior CVEs and run parallel deep audits.
>
> Say **go audit** to proceed.

## Quality Checks

- [ ] All claimed endpoints actually respond (curl spot-check passes)
- [ ] Live-instance note exists in **repo memory**, not session memory
- [ ] Note documents every file edit made (and why) so the deploy is reproducible
- [ ] Bind-mounted config files are listed (later verify forks need to know what to back up before PoC)
- [ ] Restart command is documented (verify forks will use it)

## Common Pitfalls

- **Don't deploy to a public host or shared port.** Always 127.0.0.1.
- **Don't enable destructive admin features.** Keep test fixtures minimal.
- **Don't bake real secrets into the instance.** Use placeholder/sample credentials so PoCs can be shared.
- **Tracing/metrics ports often fail startup if the provider env var is empty** — explicitly remove or set the variable rather than leaving it blank.
