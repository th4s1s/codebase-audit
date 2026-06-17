---
name: codebase-audit
description: >-
  Runs a structured multi-phase security audit of an application using parallel
  subagents for recon, live-instance deployment, deep vulnerability hunting,
  false-positive verification, live PoC verification, and final reporting.
  Supports source code, IDA Pro MCP binary reverse engineering, or both. Use for
  full app/repo audits, bug bounty audits, patch-bypass research, and automated
  source-only scans. Triggers on 'audit this app', 'security audit this
  codebase', 'find vulnerabilities in this project', 'run the codebase audit',
  '$codebase-audit', '/codebase-audit', phase requests like recon/deploy/audit/
  fpcheck/verify/report/source, and 'automated source-only audit'. NOT for
  single-file review, quick pattern scans, PR diff review, threat modeling only,
  or post-audit cleanup.
---

# Codebase Audit — Parallel Feature-Mapped Vulnerability Hunting

A battle-tested methodology for auditing applications at scale. The workflow divides the target into feature groups, deploys a live instance, hunts vulnerabilities in parallel, eliminates false positives via static review, and verifies each survivor against the live instance via forked conversations.

## Essential Principles

1. **Source-agnostic**: Works with source directories, IDA Pro MCP, or both. Detection happens automatically in recon; user confirms.

2. **Parallel-first**: Feature mapping, deep audit, and FP-check each spawn subagents per group/batch. Per-finding verification spawns one fork per finding. Never serialize when work is independent.

3. **Memory-persistent across compactions**: Every major phase ends by **rewriting the audit resume note** (see `references/resume-note-template.md`). This single file lets the orchestrator survive arbitrary context compactions without losing state. SQLite (`audit.db`) holds the structured data; the resume note holds the working strategy.

4. **Manually compact between phases, never mid-phase**: Auto-compaction is unpredictable and frequently drops the exact reasoning/state the next phase needs (subagent outputs, dedup decisions, partial findings not yet flushed to SQL). At every user gate, **before saying "go" to the next phase**, run a manual compact (`/compact` in Claude Code or Codex CLI, the Compact action in Copilot Chat). The phase you just finished has already written its artifacts to disk + a fresh resume note, so compacting at that boundary is lossless; compacting mid-phase is not.

5. **Subagent capability matters**: any subagent that must write artifacts, run SQL inserts, or hit the live instance needs a **writable** agent — never a read-only one (which silently produces no files/SQL). See the *Cross-client tool mapping* for each client's writable agent (Claude/Copilot `general-purpose`, NOT read-only `Explore`; Codex `spawn_agent`). (Lesson learned the hard way — see `references/lessons-learned.md`.)

6. **Live verification is forked, not in-line**: After FP-check produces N true positives, each finding is verified in its **own forked conversation** so curl/HTTP noise never bloats the orchestrator context. Forks write `verify-<finding-id>.md` artifacts; the orchestrator stitches them into the final report. Each fork also **adversarially reviews** its findings with fresh, unbiased subagents (verify Step 2) before returning, so auditor bias and intentionally-vulnerable/test code are caught early.

7. **User gates control pacing**: User explicitly approves transitions between phases. Never auto-advance past a gate.

8. **FP-check is static-only**: FP-check subagents re-read source and apply 18 Hard Exclusions + 10 Precedent rules. They do NOT use the live instance — that is what verify forks are for. This separation prevents an "I couldn't reproduce it" handwave from killing a real source-level bug.

9. **Honest impact over inflated severity; PoC on the real build**: A finding is a vulnerability only when impact is demonstrated on the **real, unmodified** target via the **genuine attacker path with attacker-controlled inputs** — not a self-written harness, a sanitizer abort, or a debugger-injected condition (those prove a *defect*, not impact). Apply the attacker-advantage test first; if the stock-build outcome is unobservable or self-healing, it is Informational. Lead with the honest verdict and never defend an overstated severity under pushback. (See `references/lessons-learned.md` items 11–16.)

10. **Stay at the project root — never `cd` into the audit dir**: Keep the orchestrator's working directory at the **project root** for the entire audit. Reference the audit dir (`reports/audit-<ts>/`) and `audit.db` by their path — never `cd` into them. Two reasons: the resume note's resumption commands are relative to the project root, and — critically — **verify forks/branches inherit the orchestrator's current working directory**. Claude's resume picker groups sessions by that directory, so if the cwd has drifted into `reports/audit-<ts>/`, the forks are filed under a *different* project and disappear from the picker (resumable by id, but hard to find), and their relative artifact writes mis-resolve. **Open every fork from the project root.** (See `references/lessons-learned.md` item 17.)

## Sub-Command Router

The skill supports six phases (invoke them individually after the prior phase completes, or run the full pipeline), plus an automated **`source`** run that chains recon → audit → fpcheck → report unattended for source-only scans.

### Phase → workflow mapping

| Phase | Workflow file | Purpose | Entry condition | Output |
|---|---|---|---|---|
| `recon` | [workflows/recon.md](workflows/recon.md) | Source detection, reconnaissance, **parallel feature mapping**, write resume note | Fresh start (or new target) | `cba_feature_groups`, `cba_attack_surface`, `cba_security_observations` populated; `files/G<n>-mapping.md` per group; resume note ready for compact |
| `deploy` | [workflows/deploy.md](workflows/deploy.md) | Deploy live instance from source (Docker, build artifact, or local run); document in `/memories/repo/<project>-live-instance.md` | Recon done OR independent setup task | Live instance running; endpoints documented; live-instance note saved to repo memory |
| `audit` | [workflows/audit.md](workflows/audit.md) | Load prior CVEs/advisories (find patch-bypass surfaces), **parallel deep-audit subagents** per group, write resume note | Recon + deploy done | `cba_known_findings`, `cba_findings` populated; per-group `artifacts/G<n>-findings.md`; resume note updated |
| `fpcheck` | [workflows/fpcheck.md](workflows/fpcheck.md) | **Parallel FP-check subagents** apply Hard Exclusions / Precedent rules / Marginal Gain Test — **static review only**, no live testing; write resume note | Audit done | `cba_fp_verdicts` populated; per-batch `artifacts/phase5-batch<X>.md`; resume note updated |
| `verify` | [workflows/verify.md](workflows/verify.md) | **Runs in a forked conversation**, requires finding-ID list. Per-finding live-instance PoC, then **adversarial review by fresh subagents** (Step 2); writes `artifacts/verify-<finding-id>.md`. Refuses to run without IDs. | FP-check produced TPs; user has opened a fork and passed `<ids>` (or pasted the orchestrator's fork prompt). | One verify artifact per finding in scope; CONFIRMED / REFUTED / INCONCLUSIVE, each adversarially reviewed (bias / intentionally-vulnerable-code checks). |
| `report` | [workflows/report.md](workflows/report.md) | Runs in the orchestrator. **Step 1 ingests every `verify-<id>.md` from disk** and refuses to continue if any TP is missing an artifact (or explicit skip). Then writes consolidated `report.md` + vendor-facing `disclosure-summary.md`. | All verify forks finished (or explicitly skipped); orchestrator-side. | `report.md`, `disclosure-summary.md`, updated `cba_fp_verdicts.final_id`. |
| `source` | [workflows/source.md](workflows/source.md) | **Automated source-only run** (composite): chains recon → audit → fpcheck → report **unattended** — no deploy, no live instance, no verify, **no user gates**. For product teams scanning a codebase before release. CVE ingest best-effort. | Fresh start; source tree present; no human supervision wanted | `report.md` + `disclosure-summary.md` + `audit.db`; all findings `verified='source-only'` (not live-verified) |

**Full pipeline mode**: orchestrator runs recon → deploy → audit → fpcheck → user opens forks → report. Each transition is gated.

**Automated source-only mode**: the **`source`** run does the recon → audit → fpcheck → report chain **unattended and without a live instance** — every gate auto-proceeds, deploy and verify are skipped, and it ends by writing the report (see [workflows/source.md](workflows/source.md)).

### How phases are invoked per client

| Client | Full pipeline | Specific phase |
|---|---|---|
| **GitHub Copilot Chat** (VS Code) | `/codebase-audit` | `/codebase-audit recon` / `deploy` / `audit` / `fpcheck` / `verify <ids>` / `report` — Copilot does NOT support namespaced slash commands, so the phase is passed as a free-text argument after the slash command. |
| **Claude Code CLI** | `/codebase-audit` | `/codebase-audit:recon`, `/codebase-audit:deploy`, `/codebase-audit:audit`, `/codebase-audit:fpcheck`, `/codebase-audit:verify <ids>`, `/codebase-audit:report` |
| **OpenAI Codex CLI** | `$codebase-audit` | `$codebase-audit recon` / `deploy` / `audit` / `fpcheck` / `verify <ids>` / `report` — like Copilot, Codex has no namespaced slash commands, so the phase is passed as a free-text argument after the skill invocation. |
| **Free-text** (any) | "audit this app" | "run the codebase-audit recon phase" |

**Automated source-only run:** invoke the **`source`** command (Claude `/codebase-audit:source`; Copilot `/codebase-audit source`; Codex `$codebase-audit source`; or free-text "run the automated source-only audit") to chain recon → audit → fpcheck → report **unattended** with no live instance — see [workflows/source.md](workflows/source.md).

### Cross-client tool mapping

The workflows name **capabilities**, not one client's tool IDs. Use your client's equivalent:

| Capability | Copilot Chat | Claude Code CLI | OpenAI Codex CLI |
|---|---|---|---|
| Ask the user to choose | `vscode_askQuestions` | `AskUserQuestion` | present the options in text and wait for the reply |
| Spawn a subagent | `runSubagent` (or `task`) | `Task` | `spawn_agent` (+ `wait_agent` / `close_agent`) |
| Run a command in a subagent | `execution_subagent` | a `general-purpose` `Task` | `spawn_agent` |
| **Writable** subagent (writes files/SQL) vs read-only | `general-purpose` vs read-only `explore` | `general-purpose` vs read-only `Explore` | `spawn_agent` (writable by default — no read-only type) |
| Read / search files | `view` / `grep` / `glob` | `Read` / `Grep` / `Glob` | your native file tools |
| Semantic / codebase search | `semantic_search` | agentic search (`Grep`/`Glob` + exploration) | native code search |
| Manual context compaction | Compact action | `/compact` | `/compact` |

**Two rules hold on every client:** (1) any subagent that writes artifacts, runs SQL inserts, or hits the live instance MUST be a **writable** agent — a read-only agent silently produces nothing; (2) use the **strongest model your client offers** (e.g. the latest Claude Opus on Claude/Copilot; the default high-capability model on Codex).

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

The automated **`source`** run uses the same diagram **minus deploy and the verify forks**: recon → audit → fpcheck → report, unattended (see [workflows/source.md](workflows/source.md)).

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
| recon (mapping) | **writable** subagent (writes SQL/artifacts — see *Cross-client tool mapping*) | strongest available (e.g. Claude Opus 4.5+) | 1 per group | Map features → code |
| audit | **writable** subagent | strongest available | 1 per group | Deep adversarial audit |
| fpcheck | **writable** subagent | strongest available | 1 per batch of 8-12 findings | Static FP review |
| verify | n/a — runs in a forked **root** conversation | — | 1 fork per ~5-8 findings | Live PoC against deployed instance |
| verify (review) | **writable** subagent, **fresh** (no fork/audit context) | strongest available | 2-3 per CONFIRMED finding | Adversarial review of each finding/PoC — neutral prompt; real-bug / valid-PoC / intentionally-vulnerable-code lenses (optional interactive multi-agent debate where the client supports it, e.g. a Claude agent-team) |

## Rationalizations to Reject

| Rationalization | Required Action |
|---|---|
| "The code looks clean, skip deep analysis" | Analyze every entry point. Surface appearance is not security. |
| "I found enough bugs, stop early" | Complete all groups. Coverage gaps hide the worst bugs. |
| "This group is just config, skip it" | Config bugs (SSRF, injection, supply chain) are often the most critical findings. |
| "Admin-only feature isn't interesting" | Apply Marginal Gain Test — admin → cross-tenant, supply chain, persistence are all valid. |
| "Static analysis is enough, skip live verify" | Live PoC is mandatory for vendor credibility. Use a fork. |
| "Use a read-only / Explore agent for the subagents" | Use a **writable** subagent (Claude/Copilot `general-purpose`, NOT read-only `Explore`; Codex `spawn_agent`) — a read-only agent cannot write SQL/artifacts. |
| "Verify in the main conversation to save tokens" | Forks isolate failure and noise. Always fork for verification. |
| "Skip the resume note this phase, it's fine" | Compaction is unpredictable. Always rewrite the resume note at phase end. |
| "Context is still big enough, don't bother compacting yet" | Manual compact at every gate. Letting auto-compaction fire mid-phase frequently drops the exact state the next phase needs. The cost of compacting too early is zero; the cost of compacting too late is a corrupted audit. |
| "My harness / ASan triggers it — that's a PoC" | A self-written harness, sanitizer abort, or debugger-injected condition proves a *defect*, not impact. Reproduce on the **stock production build** via the genuine attacker path with attacker-controlled inputs only. If the stock outcome is unobservable → Informational. |
| "Just patch the target so the bug fires" | For trust-boundary bugs, patch the **attacker** component and keep the **victim** binary 100% stock (verify via `/proc/<pid>/exe`). Modifying the victim proves nothing. |
| "It obviously hangs / crashes — no need to measure" | Quantify on the real binary: `top -bH` + `/proc/.../stat` for a spin, exit/signal for a crash, N-trial counts. 100% CPU ≠ a blocked wait. Pair with an honest-input control run. |
| "Call it an infinite loop / say it always crashes" | Use precise, measured wording ("effectively unbounded, expected N iters"; "observed M/N"). Overstatement gets bug-bounty submissions rejected — adversarially verify every claim before shipping. |

## Lessons Learned (FROM REAL AUDITS — READ BEFORE STARTING)

See [references/lessons-learned.md](references/lessons-learned.md) for the full list. Key items:

1. **Never use a read-only agent for write-needed work** (Claude/Copilot `Explore`) — it silently produces no artifacts; use a writable subagent.
2. **Always back up live-instance config before PoC** (e.g., `cp .docker_compose/rules.json /tmp/rules.json.bak.fork-<X>`) and verify restore at end.
3. **User may hand-edit live-instance config between phases** — always re-read configs before edits.
4. **Patch-bypass class is gold** — when ingesting CVEs, look at the patch diff and check sibling files for the same root cause untouched. (Highest-severity findings in real audits come from this.)
5. **Operator-config "vulns" usually fail the Marginal Gain Test** — if the operator could already do X via documented config, finding a second way is not a CVE.
6. **Session memory drops** from subagents accumulate — clean them up after consolidating into `artifacts/`.
7. **PoC rigor** — reproduce impact on the real production-flag build via the genuine attacker path; a self-harness / sanitizer abort / debugger-injected condition proves a *defect*, not impact (downrate to Informational if the stock-build outcome is unobservable).
8. **Trust-boundary PoCs: patch the attacker, keep the victim stock** — for client↔server / server→client bugs, control the attacker's component (let its real serializer emit wire-correct bytes) and verify the victim is the unmodified binary (`readlink /proc/<pid>/exe`).
9. **DoS / hang / non-HTTP findings need OS-level proof + a control** — quantify with `top -bH` + `/proc/<pid>/task/<tid>/stat` (spin), exit code (crash), or RSS (memory); 100% CPU distinguishes a spin from a blocked wait; always pair with an honest-input control run.
10. **State outcomes precisely + adversarially verify the report** — "effectively unbounded (expected N iters)" not "infinite", "observed X" not "would X"; run an independent pass over citations / mechanism / severity before shipping.
11. **Live-instance footguns** — `kill -9` hung processes (they ignore SIGTERM and squat ports); persist ephemeral state before restarting between runs; flush state to disk before any cross-process handoff; lifecycle ops may need the sandbox disabled.
12. **Attacker-advantage test FIRST** — a node dropping a misbehaving peer, or a self-healing / operator-misconfig condition, is not a vuln; lead with the honest verdict.

## Workflow Entry

To begin, route to the appropriate workflow:

- "audit this app" or no specific sub-command → start with [workflows/recon.md](workflows/recon.md)
- A specific-phase invocation (per *How phases are invoked per client* — Claude `/codebase-audit:<phase>`, Copilot `/codebase-audit <phase>`, Codex `$codebase-audit <phase>`) → load `workflows/<phase>.md` and execute
- The `source` run / "automated source-only audit" → load [workflows/source.md](workflows/source.md) and run recon → audit → fpcheck → report unattended (no deploy, no live instance, no verify, no user gates)

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

**For the automated `source` run:** the *live instance* (line 2) and *verify artifact* (line 5) criteria do **not** apply — deploy and verify are skipped. Instead: every TRUE_POSITIVE is `verified='source-only'`; `report.md` + `disclosure-summary.md` carry the not-live-verified caveat; and the final severity-counts summary was printed.
