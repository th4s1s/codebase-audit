---
mode: 'agent'
description: 'Codebase audit — pass a phase (recon | deploy | audit | fpcheck | verify | report) or leave blank for full pipeline.'
---

Run the **codebase-audit** skill.

User-provided argument (may be empty): **${input:phase:full — or one of: recon, deploy, audit, fpcheck, verify, report}**

Read [SKILL.md](../SKILL.md), then route based on the argument:

| Argument | Action |
|---|---|
| `recon` (or `1`) | Execute [workflows/recon.md](../workflows/recon.md) and stop at the user gate. |
| `deploy` (or `2`) | Execute [workflows/deploy.md](../workflows/deploy.md) and stop at the user gate. |
| `audit` (or `3`) | Execute [workflows/audit.md](../workflows/audit.md) and stop at the user gate. |
| `fpcheck` (or `4`) | Execute [workflows/fpcheck.md](../workflows/fpcheck.md) and stop at the user gate. |
| `verify` (or `5`) | Execute [workflows/verify.md](../workflows/verify.md). **This phase MUST run in a forked conversation** — if you are not in a fork, tell the user to fork the conversation first and then re-run. |
| `report` (or `6`) | Execute [workflows/report.md](../workflows/report.md) and stop at the user gate before disclosure. |
| `full`, empty, or anything else | Run the full pipeline: recon → deploy → audit → fpcheck → (instruct user to open forks for verify) → report. Honor every user gate between phases. |

Before executing any phase, re-read the resume note at `/memories/session/<project>-audit-resume.md` (if present) and the live-instance note at `/memories/repo/<project>-live-instance.md` (if present) to orient.

Follow every Essential Principle and Rationalization-to-Reject in SKILL.md. Use **`general-purpose`** subagents for any write-needed parallel work — never `Explore`.
