---
mode: 'agent'
description: 'Codebase audit — Phase 2: deploy live instance and document it in repo memory.'
---

Run the **deploy** phase of the codebase-audit skill.

Read [SKILL.md](../SKILL.md), the current resume note at `/memories/session/<project>-audit-resume.md`, then execute [workflows/deploy.md](../workflows/deploy.md).

Outputs expected:
- Live instance running and reachable
- Endpoints + bind-mounted configs documented in `/memories/repo/<project>-live-instance.md`
- Resume note updated

Stop at the user gate before audit.
