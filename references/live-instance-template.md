# Live-Instance Note Template

Save to **`/memories/repo/<project>-live-instance.md`** (REPO memory, not session — it must survive across audits of the same target).

This file is read by:
- The orchestrator at the start of audit / fpcheck / report phases (to know what's deployed)
- Every verify fork (to know endpoints, config files, restart commands)
- Future audits of the same project (to skip the deploy phase)

---

## Template (copy and fill)

```markdown
# <Project> — Live Test Instance

Workspace: `<absolute-workspace-path>`
Purpose: Audit target for CVE reporting; live instance for verifying findings.

## Stack
- Container/process manager: <Docker Compose | systemd | bare process>
- Compose file / launch command: `<path/to/docker-compose.yml or command>`
- Containers / services:
  - `<service-name>` — built from `<dockerfile-or-image>`
  - `<sidecar>` — `<image>`
- Restart policy: <on-failure | always | none>

## Endpoints (host-side)
- Primary:    http://127.0.0.1:<port>   — <what it serves>
- Admin/API:  http://127.0.0.1:<port>   — <what it serves>
- Metrics:    http://127.0.0.1:<port>   (or "NOT published")
- Tracing UI: http://127.0.0.1:<port>   (or "disabled")

## Config (bind-mounted; edits may hot-reload)
- `<path>/config.yaml` — server config; auto-reload: yes/no
- `<path>/rules.json`  — access rules / routing; auto-reload: yes/no
- `<path>/keys.json`   — secrets / JWKS; sensitive

## Changes made to get it running (vs upstream repo)
1. `<file>`: <change> — <why>
2. `<file>`: <change> — <why>
…

(These are required for reproducing the live instance. If a future auditor sees a different repo state, they can use this list to re-derive the working config.)

## Verified working YYYY-MM-DD
- `/health/alive` → 200
- `<known-test-route>` → 200/4xx as expected

## Common ops
```bash
cd <workspace>
docker compose ps                          # or equivalent
docker compose logs -f <service>
docker compose restart <service>           # pick up non-hot-reload config edits
docker compose up -d --build <service>     # rebuild after source changes
docker compose down                        # full stop
```

## Notes for audit
- <e.g., default credentials / sample tokens for PoC>
- <e.g., anonymous-allowed test routes>
- <e.g., a mutator/auth path that uses local secrets — easier to test forgery>
- <e.g., warning: this instance proxies to `httpbin.org` — replace if testing offline>

## Hand-edit log (timestamps)
- YYYY-MM-DD HH:MM — <user/tool> edited `<file>` to add `<rule/feature>` for testing `<finding-id>`
- YYYY-MM-DD HH:MM — restored to baseline

(Useful for verify forks to know if config drifted since deploy.)
```

---

## Rules for the live-instance note

1. **Repo memory only.** Session memory dies; repo memory survives across audit campaigns of the same target.
2. **Endpoint table is the most-read section.** Make it scannable.
3. **Document every deviation from upstream** — others will fail to reproduce without this list.
4. **Keep secrets OUT** — only placeholder/sample tokens. Real secrets belong in env vars, not memory files.
5. **Update the "Verified working" date** when you re-test reachability.
6. **Append to the hand-edit log** whenever you modify a bind-mounted config — even temporarily — so verify forks know what state they're inheriting.
