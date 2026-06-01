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
- After the PoCs, adversarially review each CONFIRMED finding with fresh subagents — neutral prompt (code + claim + PoC only), checking real-bug / valid-PoC / intentionally-vulnerable-or-test-code; reconcile and record in the artifact (verify.md Step 2)
- Return a summary table to the orchestrator

Stop at the user gate before the next phase.
