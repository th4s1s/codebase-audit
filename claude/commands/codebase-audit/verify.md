---
description: "Codebase audit — Phase 5: per-finding live PoC in a forked conversation."
argument-hint: "<finding IDs, comma-separated, e.g. G1-F1,G1-F2,G2-F5>"
---

Run the **verify** phase of the codebase-audit skill **in this forked conversation**.

Findings assigned to this fork: $ARGUMENTS

Read @SKILL.md, the resume note (`/memories/session/<project>-audit-resume.md`), and the live-instance note (`/memories/repo/<project>-live-instance.md`). Then execute @workflows/verify.md.

Hard rules:
- This fork MUST NOT modify SQL state (no inserts/updates to `audit.db`)
- Back up every config file before editing (`cp <file> /tmp/<file>.bak.fork-<X>`); verify restore at end
- Re-read configs from disk before editing — user may have hand-edited between phases
- Write one `artifacts/verify-<finding-id>.md` per finding with status CONFIRMED / REFUTED / INCONCLUSIVE
- Return a summary table to the orchestrator
