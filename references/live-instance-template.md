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

## Deployment mode
**Mode:** `local-managed` | `external-provided`

(If `external-provided`: operator contact = `<name / channel>`; auditor MAY NOT run lifecycle commands, edit config files, or restart services. Coordinate out-of-band for those.)

## Capabilities (verify forks must respect these)
| Capability | Available? | Notes |
|---|---|---|
| Back up bind-mounted config files | yes / no | only `local-managed` typically |
| Edit config files in-place | yes / no | only `local-managed` typically |
| Restart service / container | yes / no | only `local-managed` typically |
| Tail server logs | yes / no | may be yes for `external-provided` if operator shares a log stream |
| Filesystem access to the host running the service | yes / no | almost never for `external-provided` |

If a finding requires a capability marked **no**, the verify fork should mark it INCONCLUSIVE and document the required operator action — do NOT attempt to substitute a local workaround that changes the test target.

## Workspace / source
- Workspace path: `<absolute-workspace-path>` (the repo we are auditing)
- Source ref under audit: `<commit-sha or version tag>`

## Stack  *(local-managed only — write "N/A — external" otherwise)*
- Container/process manager: <Docker Compose | systemd | bare process>
- Compose file / launch command: `<path/to/docker-compose.yml or command>`
- Containers / services:
  - `<service-name>` — built from `<dockerfile-or-image>`
  - `<sidecar>` — `<image>`
- Restart policy: <on-failure | always | none>

## Endpoints (use the actual base URL — do NOT hardcode 127.0.0.1)
- Primary:    `<scheme>://<host>:<port>`   — <what it serves>
- Admin/API:  `<scheme>://<host>:<port>`   — <what it serves>
- Metrics:    `<scheme>://<host>:<port>`   (or "NOT published")
- Tracing UI: `<scheme>://<host>:<port>`   (or "disabled")

## Liveness check (verify forks MUST use this command, not invent one)
```bash
<exact command, e.g. curl -fsS https://audit.example.com/api/health>
```
Expected exit code 0 and/or HTTP `<status>`.

## Off-limits surface  *(external-provided — what NOT to hit)*
- <method + path patterns the operator forbids, e.g. "any POST/DELETE under /admin/*">
- <data the operator considers sensitive — exclude from PoCs / logs>

## Credentials inventory  *(external-provided)*

One row per identity the operator has granted. **The secret value itself MUST live in an env var, not in this note** — the note only records the env-var name + how to use it.

| Role / tier | Auth scheme | Header / param | Env var holding secret | Can create accounts? | Can rotate? | Notes |
|---|---|---|---|---|---|---|
| anonymous | none | n/a | n/a | n/a | n/a | baseline |
| tenant-user | bearer | `Authorization: Bearer <token>` | `AUDIT_USER_TOKEN` | no | no | tenant `acme-test` |
| tenant-admin | bearer | `Authorization: Bearer <token>` | `AUDIT_ADMIN_TOKEN` | **yes** — may provision sub-users for permission-boundary testing | no | tenant `acme-test` only |
| service-account | api-key | `X-API-Key: <key>` | `AUDIT_SVC_KEY` | no | yes | scoped to read-only |

If no credentials were supplied, write a single row "**none — anonymous-only audit**" and add a callout: *the final report must flag that authenticated/admin-only flaws were not assessed*.

## Tenant / scope boundaries  *(external-provided)*
- **Owned by the agent (safe to fully exercise):** <tenant/org/project IDs>
- **Do NOT cross into:** <list of other tenants/orgs/users visible to the agent's credentials>
  - If a finding allows cross-tenant impact, mark **INCONCLUSIVE — cross-tenant impact suspected, operator coordination required**; do NOT actually pivot.

## Off-limits resources  *(external-provided — even with admin credentials)*

Concrete allow/deny entries beyond URL patterns. The agent's privilege level does NOT override these.

- **Do NOT delete or modify:**
  - account `ops@example.com` (the operator's other admin)
  - bucket `prod_backups`
  - any object under prefix `customer-data/*`
- **Do NOT POST/PUT to:**
  - `/billing/*` (real billing pipeline)
  - `/webhooks/*` (fires external integrations)
- **Do NOT trigger:**
  - email sends to addresses other than `audit-sink+*@example.com`
  - SMS / push notifications
  - paid-tier feature toggles

If a PoC would need to touch any of the above, mark INCONCLUSIVE and document the required operator action.

## Rate limits / blast-radius caps  *(external-provided)*
- Max sustained request rate: `<N req/sec>`
- Bulk-create cap: `<e.g. up to 50 throwaway users per audit; tag with prefix audit-fork->`
- Bulk-create cleanup: `<who/when cleans them up; or operator does>`
- Monitoring / WAF in path: `<yes/no; if yes, contact for ban-recovery>`
- Quiet-hours requested: `<e.g. no probes 09:00–18:00 UTC>`

## Seed test data  *(external-provided)*
- Known-good IDs / tokens / uploads pre-staged by the operator:
  - `<resource type>`: `<ID>` — <purpose>
  - …
- Use these in preference to creating new state, when applicable.

## Config (bind-mounted; edits may hot-reload)  *(local-managed only)*
- `<path>/config.yaml` — server config; auto-reload: yes/no
- `<path>/rules.json`  — access rules / routing; auto-reload: yes/no
- `<path>/keys.json`   — secrets / JWKS; sensitive

## Changes made to get it running (vs upstream repo)  *(local-managed only)*
1. `<file>`: <change> — <why>
2. `<file>`: <change> — <why>
…

(Required for reproducing the local instance. Future auditors of the same repo can re-derive the working config from this list.)

## Verified working YYYY-MM-DD
- `<liveness command>` → exit 0, HTTP <status>
- `<known-test-route>` → 200/4xx as expected

## Common ops  *(local-managed only — write "N/A — external (contact operator)" otherwise)*
```bash
cd <workspace>
docker compose ps                          # or equivalent
docker compose logs -f <service>
docker compose restart <service>           # pick up non-hot-reload config edits
docker compose up -d --build <service>     # rebuild after source changes
docker compose down                        # full stop
```

## Notes for audit
- <e.g., default credentials / sample tokens for PoC — placeholder only>
- <e.g., anonymous-allowed test routes>
- <e.g., a mutator/auth path that uses local secrets — easier to test forgery>
- <e.g., warning: this instance proxies to `httpbin.org` — replace if testing offline>

## Hand-edit log (timestamps)
- YYYY-MM-DD HH:MM — <user/tool> edited `<file>` to add `<rule/feature>` for testing `<finding-id>`
- YYYY-MM-DD HH:MM — restored to baseline

(Local-managed: useful for verify forks to know if config drifted since deploy. External-provided: log every operator-coordinated change made for the audit.)
```

---

## Rules for the live-instance note

1. **Repo memory only.** Session memory dies; repo memory survives across audit campaigns of the same target.
2. **`Deployment mode` and `Capabilities` are the first two sections** — verify forks branch their entire behavior on them. Never omit or leave blank.
3. **Endpoint table is the most-read section after mode/capabilities.** Use full base URLs (`scheme://host:port`); never hardcode `127.0.0.1` unless the instance truly is local. A remote-host finding tested against `127.0.0.1` is a silent false negative.
4. **Document every deviation from upstream** (`local-managed`) — others will fail to reproduce without this list.
5. **Keep secrets OUT of this note.** Real credentials/tokens go in env vars; the note records only env-var names + roles + usage. This file lands in git-tracked / shareable memory.
6. **Off-limits resources override privilege.** Even with admin credentials, the agent must respect the deny-list — "I had permission" is not a defense for touching another admin's account or shared infrastructure.
7. **No credentials → explicitly record it.** If the operator gave only a URL, write "none — anonymous-only audit" in the credentials section so the final report can flag the coverage gap.
8. **Update the "Verified working" date** when you re-test reachability.
9. **Append to the hand-edit log** whenever you modify a bind-mounted config (`local-managed`) or coordinate an operator change (`external-provided`) — even temporarily — so verify forks know what state they're inheriting.
