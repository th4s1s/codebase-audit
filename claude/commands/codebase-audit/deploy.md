---
description: "Codebase audit — Phase 2: deploy live instance and document in repo memory."
argument-hint: "[optional: focus or notes]"
---

Run the **deploy** phase of the codebase-audit skill.

Argument: $ARGUMENTS

Read @__SKILL_DIR__/SKILL.md and the current resume note at `/memories/session/<project>-audit-resume.md` (if present), then execute @__SKILL_DIR__/workflows/deploy.md.

Stop at the user gate before the next phase.
