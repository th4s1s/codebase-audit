---
description: "Codebase audit — Phase 5: per-finding live PoC (run inside a forked conversation)."
argument-hint: "<finding IDs, comma-separated, e.g. G1-F1,G1-F2>"
---

Run the **verify** phase of the codebase-audit skill.

Argument: $ARGUMENTS

Read @__SKILL_DIR__/SKILL.md and the current resume note at `/memories/session/<project>-audit-resume.md` (if present), then execute @__SKILL_DIR__/workflows/verify.md.

Hard rules:
- This fork MUST NOT modify SQL state (no inserts/updates to `audit.db`)
- Back up every config file before editing; verify restore at end
- Re-read configs from disk before editing
- Write one `artifacts/verify-<finding-id>.md` per finding (CONFIRMED / REFUTED / INCONCLUSIVE)
- Return a summary table to the orchestrator

Stop at the user gate before the next phase.
