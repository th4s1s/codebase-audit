---
description: "Codebase audit — report phase: write the per-finding vuln report in the verify fork (live), or one consolidated source-only report in the orchestrator."
argument-hint: "[optional: focus or notes]"
---

Run the **report** phase of the codebase-audit skill.

Argument: $ARGUMENTS

Read @__SKILL_DIR__/SKILL.md, then execute @__SKILL_DIR__/workflows/report.md.

- **Live (in a verify fork):** after verify + adversarial review, for a finding confirmed as a real vulnerability, write its own `reports/audit-<ts>/artifacts/<finding-id>-vuln-report.md` (Mode A) — lean format, real PoC inlined, runnable scripts staged in the project-root `poc/`.
- **Source-only (in the orchestrator):** write ONE consolidated `reports/audit-<ts>/report.md` (Mode B) — Steps to reproduce are reproduction guides, no live PoC or output.

Never reference a `reports/audit-<ts>/` path inside a report, and never perform external disclosure — that is the user's call.
