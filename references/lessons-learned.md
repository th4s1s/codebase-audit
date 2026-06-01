# Lessons Learned — From Real Audits

This file records pitfalls observed in actual codebase-audit runs. Read it **before** starting any new audit. Each lesson includes the symptom, the root cause, and the prevention.

---

## 1. `Explore` subagent is read-only — silently produces no artifacts

**Observed in:** A prior Phase 4 run. Six of seven groups returned no findings to SQL.

**Symptom:** Subagent returns analytical text but never runs `INSERT` statements or creates `artifacts/G<n>-findings.md` files. The orchestrator sees output that looks like findings but the database stays empty.

**Root cause:** `Explore` agent type has no terminal, no file-write, and no SQL tools. It silently does nothing when asked to write to disk.

**Prevention:**
- Use `general-purpose` agent type for any subagent that must write artifacts, run SQL, or hit the live instance.
- Use `Explore` ONLY for pure read-only research and Q&A.
- If you encounter this mid-pipeline: re-spawn the failed subagent with `general-purpose`, OR manually materialize the findings from the agent's return blob into `artifacts/G<n>-findings.md` + SQL inserts. Don't lose findings.

---

## 2. Live-instance config drift between phases

**Observed in:** A prior audit. The user hand-edited bind-mounted config files between fpcheck and verify forks. A fork that assumed the baseline state could have made wrong edits or failed to restore correctly.

**Symptom:** Verify forks see config that doesn't match the audit-phase snapshot. Restorations write back a state the user didn't want.

**Prevention:**
- Always **re-read** any config file immediately before editing it.
- Back up with a unique filename per fork+finding: `/tmp/<file>.bak.fork-<X>-<finding-id>`.
- After PoC, `diff` against the backup to confirm what you changed.
- Restore from backup, verify via a probe command (re-run the documented liveness command), and only THEN move to next finding.
- The live-instance note has a "Hand-edit log" section — update it after any temp modification.

---

## 3. Patch-bypass class findings are the highest-value output

**Observed in:** A prior audit — the two CRITICAL findings both came from a single GHSA being patched in one handler but the same root cause left untouched in a sibling handler.

**Symptom:** A vendor patches one file, files a CVE, and considers the issue closed. Sibling files with identical root cause aren't reviewed.

**Prevention:**
- In Phase 3 (known findings ingest), for **every** advisory: fetch the patch commit, list the files touched, then **grep the codebase for the same pattern in other files**. Document the "probe these sites" list in `files/known-findings.md`.
- Phase 4 subagents must receive the patch-bypass intel and probe those specific sites.
- The "Top patch-bypass discoveries" section of the resume note exists to highlight these for vendor disclosure prioritization.

---

## 4. Operator-config "vulnerabilities" usually fail Marginal Gain Test

**Observed in:** Several Phase 5 dismissals — e.g., a URL-traversal finding that turned out to be FP because the operator already controlled the same setting directly and the new path gave no marginal attacker gain.

**Symptom:** A finding describes an operator-only configuration path that grants an effect the operator could already produce via another documented setting. Listed as TP, but actual attacker has no marginal gain.

**Prevention:**
- FP-check subagents must explicitly apply HE-17 (Marginal Gain Test): "Does this finding give an attacker a *new* capability they didn't already have, GIVEN the threat model?"
- Operator misconfiguration → typically not a CVE (it's a documentation/hardening issue).
- Distinguish "operator does something dangerous" (not a CVE) from "untrusted input reaches dangerous sink without operator opt-in" (likely a CVE).

---

## 5. Session memory drops from subagents accumulate

**Observed in:** Several subagents wrote `/memories/session/<group>-mapping.md` or `<group>-findings.md` during their run. After the orchestrator consolidated into `artifacts/G<n>-findings.md`, these intermediate files lingered.

**Symptom:** Session memory has stale duplicate content; future sessions get confused about which file is the canonical truth.

**Prevention:**
- Subagent prompts should explicitly say: "Write your output to `<AUDIT_DIR>/artifacts/G<n>-findings.md`, not to session memory."
- After consolidating, delete intermediate session-memory files: `memory delete /memories/session/g<n>-*.md`.
- Resume note should declare which file is canonical for each piece of state.

---

## 6. Subagent stalls / timeouts mid-run

**Observed in:** One Phase-5 batch subagent (G2 batch) stalled and never wrote SQL inserts.

**Symptom:** Batch returns no response, no error, no SQL rows. Other batches finished cleanly.

**Prevention:**
- After spawning N parallel subagents, after they "finish": query SQL to confirm row counts match expected (`SELECT COUNT(*) FROM cba_fp_verdicts`).
- If a batch is short: identify which findings are missing, re-spawn just that batch with the same prompt.
- The fpcheck/audit workflows include explicit count-check steps for this reason.

---

## 7. Resume note rot — partial updates leave stale sections

**Symptom:** Resume note has new phase status at top but stale "next-step plan" at bottom that refers to a phase already done.

**Prevention:**
- **Rewrite the resume note fully** at the end of each phase, don't just append.
- Use the template in `references/resume-note-template.md` as the canonical structure.
- The orchestrator's first read on resume should be the resume note — make it accurate.

---

## 8. Forgetting that FP-check is static and verify is live

**Symptom:** FP-check subagents try to spin up the live instance and produce flaky verdicts ("couldn't reproduce" rejects real bugs); OR verify forks re-do FP-check analysis instead of running the curl.

**Prevention:**
- FP-check phase: STATIC ONLY. Source re-reads, exclusion-rule application, no live testing.
- Verify phase: LIVE ONLY (per finding, in a fork). Run the PoC, capture HTTP, judge by reproduction not by theory.
- The two are separate phases for a reason — preserve the separation.

---

## 9. Verify forks attempting to upload edits back to orchestrator state

**Symptom:** A verify fork tries to `UPDATE cba_findings SET verified='live-poc'` or modify `cba_fp_verdicts`. This causes race conditions when multiple forks run in parallel.

**Prevention:**
- Verify forks write **artifact files only** (`verify-<id>.md`). The orchestrator reads those in Phase 6.
- The verify workflow doc says this explicitly. Include the rule in every verify-fork prompt.

---

## 10. Deploy phase glossed over → audit findings can't be validated

**Symptom:** Audit produces 47 findings but only 2 are live-verified because the live instance wasn't set up early enough.

**Prevention:**
- Make `/codebase-audit:deploy` a mandatory step before `/codebase-audit:audit`, not optional.
- Even if the deep audit subagents don't all use the live instance, having it ready means verify forks can do their job later.
- If the project has no clear deploy path, document that fact in the live-instance note as "infra-blocked, all findings will be source-only" — and the report sets expectations accordingly.

---

## How to add a new lesson

When you encounter a new failure mode:
1. Add a numbered section here with **Observed in / Symptom / Root cause / Prevention**.
2. If the lesson should be surfaced in SKILL.md's "Lessons Learned" summary, add a one-line entry there too.
3. If a sub-workflow can be hardened to prevent the failure mode automatically, edit that workflow file too.
