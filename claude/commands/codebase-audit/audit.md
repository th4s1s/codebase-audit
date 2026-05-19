---
description: "Codebase audit — Phase 3: CVE ingest, patch-bypass mining, parallel deep audit."
argument-hint: "[optional: focus or notes]"
---

Run the **audit** phase of the codebase-audit skill.

Argument: $ARGUMENTS

Read @__SKILL_DIR__/SKILL.md and the current resume note at `/memories/session/<project>-audit-resume.md` (if present), then execute @__SKILL_DIR__/workflows/audit.md.

Stop at the user gate before the next phase.
