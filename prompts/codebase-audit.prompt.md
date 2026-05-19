---
mode: 'agent'
description: 'Codebase audit — pass a phase (recon | deploy | audit | fpcheck | verify | report) or leave blank for full pipeline.'
---

Run the **codebase-audit** skill installed at `__SKILL_DIR__`.

User-provided argument (may be empty): **${input:phase:full — or one of: recon, deploy, audit, fpcheck, verify, report}**

First read [__SKILL_DIR__/SKILL.md](__SKILL_DIR__/SKILL.md) for context and routing rules. Then read the matching workflow file from `__SKILL_DIR__/workflows/`:

| Argument | Workflow to execute |
|---|---|
| `recon` | [__SKILL_DIR__/workflows/recon.md](__SKILL_DIR__/workflows/recon.md) |
| `deploy` | [__SKILL_DIR__/workflows/deploy.md](__SKILL_DIR__/workflows/deploy.md) |
| `audit` | [__SKILL_DIR__/workflows/audit.md](__SKILL_DIR__/workflows/audit.md) |
| `fpcheck` | [__SKILL_DIR__/workflows/fpcheck.md](__SKILL_DIR__/workflows/fpcheck.md) |
| `verify` | [__SKILL_DIR__/workflows/verify.md](__SKILL_DIR__/workflows/verify.md) — **must run in a forked conversation** |
| `report` | [__SKILL_DIR__/workflows/report.md](__SKILL_DIR__/workflows/report.md) |
| `full` / empty / other | Full pipeline: recon → deploy → audit → fpcheck → (instruct user to fork for verify) → report, gating between phases |

Before executing any phase, re-read the resume note at `/memories/session/<project>-audit-resume.md` and the live-instance note at `/memories/repo/<project>-live-instance.md` (if present) to orient.

Follow every Essential Principle and Rationalization-to-Reject in SKILL.md. Use **`general-purpose`** subagents for any write-needed parallel work — never `Explore`.
