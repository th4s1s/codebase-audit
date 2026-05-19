# `/codebase-audit:report` — Final Report Generation

**Purpose**: Stitch FP-check verdicts + verify-fork artifacts into the consolidated `report.md` and a short vendor-facing `disclosure-summary.md`.

**Entry**: All verify forks have finished (or have been explicitly skipped with documented reason).
**Exit**: `report.md` + `disclosure-summary.md` in the audit dir. User gate before any external disclosure.

---

## Step 1 — Inventory verify artifacts

```bash
ls reports/audit-<timestamp>/artifacts/verify-*.md
```

Parse each artifact's "Status" line. Build the inventory:

| finding_id | verify status | final severity | artifact |
|---|---|---|---|
| G1-F1 | CONFIRMED | HIGH | verify-G1-F1.md |
| … | … | … | … |

If any TP from `cba_fp_verdicts` has no verify artifact AND no "infra-blocked" justification, ASK THE USER whether to:
- Skip the finding (treat as source-only with a caveat in the report)
- Open another fork to verify

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
