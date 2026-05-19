# `/codebase-audit:verify` — Per-Finding Live PoC (Runs in a FORK)

**Purpose**: Reproduce true-positive findings against the deployed live instance. **This workflow runs in a forked conversation**, not the main orchestrator. The fork covers a small batch of findings (~5-8) and writes one artifact per finding.

**Entry**: You are a forked conversation. The user pasted a verify-fork prompt. The audit's main orchestrator is paused awaiting fork completion.
**Exit**: One `verify-<finding-id>.md` artifact per in-scope finding. Return a summary table to the user (who will hand it back to the orchestrator).

---

## Step 0 — Orient yourself

You are a fork. Do these reads first (parallel):

1. `/memories/session/<project>-audit-resume.md` — current pipeline state, what's TP, fork inventory, live-instance pointer
2. `/memories/repo/<project>-live-instance.md` — endpoints, bind-mounted config, restart commands, hand-edit warnings
3. Each in-scope finding's section in `reports/audit-<timestamp>/artifacts/G<n>-findings.md`
4. The corresponding FP-check verdict reason from `cba_fp_verdicts` (verifies the FP-check was satisfied this is a real bug, so any "can't reproduce" outcome is suspicious)

Confirm the live instance is reachable:

```bash
curl -sS http://127.0.0.1:<port>/health 2>&1 | head
docker compose ps  # or equivalent
```

If it isn't up: bring it up using the commands documented in the live-instance note. Don't change the deployment configuration unless required for a specific PoC (and back it up if so).

## Step 1 — Per-finding loop

For EACH finding in scope:

### 1a. Plan the PoC

From the artifact's "PoC" section, extract the curl/payload. Identify what live-instance changes are needed:

- **No changes**: curl against an existing route → trivial, just run.
- **Temp rule needed**: edit `rules.json` / matching config → **BACK UP FIRST**.
- **Temp config needed**: edit `config.yaml` → **BACK UP FIRST**.
- **Restart required**: note it; restart adds latency.

### 1b. Back up before any modification

Mandatory backup pattern:

```bash
cp <config-file> /tmp/<filename>.bak.fork-<X>-<finding-id>
```

Where `<X>` is your fork letter and `<finding-id>` is the current finding. This makes it easy to find and restore the right backup if multiple findings need config edits.

### 1c. Re-read the config before editing

**The user may have hand-edited the live-instance config between phases.** Always re-read the current file content before making edits — never assume it matches what was there yesterday.

### 1d. Apply the change, restart if needed, capture HTTP output

Use `curl -i` to capture full headers + body. Pipe to a temp file if large:

```bash
curl -sSi <endpoint> -H '<malicious-header>' -d '<payload>' | tee /tmp/poc-<id>.txt
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

Before returning to the user, verify the live instance is back to baseline:

```bash
diff /tmp/<config-original-backup> <config-file>  # should be empty
curl -s <api-url>/rules | jq  # should match pre-fork state
docker compose ps                # services still up
```

## Step 4 — Return summary

Return a compact markdown table to the user:

| Finding | Status | Severity (orig → final) | One-line note |
|---|---|---|---|
| G<n>-F<m> | CONFIRMED | HIGH → HIGH | Live PoC: <one-line> |
| … | … | … | … |

Plus a one-paragraph high-level summary the user can paste back to the orchestrator.

## Common Pitfalls (see also [../references/lessons-learned.md](../references/lessons-learned.md))

- **Forgetting to restore** the live-instance config. Always verify restoration before returning.
- **Editing the wrong config file** because the user edited it between phases. Re-read first.
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
