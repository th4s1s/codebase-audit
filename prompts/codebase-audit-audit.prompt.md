---
mode: 'agent'
description: 'Codebase audit — Phase 3: CVE ingest, patch-bypass mining, parallel deep audit.'
---

Run the **audit** phase of the codebase-audit skill.

Read [SKILL.md](../SKILL.md), the resume note, and the live-instance note. Then execute [workflows/audit.md](../workflows/audit.md).

Key reminders:
- Use `general-purpose` subagents, NOT `Explore` (Explore is read-only — will silently fail)
- Patch-bypass mining is the highest-value step — for each CVE, fetch the patch diff and check sibling files for the same root cause untouched
- One subagent per feature group; handle stalls by re-spawning

Outputs expected:
- `cba_known_findings` + `cba_findings` populated; per-group `artifacts/G<n>-findings.md`
- Resume note rewritten

Stop at the user gate before fpcheck.
