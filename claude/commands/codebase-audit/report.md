---
description: "Codebase audit — Phase 6: stitch verify artifacts into final report + disclosure summary."
argument-hint: "[optional: severity floor or notes]"
---

Run the **report** phase of the codebase-audit skill.

Optional user note: $ARGUMENTS

Read @SKILL.md, the resume note, and inventory every `artifacts/verify-*.md`. Then execute @workflows/report.md.

Outputs expected:
- `reports/audit-<TS>/report.md` — consolidated, REFUTED dropped, re-ranked by final severity
- `reports/audit-<TS>/disclosure-summary.md` — ≤2 pages, vendor-facing

Stop at the user gate before any disclosure action.
