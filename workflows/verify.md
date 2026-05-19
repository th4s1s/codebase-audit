# `/codebase-audit:verify` — Per-Finding Live PoC

**Purpose**: Reproduce true-positive findings against the deployed live instance and record the result as an on-disk artifact per finding. This workflow has **two modes** depending on where it is invoked:

| Invoked from | Mode | What it does |
|---|---|---|
| **A forked conversation** (user opened a new chat and pasted the fork prompt, or ran `/codebase-audit:verify <ids>` in the fork) | `fork` | Runs the per-finding PoC loop and writes `verify-<finding-id>.md` artifacts. Returns a summary table for the user's eyes. |
| **The main orchestrator** (no fork prompt; user just runs `/codebase-audit:verify`) | `orchestrator-ingest` | Scans `reports/audit-<timestamp>/artifacts/verify-*.md`, reconciles against `cba_fp_verdicts`, surfaces a status table, and updates the resume note. **Does NOT run any PoC.** |

**Entry**:
- Fork mode: you are a forked conversation. The user pasted a verify-fork prompt or ran `/codebase-audit:verify <comma-separated-ids>`. The orchestrator is paused awaiting fork completion.
- Orchestrator-ingest mode: you are the main orchestrator and the user ran `/codebase-audit:verify` with no finding IDs. Some verify forks have produced (or finished producing) artifacts.

**Exit**:
- Fork mode: one `verify-<finding-id>.md` artifact per in-scope finding; summary table printed to the user.
- Orchestrator-ingest mode: status table showing which findings have artifacts (CONFIRMED / REFUTED / INCONCLUSIVE / MISSING), and an updated resume note. No artifacts ever need to be pasted back — the orchestrator reads them directly from disk.

---

## Mode detection (do this first)

- If the user provided a comma-separated list of finding IDs (e.g. `/codebase-audit:verify G1-F1,G1-F2`) **or** you are in a forked conversation that received a verify-fork prompt → you are in **fork mode**. Proceed to Step 0.
- Otherwise → you are in **orchestrator-ingest mode**. Jump to the [Orchestrator-ingest mode](#orchestrator-ingest-mode) section at the bottom of this file.

---

## Step 0 — Orient yourself  *(fork mode)*

You are a fork. Do these reads first (parallel):

1. `/memories/session/<project>-audit-resume.md` — current pipeline state, what's TP, fork inventory, live-instance pointer
2. `/memories/repo/<project>-live-instance.md` — **deployment mode, capabilities, base URLs, liveness command**, bind-mounted config, hand-edit log
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

---

## Orchestrator-ingest mode

You are the **main orchestrator** and the user ran `/codebase-audit:verify` with no finding IDs. Some verify forks have produced (or finished producing) artifacts and you need to reconcile them against the FP-check verdicts.

**You do not run any PoC in this mode. You only read artifacts that already exist.**

### Step A — Locate the audit dir + scan artifacts

Get the active `reports/audit-<timestamp>/` from the resume note (or `ls -td reports/audit-*` if missing). Then:

```bash
ls -1 reports/audit-<timestamp>/artifacts/verify-*.md 2>/dev/null
```

For each file, extract:
- `<finding-id>` from the filename (`verify-G1-F2.md` → `G1-F2`)
- `Status:` line (CONFIRMED | REFUTED | INCONCLUSIVE)
- `Severity adjustment:` line (orig → final)
- The one-sentence `Interpretation` (for the table)

### Step B — Reconcile against `cba_fp_verdicts`

Query the TRUE_POSITIVE list:

```sql
SELECT finding_id FROM cba_fp_verdicts WHERE verdict = 'TRUE_POSITIVE';
```

Cross-check against the artifact set. Three possible states per TP finding:

| State | Meaning | Action |
|---|---|---|
| Artifact exists + Status is CONFIRMED/REFUTED/INCONCLUSIVE | Fork finished | Include in status table |
| Artifact exists but Status field is missing/blank | Fork wrote a partial file | Flag for user attention |
| No artifact | No fork has covered this finding yet | List as MISSING — user needs to open another fork |

### Step C — Surface the status table

Print a single table for the user:

| Finding | Status | Severity (orig → final) | Source artifact | Note |
|---|---|---|---|---|
| G1-F1 | CONFIRMED | HIGH → HIGH | `verify-G1-F1.md` | <one-line interpretation> |
| G1-F2 | INCONCLUSIVE (external) | MED → MED | `verify-G1-F2.md` | Requires operator restart |
| G2-F5 | **MISSING** | n/a | \_none\_ | Open a fork for this finding |
| … | … | … | … | … |

Group by status. Highlight `MISSING` entries first so the user knows which forks still need to run.

### Step D — Update the resume note

Append (or refresh) a "Verify status snapshot" section to `/memories/session/<project>-audit-resume.md` with:
- Total TPs
- CONFIRMED count
- REFUTED count
- INCONCLUSIVE count + brief reasons
- MISSING list (finding IDs)

Do NOT mark verify DONE in the resume note unless every TP has a non-MISSING artifact.

### Step E — Tell the user what to do next

- If MISSING is non-empty: tell the user which finding IDs still need a fork, and provide a copy-pasteable fork prompt for each (or a single prompt batching them ~5-8 per fork).
- If MISSING is empty: confirm verify is complete and suggest `/codebase-audit:report` (after the recommended manual compact).

### Mode-specific Quality Checks

- [ ] You did NOT run any curl / PoC / live-instance probe
- [ ] You did NOT modify `cba_findings` or `cba_fp_verdicts`
- [ ] Every TP finding from `cba_fp_verdicts` appears in the status table (either with an artifact or as MISSING)
- [ ] Resume note's "Verify status snapshot" reflects current disk state
