---
description: "Codebase audit — Phase 4: static-only false-positive review of findings."
argument-hint: "[optional: focus or notes]"
---

Run the **fpcheck** phase of the codebase-audit skill.

Argument: $ARGUMENTS

Read @__SKILL_DIR__/SKILL.md and the current resume note at `/memories/session/<project>-audit-resume.md` (if present), then execute @__SKILL_DIR__/workflows/fpcheck.md.

Stop at the user gate before the next phase.
