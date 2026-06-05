# codebase-audit — source: Automated Source-Only Audit (unattended, no live instance)

**Purpose**: Run the entire audit pipeline on source code **end-to-end with no human in the loop and no live instance** — for product teams who want a security report on a codebase before a release. Runs **recon → audit → fpcheck → report**; skips **deploy** and **verify** entirely.

**Entry**: User invokes the **source** run (see SKILL.md → *How phases are invoked per client*) or asks for an "automated source-only audit". A source tree must be present.
**Exit**: A consolidated report under `reports/audit-<timestamp>/` (`report.md`, `disclosure-summary.md`, `audit.db`) plus a printed counts-by-severity summary. No user gates, no live verification.

---

## Automated source-only mode — precedence rules (READ FIRST)

You are running **unattended**. These rules **supersede** any conflicting instruction in the phase files you execute below:

1. **Never stop for user input.** Every "USER GATE", "ask the user", or "wait for confirmation" step in the referenced phases is **auto-resolved**: pick the best default and continue. Do not present gates; do not wait.
2. **Source only — read-only, no runtime, no mutation.** There is **no live instance**. Do **not** run the deploy phase; do **not** attempt any live PoC, `curl`, or runtime reproduction; do **not** edit, back up, restore, or write to any project/config file; do **not** start a process or send network traffic to a target. The only things you write are the audit's own `reports/` artifacts, `audit.db`, and memory notes. Every finding is recorded `verified='source-only'` (never `live-poc`).
3. **Auto-accept your own proposals.** Where a phase would ask the user to confirm (source-vs-IDA detection, the feature-group split), pick the correct/default option yourself and proceed.
4. **Best-effort network.** CVE / patch-bypass ingest is attempted but optional — if the network is unavailable, note it in the report and continue with pure source-level analysis. Never abort the run over a network failure.
5. **Compaction is automatic, not gated.** Between phases, compact context as the phase files advise (artifacts + resume note are already on disk), but do **not** pause for the user to do it.
6. **Abort only on a hard blocker**, with a clear one-line reason: no source tree found, or the target is IDA/binary-only (this mode is source-only — tell the user to run the interactive pipeline instead).

Optional free-text notes (focus area, scope hints) may arrive as `$ARGUMENTS`; honor them but never treat their absence as a reason to pause.

## Step 1 — recon (auto)

Execute [recon.md](recon.md) with these overrides:
- **Source detection (its Step 2):** auto-select the **source** target. If no source tree is detected (IDA/binary-only or empty), **abort** per precedence rule 6.
- **Feature groups (its Step 4):** propose the split per the size guidelines and **auto-accept it** — do not ask.
- **Mapping subagents (its Step 5):** run normally (writable subagents — see SKILL.md → *Cross-client tool mapping* — one per group, in parallel).
- **USER GATE (its Step 7):** **skip** — write the resume note, then continue straight to Step 2.

## Step 2 — audit (auto, source-only)

Execute [audit.md](audit.md) with these overrides:
- **CVE / patch-bypass ingest:** best-effort (rule 4) — attempt it; run `gh` **non-interactively** (ensure `GH_TOKEN` is set, or skip if `gh auth status` fails) so it can never open an auth prompt; on any auth/network error, record "CVE ingest skipped: network/auth unavailable" in the resume note + report and continue. Never abort or pause.
- **Deep-audit subagents — source-only template:** when filling the [phase4-deep-audit.md](../references/phase4-deep-audit.md) prompt template, **omit all live-instance details** and set its *Test Instance* section to the documented fallback — **"No test instance available. Provide source-level analysis only."** **Delete the live-verification (curl / requests / raw-sockets) instructions.** The only legal `verified` value a subagent may write is **`source-only`** — never `live-poc`.
- **No mutation (rule 2):** **drop audit.md Step 4's "Live-instance hygiene" bullet entirely** — subagents must NOT edit, back up, or restore any project/config file. Read-only source analysis only.
- **USER GATE:** **skip** — continue straight to Step 3.

## Step 3 — fpcheck (auto)

Execute [fpcheck.md](fpcheck.md) as written (it is already **static-only**) with these overrides:
- Run the parallel FP-check subagents and populate `cba_fp_verdicts` exactly as normal.
- **Skip** the "open verify forks" step and its gate — there is no verification in this mode. Continue straight to Step 4 with the TRUE_POSITIVE list.

## Step 4 — report (auto, verification skipped)

Execute [report.md](report.md), treating its **Step 1 MISSING-TP gate** as an explicit "all TPs source-only / verification skipped" decision (there are no verify forks in this mode):
- Do **not** require or look for `verify-<id>.md` artifacts; do **not** stop. Tag **every** finding `(source-only — not live-verified)`.
- Build `report.md` + `disclosure-summary.md` from the **TRUE_POSITIVE** verdicts in `cba_fp_verdicts`, ordered by source-assessed severity.
- **Per-finding PoC honesty:** each finding's "Proof of Concept" section holds only the **source-level data-flow / reproduction sketch** (from `cba_findings.poc`), explicitly labeled **"source-only — not executed"**. **Never** paste or fabricate an HTTP request/response as if it were captured live evidence — there is none in this mode.
- **Quality-check carve-out:** report.md's Step 6 QC items that reference verify-fork confirmation or "PoCs reproducible against the live instance" are **N/A** here; the accepted tag is `(source-only — not live-verified)` (not "infra-blocked").
- **Honest-reporting caveat (mandatory):** state prominently near the top of both `report.md` and `disclosure-summary.md` that **all findings are static (source-level) true-positives that survived false-positive review but were NOT live-verified** — severities are source-assessed, and running the interactive `verify` phase against a live instance is recommended before any external disclosure.
- **Skip** the report phase's pre-disclosure user gate — produce the artifacts and continue to Step 5.

## Step 5 — final summary (printed, no gate)

Print a concise summary for the operator:
- Path to `reports/audit-<timestamp>/report.md`.
- Counts of TRUE_POSITIVE findings by source-assessed severity (CRITICAL / HIGH / MEDIUM / LOW / INFO).
- A one-line reminder that findings are source-only (not live-verified) and that `verify` against a live instance is recommended before disclosure.

Do **not** perform any external disclosure. Stop.

## Quality checks

- [ ] recon, audit, fpcheck, report all completed **without pausing for input**
- [ ] No deploy phase ran; no live-instance / `curl` / PoC was attempted; every finding is `verified='source-only'`
- [ ] `report.md`, `disclosure-summary.md`, `audit.db` exist under `reports/audit-<timestamp>/`
- [ ] The report carries the source-only / not-live-verified caveat
- [ ] Final severity-counts summary was printed; no disclosure performed
