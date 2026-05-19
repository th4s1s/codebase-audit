# `/codebase-audit:verify` — Per-Finding Live PoC (Runs in a FORK)

**Purpose**: Reproduce true-positive findings against the deployed live instance. **This workflow runs in a forked conversation**, not the main orchestrator. The fork covers a small batch of findings (~5–8) and writes one artifact per finding.

**Entry**: You are a forked conversation. The user pasted a verify-fork prompt **or** ran `/codebase-audit:verify <comma-separated-ids>` (IDs are mandatory). The audit's main orchestrator is paused awaiting fork completion.
**Exit**: One `verify-<finding-id>.md` artifact per in-scope finding. Return a summary table to the user (for their situational awareness — the orchestrator does NOT need it pasted back; `/codebase-audit:report` reads the artifacts directly from disk).

---

## Guard — refuse to run without IDs

If the user invoked `/codebase-audit:verify` with **no finding IDs and no pasted fork prompt**, stop immediately and respond:

> `/codebase-audit:verify` runs in a forked conversation and requires a finding-ID list (e.g. `/codebase-audit:verify G1-F1,G1-F2`). To consolidate the artifacts produced by completed forks, run `/codebase-audit:report` in this orchestrator — it will ingest every `verify-<id>.md` from disk and refuse to continue if any TP is missing.

Do not attempt to guess intent. Do not run any PoC. Do not scan artifacts. Wait for the user to re-issue the correct command.

---

## Step 0 — Orient yourself

You are a fork. Do these reads first (parallel):

1. `/memories/session/<project>-audit-resume.md` — current pipeline state, what's TP, fork inventory, live-instance pointer
2. `/memories/repo/<project>-live-instance.md` — **deployment mode, capabilities, base URLs, liveness command**, bind-mounted config, hand-edit log, **credentials inventory, tenant/scope boundaries, off-limits resources, rate-limit caps, seed test data** (external-provided)
3. Each in-scope finding's section in `reports/audit-<timestamp>/artifacts/G<n>-findings.md`
4. The corresponding FP-check verdict reason from `cba_fp_verdicts` (verifies the FP-check was satisfied this is a real bug, so any "can't reproduce" outcome is suspicious)

Confirm the live instance is reachable using the **liveness command from the live-instance note** (do not invent one — `/health` may 404 or be sensitive, and `127.0.0.1` may be the wrong host):

```bash
<liveness command from live-instance note>     # e.g. curl -fsS <base-url>/<liveness-path>
```

For `local-managed` mode you may additionally use container introspection (`docker compose ps`, etc.). For `external-provided` mode the HTTP probe is the only signal — **do not** swap in a local-loopback probe; that will silently test the wrong target.

### Mode-dependent constraints (read before planning ANY PoC)

The `Capabilities` table in the live-instance note is authoritative. For `external-provided` instances in particular:

- **No config backup / edit / restart.** Skip Steps 1b, 1c, 1f for those findings. If a finding **requires** a config change, mark it **INCONCLUSIVE** with status note `requires operator-coordinated change: <what>` — do NOT attempt a local-loopback substitute.
- **No filesystem access.** Treat the target purely as an HTTP black box.
- **Respect the "Off-limits surface" list** in the note — skip any finding whose PoC would hit a forbidden path/method, mark INCONCLUSIVE with reason `operator forbids hitting <surface>`.
- **Respect the "Off-limits resources" list.** Even if your credentials would allow it, do NOT delete/modify other admin accounts, other tenants' data, billing/webhook endpoints, or any specific resource in the deny-list. Mark INCONCLUSIVE with reason `would touch off-limits resource: <id>`.
- **Respect tenant / scope boundaries.** Stay inside the tenant(s) the agent owns. If a PoC requires pivoting into another tenant to demonstrate impact, stop at the boundary and mark **INCONCLUSIVE — cross-tenant impact suspected, operator coordination required** with a description of what would happen if executed.
- **Respect rate-limit / blast-radius caps.** Throttle to the documented max req/sec; cap bulk-create probes at the documented limit; tag all created throwaway resources with a recognizable prefix (e.g. `audit-fork-G1-F2-…`) so the operator can clean them up. If the cap blocks the PoC, mark INCONCLUSIVE with reason `cap exceeded: <what>`.
- **Use seed test data when available** rather than creating new state.
- **Pull credentials from the documented env vars** (`Credentials inventory` section). Never paste tokens into artifacts; reference the env var name instead. If `can-rotate=no`, treat the credential as scarce — avoid actions that could lock you out (password change, MFA enrollment, etc.).

If the live instance is **not reachable** and mode is `local-managed`, bring it up using the documented `Common ops` commands. If it is not reachable and mode is `external-provided`, stop — return to the user with the unreachable status; do NOT attempt to restart or redeploy. The user must coordinate with the operator.

## Step 1 — Per-finding loop

For EACH finding in scope:

### 1a. Plan the PoC

From the artifact's "PoC" section, extract the curl/payload. Identify what live-instance changes are needed and cross-check against the `Capabilities` table:

- **No changes**: curl against an existing route → trivial, just run.
- **Temp rule needed**: edit `rules.json` / matching config → **BACK UP FIRST** (only if `edit-config: yes`; otherwise INCONCLUSIVE).
- **Temp config needed**: edit `config.yaml` → **BACK UP FIRST** (same constraint).
- **Restart required**: note it; restart adds latency (only if `restart-service: yes`; otherwise INCONCLUSIVE).

If any required capability is **no**, do not proceed with that finding — write the artifact with status **INCONCLUSIVE** and reason `requires <capability> which is unavailable in <mode> mode`. Skip the rest of Step 1 for that finding.

### 1b. Back up before any modification

Mandatory backup pattern:

```bash
cp <config-file> /tmp/<filename>.bak.fork-<X>-<finding-id>
```

Where `<X>` is your fork letter and `<finding-id>` is the current finding. This makes it easy to find and restore the right backup if multiple findings need config edits.

### 1c. Re-read the config before editing

**The user may have hand-edited the live-instance config between phases.** Always re-read the current file content before making edits — never assume it matches what was there yesterday.

### 1d. Apply the change, restart if needed, capture HTTP output

Use `curl -i` to capture full headers + body. Build the URL from the **base URL recorded in the live-instance note** — never substitute `127.0.0.1` for a remote host. Pipe to a temp file if large:

```bash
curl -sSi <base-url>/<path> -H '<malicious-header>' -d '<payload>' | tee /tmp/poc-<id>.txt
```

Capture:
- Request line
- Full response (status, headers, body — truncate body to 2KB if huge)
- Any side-effect evidence (server logs, file changes, downstream service receipt)

### 1e. Determine status

- **CONFIRMED**: PoC reproduces the claimed impact. Capture severity adjustments (often unchanged; sometimes upgraded when impact is broader than expected).
- **REFUTED**: PoC does not reproduce. Re-read the source one more time to be sure — if still no repro, the finding should be dropped from the report. Document exactly why (e.g., "a default config guard at `file:line` blocks the payload").
- **INCONCLUSIVE**: Live instance lacks required infrastructure (e.g., needs a gRPC client, an SSE upstream, an external IdP) and you can't stand it up reliably. Document the missing piece. Keep finding as source-only in the report with this note.

### 1f. RESTORE the config

```bash
cp /tmp/<filename>.bak.fork-<X>-<finding-id> <config-file>
docker compose restart <service>  # if needed
```

Verify restore worked (e.g., `curl -s http://127.0.0.1:<api-port>/rules | jq '[.[]|.id]'` for oathkeeper).

### 1g. Write the verify artifact

Save to **`reports/audit-<timestamp>/artifacts/verify-<finding-id>.md`** with this structure:

```markdown
# Verify <finding-id> — <short title>

**Audit:** `audit-<timestamp>`  · **Fork:** <letter>  · **Date:** <date>
**Finding artifact:** [G<n>-findings.md#<finding-id>](G<n>-findings.md)
**FP-check verdict:** TRUE_POSITIVE — <reason>

## Status: CONFIRMED | REFUTED | INCONCLUSIVE

## Live-instance setup
- Backup taken: `/tmp/...bak.fork-<X>-<finding-id>`
- Config change: <description, or "none">
- Restart required: yes/no

## PoC invocation
```bash
<exact curl/script>
```

## Full captured response
```http
<status line + headers + body>
```

## Interpretation
<2-4 sentences: what the response shows, why it confirms/refutes/blocks the claim>

## Severity adjustment
<original-severity> → <final-severity>  (reason if changed)

## Draft remediation
<1-3 sentences of code-level fix guidance, suitable for vendor disclosure>

## Cleanup verified
- Config restored from backup: yes
- Live instance back to baseline: yes (verified via `<command>`)
```

## Step 2 — Do NOT modify `cba_findings` or `cba_fp_verdicts`

That's the orchestrator's job in the report phase. You only write artifact files.

## Step 3 — Final restoration check

Before returning to the user, verify the live instance is back to baseline.

For `local-managed` mode:

```bash
diff /tmp/<config-original-backup> <config-file>  # should be empty
curl -s <admin-base-url>/rules | jq  # should match pre-fork state
docker compose ps                                    # services still up
```

For `external-provided` mode (no filesystem / no lifecycle access), just re-run the documented liveness command and any read-only sanity probe:

```bash
<liveness command from live-instance note>           # exit 0 + expected status
curl -sSI <base-url>/<known-stable-route>            # status unchanged vs Step 0
```

## Step 4 — Return summary

Return a compact markdown table to the user (this is for the user's situational awareness — **the orchestrator does NOT need it pasted back**, it reads the `verify-<id>.md` artifacts directly from disk):

| Finding | Status | Severity (orig → final) | One-line note |
|---|---|---|---|
| G<n>-F<m> | CONFIRMED | HIGH → HIGH | Live PoC: <one-line> |
| … | … | … | … |

Plus a one-paragraph high-level summary. The user can close this fork once the table looks right; the orchestrator will pick the artifacts up on its next `/codebase-audit:verify` (ingest) or `/codebase-audit:report` invocation.

## Common Pitfalls (see also [../references/lessons-learned.md](../references/lessons-learned.md))

- **Forgetting to restore** the live-instance config (`local-managed`). Always verify restoration before returning.
- **Editing the wrong config file** because the user edited it between phases. Re-read first.
- **Probing `127.0.0.1` when mode is `external-provided`.** The loopback probe will appear to succeed against an unrelated service on your fork's host and silently invalidate every verdict. Always build URLs from the documented base URL.
- **Attempting `docker compose ...` against an external instance.** You don't manage it. Mark INCONCLUSIVE and request operator coordination.
- **Capturing only stdout, not headers** — use `curl -i` or `curl -D-`.
- **Concluding REFUTED too quickly** when a default config guard could be relaxed. If the finding is "X works when Y is enabled" and Y is off by default, that's still TP — document the config requirement, don't refute.
- **Spending excessive time on infra-blocked findings.** If you've spent more than a few attempts standing up infrastructure (e.g., gRPC test client) for one finding, mark INCONCLUSIVE and move on.

## Quality Checks (before returning)

- [ ] Every in-scope finding has a `verify-<id>.md` artifact
- [ ] Every CONFIRMED finding includes full captured HTTP response
- [ ] Every REFUTED finding cites the specific code/config that blocks the PoC
- [ ] All config backups have been restored
- [ ] Live instance is operational (health check passes)
- [ ] You have NOT modified `cba_findings` or `cba_fp_verdicts`

> **Consolidation happens in `report`, not here.** The orchestrator picks up every `verify-<id>.md` you write via [report.md](report.md) Step 1. Do not implement an orchestrator-side ingest in this workflow.
