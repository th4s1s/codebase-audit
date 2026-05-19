---
mode: 'agent'
description: 'Codebase audit — Phase 4: static-only false-positive review of findings.'
---

Run the **fpcheck** phase of the codebase-audit skill.

Read [SKILL.md](../SKILL.md) and the resume note, then execute [workflows/fpcheck.md](../workflows/fpcheck.md).

Key reminders:
- **STATIC ONLY** — do not touch the live instance; live verification is a separate phase
- Batch 8–12 findings per subagent; pre-flag dedup pairs
- Apply 18 Hard Exclusions, 10 Precedent rules, Marginal Gain Test
- Sanity-check: verdict count must equal finding count

Outputs expected:
- `cba_fp_verdicts` populated; per-batch `artifacts/phase5-batch<X>.md`
- Resume note updated with a fork plan for the verify phase

Stop at the user gate; user opens forks for verify.
