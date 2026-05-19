# codebase-audit

A structured, multi-phase security audit skill that drives parallel subagents through **recon → deploy → audit → fpcheck → verify → report**. Works with both **GitHub Copilot Chat** and **Claude Code CLI**.

Battle-tested against real-world Go/HTTP applications. Codifies hard-won lessons from actual audits (see [`references/lessons-learned.md`](references/lessons-learned.md)).

## What it does

```
recon ──► deploy ──► audit ──► fpcheck ──► [open N forks] ──► report
  │         │         │           │              │             │
  │         │         │           │              ▼             │
  │         │         │           │       verify-<id>.md       │
  └─────────┴─────────┴───────────┴──────────────┴─────────────┘
                       SQLite audit.db (single source of truth)
```

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
| **Copilot Chat** | `~/.copilot/skills/codebase-audit/` | `<vscode-prompts-dir>/codebase-audit.prompt.md` |
| **Claude Code CLI** | `~/.claude/skills/codebase-audit/` *(Claude auto-discovers via description triggers)* | `~/.claude/commands/codebase-audit.md` and `~/.claude/commands/codebase-audit/*.md` |

VS Code prompts dir is auto-detected: `~/.vscode-server/data/User/prompts/` (Linux/remote), `~/Library/Application Support/Code/User/prompts/` (macOS), `%APPDATA%/Code/User/prompts/` (Windows).

### How the launchers find the skill

Launcher files live in [`prompts/`](prompts/) and [`claude/commands/`](claude/commands/) as templates containing the literal string `__SKILL_DIR__`. `install.sh` `sed`-substitutes it with the **per-client** skill dir on copy, so each set of launchers points at its own copy:

- Copilot launchers → `/home/<user>/.copilot/skills/codebase-audit/...`
- Claude launchers → `/home/<user>/.claude/skills/codebase-audit/...`

This means you can `./install.sh claude` on a machine that has no VS Code, and nothing ever touches `~/.copilot/`.

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
