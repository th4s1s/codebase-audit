# codebase-audit — report: Final Report Generation

**Purpose**: Stitch FP-check verdicts + verify-fork artifacts into the consolidated `report.md` and a short vendor-facing `disclosure-summary.md`.

**Entry**: All verify forks have finished (or have been explicitly skipped with documented reason). Runs in the **main orchestrator**, never in a fork.
**Exit**: `report.md` + `disclosure-summary.md` in the audit dir. User gate before any external disclosure.

---

## Step 1 — Ingest verify artifacts (mandatory, before anything else)

This step is the canonical "orchestrator reads what the forks produced" — there is no separate ingest command. **You do not run any live-instance PoC here.**

1. Locate the active audit dir from the resume note (fallback: `ls -td reports/audit-* | head -1`).
2. Glob the artifacts:
   ```bash
   ls -1 reports/audit-<timestamp>/artifacts/verify-*.md 2>/dev/null
   ```
3. For each artifact, parse the `Status:` line (CONFIRMED | REFUTED | INCONCLUSIVE), the `Severity adjustment:` line, the one-sentence interpretation, and the **Adversarial review** outcome (note any finding the fork's fresh reviewers overturned or downgraded — those are already reflected in the Status/severity, don't reinstate them).
4. Pull the canonical TP list:
   ```sql
   SELECT finding_id FROM cba_fp_verdicts WHERE verdict = 'TRUE_POSITIVE';
   ```
5. Reconcile artifacts ↔ TPs into this table:

| finding_id | verify status | final severity | artifact | note |
|---|---|---|---|---|
| G1-F1 | CONFIRMED | HIGH | `verify-G1-F1.md` | Live PoC captured |
| G1-F2 | INCONCLUSIVE (external) | MED | `verify-G1-F2.md` | Operator restart required |
| G2-F5 | **MISSING** | n/a | _none_ | No fork has covered this TP |
| … | … | … | … | … |

6. **Gate**: if any TP row is `MISSING` AND has no documented "infra-blocked" justification in the resume note, **STOP and ask the user**:
   - Open another fork for the missing IDs (recommended), OR
   - Explicitly skip (the finding will be tagged `(source-only — not live-verified)` in the report).

   Provide a copy-pasteable fork prompt batching the missing IDs (~5–8 per fork) so the user can immediately open the next fork. Do **not** proceed to Step 2 until every TP has an artifact or an explicit skip decision.

7. Refresh `/memories/session/<project>-audit-resume.md` with a "Verify status snapshot" section: CONFIRMED / REFUTED / INCONCLUSIVE / MISSING counts. Mark verify DONE only if MISSING is empty (or every MISSING is user-skipped).

## Step 2 — Drop REFUTED findings

Findings marked REFUTED in their verify artifact are excluded from the report (but retained in `audit.db` for audit trail). Add them to the "False Positive Analysis" section of the report as "Refuted by live testing".

## Step 3 — Final severity re-rank

Final severity = `verify-<id>.md` final severity OR `cba_fp_verdicts.final_severity` if no verify artifact OR `cba_findings.severity` as last resort.

Order: CRITICAL → HIGH → MEDIUM → LOW; within tier, group affinity then finding ID.

Re-assign `final_id` (F-1, F-2, …) in this final order:

```sql
UPDATE cba_fp_verdicts SET final_id = 'F-' || <rank>
WHERE finding_id = <id>;
```

## Step 4 — Write `report.md`

Use [../references/phase6-report.md](../references/phase6-report.md) as the template. Required sections in order:

1. **Title + metadata** (target, version/commit, audit date, methodology)
2. **Executive summary** — 1-2 paragraphs + finding count table by severity
3. **Architecture overview** — brief, with attack surface table
4. **Findings** — one per confirmed TP, ordered F-1 → F-N. Each contains:
   - Metadata table (severity, CWE, CVSS if calc, attacker position, boundary, affected file)
   - Description (root cause)
   - Data flow
   - Impact
   - **Proof of Concept** — paste the captured request + response from the verify artifact verbatim
   - **Remediation** — code-level guidance
   - **References** — link to upstream advisories if patch-bypass class
5. **False Positive Analysis** — counts by category (HE-N, PR-N, refuted-by-live, dup-merged)
6. **Recommendations** — by priority (immediate / short-term / long-term)
7. **Appendix**:
   - Methodology summary
   - Feature group table with finding counts
   - Tools used
   - **Artifact directory listing** (so reader can audit our process)

### PoC packaging (for reproducibility)

If the audit produced custom PoC scripts/patches, stage them in a single self-contained **`poc/` directory with relative paths** (e.g. `poc/run_poc.sh`, `poc/<bug>.patch`, `poc/output/`). The triager will **not** have your `reports/audit-<timestamp>/` tree — never reference that nested path in the report or PoC. Each PoC should:
- run from a clean checkout (build any attacker-side patch from the included `.patch`; do **not** ship prebuilt binaries — the maintainer rebuilds and shouldn't trust an opaque binary);
- embed the **real captured output** (paste exactly what the script printed — don't hand-write expected output);
- keep the victim stock and state that the patch, if any, is the *attacker* side (see verify.md "PoC rigor + evidence model").

## Step 4b — Adversarial self-verification (before disclosure)

Each finding was already independently reviewed by fresh subagents in its verify fork (the **Adversarial review** section of `verify-<id>.md`); this pass is the orchestrator's lighter consolidation-time check — carry forward any DISPUTED/overturned outcome and don't reinstate a finding the fork's reviewers downgraded. Before the user gate, re-verify the report's claims against source + captured evidence — overstatement or a wrong citation in a bug-bounty submission is often disqualifying. For each finding, check three lenses (independent reviewers / subagents are ideal — they catch what the author's narrative misses):
1. **Citations** — every `file:line`, quoted snippet, and constant matches the source at the audited commit.
2. **Mechanism** — the root cause re-derives from scratch; the data flow actually reaches the sink.
3. **Claims & severity** — every quantitative/behavioral claim is backed by the captured evidence, and the severity is not inflated.

Tighten wording to what was measured: "**effectively unbounded** (expected N iterations)" not "infinite"; "**observed** M/N crashes" not "it crashes"; "single-component DoS" not "takes down the service" unless shown. Fix everything the pass catches before Step 5.

## Step 5 — Write `disclosure-summary.md`

A SHORT vendor-facing summary (≤2 pages). Sections:

1. **Affected versions** — exact commit/tag/version range
2. **Summary table** — one row per finding: ID, title, severity, CWE, CVSS, file:line, patch-bypass classification
3. **Critical findings, expanded** — for CRIT/HIGH only: 1-paragraph description + 1 PoC + 1 remediation line
4. **Disclosure timeline placeholder** — discovery date, vendor contact, agreed disclosure date

This is the file you send when filing GHSA / contacting `security@…`.

## Step 6 — Final quality checks

- [ ] Every finding in `report.md` is either CONFIRMED via verify-fork OR explicitly tagged as `(source-only — infra-blocked: <reason>)`
- [ ] No REFUTED findings appear in the body (only in FP Analysis section)
- [ ] All file:line references resolve in the target repo at the audited commit
- [ ] All PoCs are reproducible against the documented live instance
- [ ] `report.md` table-of-contents links work
- [ ] Severity ordering is correct (CRIT first)
- [ ] CWE numbers are valid (CWE-N where N is a real CWE)
- [ ] Patch-bypass findings explicitly cite the prior CVE/GHSA

## Step 7 — USER GATE (before disclosure)

Present:

> Final report and disclosure summary are at:
> - `reports/audit-<timestamp>/report.md`
> - `reports/audit-<timestamp>/disclosure-summary.md`
>
> Findings (final): X CRITICAL, Y HIGH, Z MEDIUM, W LOW.
>
> Highest-value items for vendor disclosure: <top 3 with one-line each>
>
> Next steps you should take (NOT me):
> 1. Review the report personally
> 2. File GHSA on github.com/<owner>/<repo>/security/advisories/new
> 3. Email security@<vendor>.com with disclosure-summary.md attached
> 4. Wait for vendor confirmation before publishing
>
> I will NOT contact the vendor automatically. Disclosure is your call.

## Step 8 — Update resume note one last time

Mark report phase DONE. Leave the resume note in a "completed audit" state so a future session can re-open the audit to add late findings.

## Quality Checks (final)

- [ ] `report.md` exists and parses as valid markdown
- [ ] `disclosure-summary.md` ≤ 2 printed pages
- [ ] `audit.db` retained alongside the report
- [ ] All `artifacts/` files retained (do NOT delete — they are the audit trail)
- [ ] Resume note marked DONE
