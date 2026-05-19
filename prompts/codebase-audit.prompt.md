---
mode: 'agent'
description: 'Run a full multi-phase security audit (recon → deploy → audit → fpcheck → verify → report).'
---

Run the **full codebase-audit pipeline** on the current workspace.

Read [SKILL.md](../SKILL.md), then execute the phases in order, gating on user approval between each:

1. [workflows/recon.md](../workflows/recon.md) — source detection, feature mapping, resume note
2. [workflows/deploy.md](../workflows/deploy.md) — deploy live instance, write live-instance note
3. [workflows/audit.md](../workflows/audit.md) — CVE ingest, patch-bypass mining, parallel deep audit
4. [workflows/fpcheck.md](../workflows/fpcheck.md) — static false-positive review
5. [workflows/verify.md](../workflows/verify.md) — per-finding live PoC (forked conversations)
6. [workflows/report.md](../workflows/report.md) — consolidated report + disclosure summary

Follow every Essential Principle and Rationalization-to-Reject in SKILL.md. Honor user gates between phases.
