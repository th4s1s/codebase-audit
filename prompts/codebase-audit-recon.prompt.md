---
mode: 'agent'
description: 'Codebase audit — Phase 1: source detection, reconnaissance, parallel feature mapping.'
---

Run the **recon** phase of the codebase-audit skill.

Read [SKILL.md](../SKILL.md) for context, then execute [workflows/recon.md](../workflows/recon.md) end-to-end.

Outputs expected:
- `reports/audit-<TS>/audit.db` with `cba_sources`, `cba_feature_groups`, `cba_attack_surface`, `cba_security_observations` populated
- `reports/audit-<TS>/files/G<n>-mapping.md` per group
- Resume note at `/memories/session/<project>-audit-resume.md` ready for compact

Stop at the user gate before deploy.
