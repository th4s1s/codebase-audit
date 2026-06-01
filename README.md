# codebase-audit

A structured, multi-phase security audit skill that drives parallel subagents through **recon → deploy → audit → fpcheck → verify → report**. Works with both **GitHub Copilot Chat** and **Claude Code CLI**.

Codifies hard-won lessons from actual audits (see [`references/lessons-learned.md`](references/lessons-learned.md)).

## What it does

```
recon ──► deploy ──► audit ──► fpcheck ──► [open N forks] ──► report
  │         │         │           │              │             │
  │         │         │           │              ▼             │
  │         │         │           │       verify-<id>.md       │
  └─────────┴─────────┴───────────┴──────────────┴─────────────┘
                       SQLite audit.db (single source of truth)
```

The pipeline produces a `reports/audit-<timestamp>/` directory containing a SQLite `audit.db` (single source of truth for findings, FP verdicts, attack surface), per-group/per-batch markdown artifacts, per-finding live-PoC artifacts, and a final consolidated `report.md` + `disclosure-summary.md` ready for vendor disclosure.

## The six workflows

Each phase is one file in [`workflows/`](workflows/). Run them individually (recommended on first use, so you understand what each does) or let the full pipeline run them in order with user gates between phases.

### 1. [`recon`](workflows/recon.md) — source detection + parallel feature mapping
Detects whether the target is a source tree, an IDA Pro MCP binary, or both, then enumerates the attack surface (HTTP routes, gRPC services, CLI entrypoints, message handlers, file/network sinks). Splits the codebase into **feature groups** (G1, G2, …) and spawns one `general-purpose` subagent per group to produce `files/G<n>-mapping.md`. Populates `cba_feature_groups`, `cba_attack_surface`, `cba_security_observations` in `audit.db`. Ends by writing the resume note to session memory.

### 2. [`deploy`](workflows/deploy.md) — live-instance setup
Makes sure a live instance is reachable so later phases have a reproduction target. Supports two modes:

- **`local-managed`** — we bring it up from the repo (Docker Compose, `make run`, etc.); we own the lifecycle, config files, and restart.
- **`external-provided`** — instance is already running somewhere we don't own (staging, customer VM, remote host); we have only HTTP-layer access, **no config edits, no restart**.

Either way, produces a single repo-memory artifact `/memories/repo/<project>-live-instance.md` documenting **deployment mode, capabilities, base URLs, the operator-supplied liveness command, off-limits surface**, and (for local-managed) bind-mounted configs and common ops. Every later phase and every verify fork reads this note first.

### 3. [`audit`](workflows/audit.md) — CVE ingest + patch-bypass mining + parallel deep audit
Fetches prior CVEs/GHSAs and their patch diffs (populating `cba_known_findings`). For each patch, checks sibling files for the **same root cause left untouched** — historically the highest-yield class of findings. Then spawns one `general-purpose` subagent per feature group to do adversarial source-level audit, populating `cba_findings` and writing per-group `artifacts/G<n>-findings.md`.

### 4. [`fpcheck`](workflows/fpcheck.md) — parallel static false-positive review
Batches the raw findings (~8–12 per batch) and spawns parallel subagents to apply the **18 Hard Exclusions + 10 Precedent rules + Marginal Gain Test**. Static review only — does not touch the live instance (that's verify's job; separating them keeps "I couldn't reproduce" handwaves from killing real source-level bugs). Populates `cba_fp_verdicts` and writes per-batch `artifacts/phase5-batch<X>.md`.

### 5. [`verify`](workflows/verify.md) — per-finding live PoC, **runs in a forked conversation**
For each true positive: build the PoC against the documented base URL, capture full HTTP request/response (`curl -i`), determine **CONFIRMED / REFUTED / INCONCLUSIVE**, and write `artifacts/verify-<finding-id>.md`. For `local-managed` instances, may back up + edit + restart configs (always restored at end). For `external-provided` instances, any finding requiring config changes or restart is marked **INCONCLUSIVE** with the required operator action — the fork must never substitute `127.0.0.1` for a remote host (would silently test the wrong service).

Each fork covers ~5–8 findings so HTTP noise doesn't bloat the orchestrator's context. The command **requires** a finding-ID list and refuses to run without one — artifact consolidation happens in [`report`](workflows/report.md), not here.

### 6. [`report`](workflows/report.md) — consolidated final report
**Step 1 ingests every `verify-<id>.md` from disk** and reconciles them against the TP list in `cba_fp_verdicts`. If any TP is missing an artifact (and the user hasn't explicitly skipped it), the workflow **stops at a user gate** and prints a ready-to-paste fork prompt for the missing IDs — you can't accidentally write a report with un-verified TPs. Once the inventory is complete, it stitches everything into:
- `report.md` — full audit report with verified findings ordered by severity
- `disclosure-summary.md` — short vendor-facing summary suitable for an advisory

Includes a coverage matrix (every group, every CVE, every finding) and a section listing INCONCLUSIVE findings with the required operator action.

## Typical audit walkthrough

1. **Open the target project's workspace** in VS Code (or `cd` into it for Claude CLI).
2. **Start with recon**:
   - Copilot: `/codebase-audit` → type `recon`
   - Claude: `/codebase-audit:recon`

   The orchestrator detects source/IDA, proposes a feature-group split, asks you to confirm, then spawns mapping subagents in parallel. Output: `files/G<n>-mapping.md`, populated SQL tables, resume note.

3. **Deploy** (`/codebase-audit:deploy` or answer `deploy`).
   Tell the orchestrator whether the instance is `local-managed` or `external-provided`. For external, hand it the base URLs, sample auth tokens, off-limits surface, and the exact liveness command the operator considers authoritative. Output: `/memories/repo/<project>-live-instance.md`.

4. **Audit** (`/codebase-audit:audit` or `audit`).
   Ingests CVEs, mines patch-bypass surfaces, then spawns one deep-audit subagent per group in parallel. Reviews each `artifacts/G<n>-findings.md` as it lands. Output: populated `cba_findings`, per-group artifacts.

5. **FP-check** (`/codebase-audit:fpcheck` or `fpcheck`).
   Batches findings and spawns FP-review subagents. Output: `cba_fp_verdicts` and per-batch artifacts. The orchestrator surfaces the TP-only list and asks you to open verify forks.

6. **Verify** — open one forked chat per ~5–8 findings.
   In each fork: `/codebase-audit:verify G1-F1,G1-F2,G2-F5` (or paste the orchestrator's fork-prompt into Copilot Chat with `verify` as the phase). The fork runs PoCs and writes `verify-<id>.md` artifacts directly to `reports/audit-<timestamp>/artifacts/`. **You don't need to paste anything back to the orchestrator.** The verify command refuses to run without IDs — there is no "orchestrator verify" mode.

7. **Report** — once all forks have written their artifacts, run `/codebase-audit:report` on the orchestrator. Its first step ingests every `verify-<id>.md` from disk, reconciles against the TP list, and **refuses to continue if any TP is missing an artifact** (it will surface the missing IDs and offer a ready-to-paste fork prompt). When the inventory is complete, it writes `report.md` + `disclosure-summary.md` and stops at a user gate before any disclosure.

### Checking verify progress mid-flight

There is no dedicated "verify status" command — just ask the orchestrator in plain English, e.g.:

> *"How many verify forks have finished? Which TPs still need a fork?"*

The orchestrator will `ls reports/audit-*/artifacts/verify-*.md`, query the TPs from `cba_fp_verdicts`, and answer with a status table. If you'd rather get the same answer as a hard gate, just run `/codebase-audit:report` — it will print the MISSING list and stop before doing any work if any TP is unverified.

7. **Report** (`/codebase-audit:report` or `report`).
   Stitches everything into `report.md` + `disclosure-summary.md`. Done.

At any point, context compaction is recoverable: every phase rewrites a resume note in `/memories/session/<project>-audit-resume.md`. A fresh orchestrator instance can read it and pick up exactly where the previous one left off.

### Manually compact between phases

**At every user gate, before saying "go" to the next phase, run a manual compact** (`/compact` in Claude Code CLI; the Compact action in Copilot Chat). The phase you just finished has already written its artifacts to disk and refreshed the resume note, so compacting at that boundary is lossless. Letting auto-compaction fire mid-phase is the most common cause of corrupted audits — it silently drops subagent outputs, dedup decisions, and partial findings that haven't been flushed to SQL yet. Compacting early costs nothing; compacting late costs the phase.

## Install

```bash
git clone https://github.com/th4s1s/codebase-audit.git
cd codebase-audit
./install.sh                # install for both clients
# or:
./install.sh copilot        # Copilot Chat only
./install.sh claude         # Claude Code CLI only
./install.sh --insiders     # use VS Code Insiders paths
./install.sh --uninstall    # remove selected clients' launchers AND skill dirs
```

### Where things go

Each client gets its **own self-contained copy** of the skill — installing one does not touch the other.

| Client | Skill content (`SKILL.md` + `workflows/` + `references/`) | Launcher(s) |
|---|---|---|
| **Copilot Chat** | `~/.copilot/skills/codebase-audit/` | _none_ — `SKILL.md` is auto-registered as `/codebase-audit` |
| **Claude Code CLI** | `~/.claude/skills/codebase-audit/` *(Claude auto-discovers via description triggers)* | `~/.claude/commands/codebase-audit.md` and `~/.claude/commands/codebase-audit/*.md` |

### How the Claude launchers find the skill

Claude launcher files live in [`claude/commands/`](claude/commands/) as templates containing the literal string `__SKILL_DIR__`. `install.sh` `sed`-substitutes it with the per-client skill dir on copy, so the launchers always point at `~/.claude/skills/codebase-audit/...`.

You can `./install.sh claude` on a machine that has no VS Code, and nothing ever touches `~/.copilot/`.

### Special case: cloning directly into an install dir

If you cloned the repo into one of the per-client skill dirs (e.g. directly into `~/.copilot/skills/codebase-audit/`), the installer detects that and skips the skill-file copy for that target — there's nothing to copy onto itself. The launcher install still happens. To get the skill content into the **other** client's dir, run `./install.sh` with both targets (default) or just that target.

## Usage

### GitHub Copilot Chat (VS Code)

Copilot Chat does **not** support namespaced sub-commands (`/foo:bar`) — it only autocompletes top-level slash commands from prompt files. So there is **one** slash command, and you specify the phase as an argument.

After reloading the window, type:

```
/codebase-audit
```

Copilot will prompt you for a phase. Accepted values:

| Argument | Phase |
|---|---|
| `recon` | source detection + feature mapping |
| `deploy` | live instance deployment |
| `audit` | CVE ingest + patch-bypass mining + deep audit |
| `fpcheck` | static false-positive review |
| `verify` | per-finding live PoC (run inside a forked chat) |
| `report` | consolidated report + disclosure summary |
| *(blank or `full`)* | run all phases in order, gating between each |

You can also type the phase inline (`/codebase-audit audit`) or trigger by free-text phrase (*"audit this app"*, *"find vulnerabilities in this project"*).

### Claude Code CLI

Claude Code natively supports namespaced sub-commands via subdirectories under `~/.claude/commands/`. All of these autocomplete:

| Slash command | Phase |
|---|---|
| `/codebase-audit` | full pipeline |
| `/codebase-audit:recon` | source detection + feature mapping |
| `/codebase-audit:deploy` | live instance deployment |
| `/codebase-audit:audit` | CVE ingest + patch-bypass mining + deep audit |
| `/codebase-audit:fpcheck` | static false-positive review |
| `/codebase-audit:verify G1-F1,G1-F2,G2-F5` | per-finding live PoC (run in a forked session) |
| `/codebase-audit:report` | consolidated report + disclosure summary |

Claude also auto-loads the skill from `~/.claude/skills/codebase-audit/SKILL.md` based on description triggers (*"audit this app"*, *"security audit this codebase"*), so the slash commands are optional.

All sub-commands accept `$ARGUMENTS` for optional notes (`/codebase-audit:audit focus on G3`).

### Differences at a glance

| Aspect | Copilot Chat | Claude Code CLI |
|---|---|---|
| Slash-command surface | One: `/codebase-audit` (phase as argument) | Seven: `/codebase-audit[:phase]` |
| Sub-command autocomplete | ❌ not supported | ✅ via `commands/<name>/<sub>.md` |
| Skill auto-load by description | ✅ via user-level skills index | ✅ via `~/.claude/skills/<name>/SKILL.md` |
| Argument passing | `${input:phase:...}` prompt or inline | `$ARGUMENTS` substitution |
| Reload required after install | ✅ Developer: Reload Window | ❌ picked up automatically |
| File-reference syntax | `[label](path)` markdown links | `@absolute/path` |

## Layout

```
codebase-audit/                 # this repo (the clone)
├── SKILL.md                    # entrypoint; sub-command router; lessons summary
├── README.md
├── install.sh                  # per-client installer (sed-substitutes __SKILL_DIR__)
├── LICENSE
├── workflows/                  # one per phase (the actual audit logic)
│   ├── recon.md
│   ├── deploy.md
│   ├── audit.md
│   ├── fpcheck.md
│   ├── verify.md
│   └── report.md
├── references/
│   ├── phase0-source-detection.md
│   ├── phase2-feature-mapping.md
│   ├── phase4-deep-audit.md
│   ├── phase5-fp-check.md
│   ├── phase6-report.md
│   ├── resume-note-template.md
│   ├── live-instance-template.md
│   └── lessons-learned.md
├── prompts/                    # Copilot launcher template (uses __SKILL_DIR__)
│   └── codebase-audit.prompt.md
└── claude/commands/            # Claude launcher templates (use __SKILL_DIR__)
    ├── codebase-audit.md
    └── codebase-audit/
        ├── recon.md
        ├── deploy.md
        ├── audit.md
        ├── fpcheck.md
        ├── verify.md
        └── report.md
```

After `./install.sh` (both targets), the *installed* state looks like:

```
~/.copilot/skills/codebase-audit/        # Copilot skill copy
~/<vscode-prompts-dir>/codebase-audit.prompt.md
~/.claude/skills/codebase-audit/         # Claude skill copy (independent)
~/.claude/commands/codebase-audit.md
~/.claude/commands/codebase-audit/{recon,deploy,audit,fpcheck,verify,report}.md
```

## Customizing the launchers

The launcher templates in `prompts/` and `claude/commands/` are tracked in git and free to edit. Every occurrence of the literal string `__SKILL_DIR__` is substituted at install time with the per-client install path. After edits, re-run `./install.sh` to copy the updates into place.

## Key design choices

- **Per-client self-contained installs**: Copilot stuff under `~/.copilot/`, Claude stuff under `~/.claude/`. Either can be installed alone; neither needs the other's tooling on the machine.
- **Parallel-first**: feature mapping, deep audit, and FP-check each spawn subagents per group/batch. Verification spawns one fork per finding.
- **Memory-persistent across compactions**: every phase rewrites a resume note in session memory and a live-instance note in repo memory.
- **`general-purpose` subagents only** for write-needed work — `Explore` agents are read-only and silently produce no artifacts (a real-audit lesson).
- **FP-check is static, verify is live** — separated so "I couldn't reproduce" handwaves don't kill real source-level bugs.
- **Patch-bypass mining** — for every prior CVE, fetch the patch diff and check sibling files for the same root cause untouched. Highest-value class in practice.
- **No content duplication inside a client install** — launchers are tiny routing stubs; the audit logic lives only in `workflows/` and `SKILL.md`.

## Requirements

- VS Code with GitHub Copilot Chat, and/or Claude Code CLI
- A POSIX shell (`bash`) for install
- Typically `sqlite3` for `audit.db` queries during audits

## License

MIT (see [LICENSE](LICENSE)).
