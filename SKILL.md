---
name: codebase-audit
description: >-
  Runs a structured multi-phase security audit of an application using parallel
  subagents for recon, live-instance deployment, deep vulnerability hunting,
  false-positive verification, and per-finding live PoC verification. Supports
  source code, IDA Pro MCP (binary reverse engineering), or both. Triggers on
  'audit this app', 'security audit this codebase', 'find vulnerabilities in
  this project', 'run the codebase audit', '/codebase-audit', or any phase
  reference like 'run the recon phase' / 'run the fpcheck phase'. On Claude
  Code CLI also triggers on '/codebase-audit:recon', '/codebase-audit:deploy',
  '/codebase-audit:audit', '/codebase-audit:fpcheck', '/codebase-audit:verify',
  '/codebase-audit:report' (Copilot Chat does not support namespaced slash
  commands — pass the phase as an argument to /codebase-audit instead).
  NOT for single-file review (use code-reviewer), quick scans (use semgrep),
  or differential review of a PR (use differential-review).
---

# Codebase Audit — Parallel Feature-Mapped Vulnerability Hunting

A battle-tested methodology for auditing applications at scale. The workflow divides the target into feature groups, deploys a live instance, hunts vulnerabilities in parallel, eliminates false positives via static review, and verifies each survivor against the live instance via forked conversations.

## Essential Principles

1. **Source-agnostic**: Works with source directories, IDA Pro MCP, or both. Detection happens automatically in recon; user confirms.

2. **Parallel-first**: Feature mapping, deep audit, and FP-check each spawn subagents per group/batch. Per-finding verification spawns one fork per finding. Never serialize when work is independent.

3. **Memory-persistent across compactions**: Every major phase ends by **rewriting the audit resume note** (see `references/resume-note-template.md`). This single file lets the orchestrator survive arbitrary context compactions without losing state. SQLite (`audit.db`) holds the structured data; the resume note holds the working strategy.

4. **Manually compact between phases, never mid-phase**: Auto-compaction is unpredictable and frequently drops the exact reasoning/state the next phase needs (subagent outputs, dedup decisions, partial findings not yet flushed to SQL). At every user gate, **before saying "go" to the next phase**, run a manual compact (`/compact` in Claude Code, the Compact action in Copilot Chat). The phase you just finished has already written its artifacts to disk + a fresh resume note, so compacting at that boundary is lossless; compacting mid-phase is not.

5. **Subagent agent type matters**: `Explore` agents are **read-only** — no terminal, no file writes. Use `general-purpose` for any subagent that must write artifacts, run SQL inserts, or hit the live instance. (Lesson learned the hard way — see `references/lessons-learned.md`.)

6. **Live verification is forked, not in-line**: After FP-check produces N true positives, each finding is verified in its **own forked conversation** so curl/HTTP noise never bloats the orchestrator context. Forks write `verify-<finding-id>.md` artifacts; the orchestrator stitches them into the final report.

7. **User gates control pacing**: User explicitly approves transitions between phases. Never auto-advance past a gate.

8. **FP-check is static-only**: FP-check subagents re-read source and apply 18 Hard Exclusions + 10 Precedent rules. They do NOT use the live instance — that is what verify forks are for. This separation prevents an "I couldn't reproduce it" handwave from killing a real source-level bug.

## Sub-Command Router

The skill supports six phases. User can invoke them individually after the prior phase is complete, or run the full pipeline.

### Phase → workflow mapping

| Phase | Workflow file | Purpose | Entry condition | Output |
|---|---|---|---|---|
| `recon` | [workflows/recon.md](workflows/recon.md) | Source detection, reconnaissance, **parallel feature mapping**, write resume note | Fresh start (or new target) | `cba_feature_groups`, `cba_attack_surface`, `cba_security_observations` populated; `files/G<n>-mapping.md` per group; resume note ready for compact |
| `deploy` | [workflows/deploy.md](workflows/deploy.md) | Deploy live instance from source (Docker, build artifact, or local run); document in `/memories/repo/<project>-live-instance.md` | Recon done OR independent setup task | Live instance running; endpoints documented; live-instance note saved to repo memory |
| `audit` | [workflows/audit.md](workflows/audit.md) | Load prior CVEs/advisories (find patch-bypass surfaces), **parallel deep-audit subagents** per group, write resume note | Recon + deploy done | `cba_known_findings`, `cba_findings` populated; per-group `artifacts/G<n>-findings.md`; resume note updated |
| `fpcheck` | [workflows/fpcheck.md](workflows/fpcheck.md) | **Parallel FP-check subagents** apply Hard Exclusions / Precedent rules / Marginal Gain Test — **static review only**, no live testing; write resume note | Audit done | `cba_fp_verdicts` populated; per-batch `artifacts/phase5-batch<X>.md`; resume note updated |
| `verify` | [workflows/verify.md](workflows/verify.md) | **Two modes.** In a fork (`/codebase-audit:verify <ids>`): per-finding live-instance PoC; writes `artifacts/verify-<finding-id>.md`. In the orchestrator (`/codebase-audit:verify` with no IDs): scans existing artifacts, reconciles against TPs, prints a status table, updates resume note — no PoCs run. | FP-check produced TPs. Fork mode: user has opened a fork. Orchestrator-ingest mode: at least one fork has finished. | Fork: one verify artifact per finding in scope. Orchestrator-ingest: status table (CONFIRMED/REFUTED/INCONCLUSIVE/MISSING) + updated resume note. |
| `report` | [workflows/report.md](workflows/report.md) | Stitch all verify artifacts + FP verdicts into consolidated `report.md` and `disclosure-summary.md` | All verify forks finished | Final report under `reports/audit-<timestamp>/` |

**Full pipeline mode**: orchestrator runs recon → deploy → audit → fpcheck → user opens forks → report. Each transition is gated.

### How phases are invoked per client

| Client | Full pipeline | Specific phase |
|---|---|---|
| **GitHub Copilot Chat** (VS Code) | `/codebase-audit` (leave phase prompt blank) | `/codebase-audit` then answer with `recon` / `deploy` / `audit` / `fpcheck` / `verify` / `report` — Copilot does NOT support namespaced slash commands, so phase is an argument |
| **Claude Code CLI** | `/codebase-audit` | `/codebase-audit:recon`, `/codebase-audit:deploy`, `/codebase-audit:audit`, `/codebase-audit:fpcheck`, `/codebase-audit:verify <ids>`, `/codebase-audit:report` |
| **Free-text** (either) | "audit this app" | "run the codebase-audit recon phase" |

## When to Use

- Full security audit of an application targeting CVE/GHSA disclosure
- Bug bounty hunting with systematic coverage
- Auditing a compiled application via IDA Pro MCP
- Patch-bypass research on a project with existing CVEs
- Re-auditing after major changes (reuse mappings as starting point)

## When NOT to Use

- Single-file or single-function code review → `code-reviewer`
- Quick pattern-based scan → `semgrep`
- Reviewing a specific PR diff → `differential-review`
- Threat modeling without code verification → `security-threat-model`
- Post-audit FP verification only → `fp-check-pivot` directly

## Architecture

```
                                  ┌─ resume note ←─ rewritten each phase
                                  │
recon ──► deploy ──► audit ──► fpcheck ──► [open N forks] ──► report
  │         │         │           │              │             │
  │         │         │           │              ▼             │
  │         │         │           │       verify-<id>.md       │
  │         │         │           │       (per finding)        │
  └─────────┴─────────┴───────────┴───────────────┴─────────────┘
                       SQLite audit.db (single source of truth)
                       reports/audit-<timestamp>/artifacts/*.md
```

## Quick Reference

### SQL Tables (in `reports/audit-<timestamp>/audit.db`)

| Table | Purpose | Created In |
|---|---|---|
| `cba_sources` | Source configuration (path, IDA, both) | recon |
| `cba_feature_groups` | Group definitions + status | recon |
| `cba_attack_surface` | Endpoints/entry points per group | recon |
| `cba_security_observations` | Pre-audit observations from mapping | recon |
| `cba_known_findings` | Prior CVEs/advisories + patch-bypass intel | audit |
| `cba_findings` | Candidate findings from deep audit (col `artifact_path`) | audit |
| `cba_fp_verdicts` | FP-check verdicts | fpcheck |

### Artifact Layout

```
reports/audit-<YYYYMMDD-HHMMSS>/
├── audit.db                        # SQLite source of truth
├── files/
│   ├── G<n>-mapping.md             # per-group feature mapping (recon)
│   └── known-findings.md           # advisories + patch-bypass surface (audit)
├── artifacts/
│   ├── G<n>-findings.md            # per-group deep-audit output (audit)
│   ├── phase5-batch<X>-*.md        # per-batch FP-check verdicts (fpcheck)
│   └── verify-<finding-id>.md      # per-finding live PoC (verify)
├── report.md                       # consolidated final report (report)
└── disclosure-summary.md           # short vendor-facing summary (report)
```

### Resume Note + Live-Instance Note

| File | Scope | Template | Purpose |
|---|---|---|---|
| `/memories/session/<project>-audit-resume.md` | Session | [references/resume-note-template.md](references/resume-note-template.md) | Survive context compactions; rewritten after every phase |
| `/memories/repo/<project>-live-instance.md` | Repo (workspace) | [references/live-instance-template.md](references/live-instance-template.md) | Persistent deployment info; survives across sessions |

### Subagent Configuration

| Phase | Agent type | Model | Count | Task |
|---|---|---|---|---|
| recon (mapping) | `general-purpose` (NOT Explore — needs to write SQL/artifacts) | claude opus 4.5+ | 1 per group | Map features → code |
| audit | `general-purpose` | claude opus 4.5+ | 1 per group | Deep adversarial audit |
| fpcheck | `general-purpose` | claude opus 4.5+ | 1 per batch of 8-12 findings | Static FP review |
| verify | n/a — runs in a forked **root** conversation | — | 1 fork per ~5-8 findings | Live PoC against deployed instance |

## Rationalizations to Reject

| Rationalization | Required Action |
|---|---|
| "The code looks clean, skip deep analysis" | Analyze every entry point. Surface appearance is not security. |
| "I found enough bugs, stop early" | Complete all groups. Coverage gaps hide the worst bugs. |
| "This group is just config, skip it" | Config bugs (SSRF, injection, supply chain) are often the most critical findings. |
| "Admin-only feature isn't interesting" | Apply Marginal Gain Test — admin → cross-tenant, supply chain, persistence are all valid. |
| "Static analysis is enough, skip live verify" | Live PoC is mandatory for vendor credibility. Use a fork. |
| "Use Explore agent for the subagents" | Use **general-purpose** — Explore is read-only and cannot write SQL/artifacts. |
| "Verify in the main conversation to save tokens" | Forks isolate failure and noise. Always fork for verification. |
| "Skip the resume note this phase, it's fine" | Compaction is unpredictable. Always rewrite the resume note at phase end. |
| "Context is still big enough, don't bother compacting yet" | Manual compact at every gate. Letting auto-compaction fire mid-phase frequently drops the exact state the next phase needs. The cost of compacting too early is zero; the cost of compacting too late is a corrupted audit. |

## Lessons Learned (FROM REAL AUDITS — READ BEFORE STARTING)

See [references/lessons-learned.md](references/lessons-learned.md) for the full list. Key items:

1. **Never use `Explore` agent for write-needed work** — silently produces no artifacts.
2. **Always back up live-instance config before PoC** (e.g., `cp .docker_compose/rules.json /tmp/rules.json.bak.fork-<X>`) and verify restore at end.
3. **User may hand-edit live-instance config between phases** — always re-read configs before edits.
4. **Patch-bypass class is gold** — when ingesting CVEs, look at the patch diff and check sibling files for the same root cause untouched. (Highest-severity findings in real audits come from this.)
5. **Operator-config "vulns" usually fail the Marginal Gain Test** — if the operator could already do X via documented config, finding a second way is not a CVE.
6. **Session memory drops** from subagents accumulate — clean them up after consolidating into `artifacts/`.

## Workflow Entry

To begin, route to the appropriate workflow:

- "audit this app" or no specific sub-command → start with [workflows/recon.md](workflows/recon.md)
- `/codebase-audit:<phase>` → load `workflows/<phase>.md` and execute

## Phase Reference Index (technical details for sub-workflows)

| File | Content |
|---|---|
| [references/phase0-source-detection.md](references/phase0-source-detection.md) | Source detection logic, IDA Pro MCP probing, user prompts |
| [references/phase2-feature-mapping.md](references/phase2-feature-mapping.md) | Feature group taxonomy, subagent prompt, mapping format |
| [references/phase4-deep-audit.md](references/phase4-deep-audit.md) | Deep audit subagent prompt, finding schema, dedup |
| [references/phase5-fp-check.md](references/phase5-fp-check.md) | Batching strategy, FP rules, verdict schema |
| [references/phase6-report.md](references/phase6-report.md) | Report template, severity calibration |
| [references/resume-note-template.md](references/resume-note-template.md) | Standard resume-note format for compact survival |
| [references/live-instance-template.md](references/live-instance-template.md) | Standard live-instance doc format |
| [references/lessons-learned.md](references/lessons-learned.md) | Pitfalls observed in real audits |

## Success Criteria

- [ ] All feature groups have mappings in SQL + `files/G<n>-mapping.md`
- [ ] Live instance is running and documented in repo memory
- [ ] Every group was deep-audited; findings in `cba_findings` + `artifacts/G<n>-findings.md`
- [ ] Every finding has a FP-check verdict in `cba_fp_verdicts`
- [ ] Every TRUE_POSITIVE has either a `verify-<id>.md` artifact OR a documented "infra-blocked, source-only" reason
- [ ] Final `report.md` exists with verified findings only, ordered by severity
- [ ] Resume note exists and reflects current state (would let a fresh orchestrator resume cleanly)
