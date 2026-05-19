# codebase-audit

A structured, multi-phase security audit skill that drives parallel subagents through **recon → deploy → audit → fpcheck → verify → report**. Works with both **GitHub Copilot Chat** and **Claude Code CLI**.

Battle-tested against real-world Go/HTTP applications. Codifies hard-won lessons from actual audits (see [`references/lessons-learned.md`](references/lessons-learned.md)).

## What it does

```
recon ──► deploy ──► audit ──► fpcheck ──► [open N forks] ──► report
  │         │         │           │              │             │
  │         │         │           │              ▼             │
  │         │         │           │       verify-<id>.md       │
  └─────────┴─────────┴───────────┴───────────────┴─────────────┘
                       SQLite audit.db (single source of truth)
```

## Install

```bash
git clone https://github.com/th4s1s/codebase-audit.git
cd codebase-audit
./install.sh                # installs for both Copilot and Claude (auto-detect)
# or:
./install.sh copilot        # Copilot Chat only
./install.sh claude         # Claude Code CLI only
./install.sh --insiders     # use VS Code Insiders paths
./install.sh --uninstall    # remove
```

The script copies `SKILL.md`, `workflows/`, and `references/` into `~/.copilot/skills/codebase-audit/` (override with `--prefix`), then installs the slash-command launchers for each target.

## Usage

### GitHub Copilot Chat (VS Code)

Copilot Chat does **not** support namespaced sub-commands (`/foo:bar`) — it can only autocomplete top-level slash commands from prompt files. So there is **one** slash command, and you specify the phase as an argument.

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

You can also type the phase inline:

```
/codebase-audit audit
```

Or trigger by free-text phrase:

```
audit this app
find vulnerabilities in this project
run the codebase audit recon phase
```

### Claude Code CLI

Claude Code natively supports namespaced sub-commands via subdirectories under `~/.claude/commands/`. After install, all of these work as autocompleting slash commands:

| Slash command | Phase |
|---|---|
| `/codebase-audit` | full pipeline |
| `/codebase-audit:recon` | source detection + feature mapping |
| `/codebase-audit:deploy` | live instance deployment |
| `/codebase-audit:audit` | CVE ingest + patch-bypass mining + deep audit |
| `/codebase-audit:fpcheck` | static false-positive review |
| `/codebase-audit:verify G1-F1,G1-F2,G2-F5` | per-finding live PoC (run in a forked session) |
| `/codebase-audit:report` | consolidated report + disclosure summary |

All sub-commands accept `$ARGUMENTS` for optional notes (`/codebase-audit:audit focus on G3`).

### Differences at a glance

| Aspect | Copilot Chat | Claude Code CLI |
|---|---|---|
| Slash-command surface | One: `/codebase-audit` (phase as argument) | Seven: `/codebase-audit[:phase]` |
| Sub-command autocomplete | ❌ not supported | ✅ via `commands/<name>/<sub>.md` |
| Argument passing | `${input:phase:...}` prompt or inline | `$ARGUMENTS` substitution |
| Prompt file location | `~/.vscode-server/data/User/prompts/` (Linux/remote), `~/Library/Application Support/Code/User/prompts/` (macOS), `%APPDATA%/Code/User/prompts/` (Windows) | `~/.claude/commands/` |
| Reload required after install | ✅ Developer: Reload Window | ❌ picked up automatically |
| Free-text trigger phrases | ✅ via skill `description` frontmatter | ❌ slash commands only |
| File-reference syntax in prompts | `[label](path)` markdown links | `@path/to/file` |

Both clients share the same `SKILL.md`, `workflows/`, and `references/` content — the only target-specific files are the launchers in `prompts/` (Copilot) and `claude/commands/` (Claude).

## Layout

```
codebase-audit/
├── SKILL.md                    # entrypoint; sub-command router; lessons summary
├── install.sh
├── README.md
├── workflows/                  # one per phase
│   ├── recon.md
│   ├── deploy.md
│   ├── audit.md
│   ├── fpcheck.md
│   ├── verify.md               # runs in a forked conversation
│   └── report.md
├── references/                 # technical detail + templates
│   ├── phase0-source-detection.md
│   ├── phase2-feature-mapping.md
│   ├── phase4-deep-audit.md
│   ├── phase5-fp-check.md
│   ├── phase6-report.md
│   ├── resume-note-template.md
│   ├── live-instance-template.md
│   └── lessons-learned.md
├── prompts/                    # Copilot Chat launcher
│   └── codebase-audit.prompt.md
└── claude/commands/            # Claude Code launchers
    ├── codebase-audit.md
    └── codebase-audit/
        ├── recon.md
        ├── deploy.md
        ├── audit.md
        ├── fpcheck.md
        ├── verify.md
        └── report.md
```

## Key design choices

- **Parallel-first**: feature mapping, deep audit, and FP-check each spawn subagents per group/batch. Verification spawns one fork per finding.
- **Memory-persistent across compactions**: every phase rewrites a resume note in session memory and a live-instance note in repo memory.
- **`general-purpose` subagents only** for write-needed work — `Explore` agents are read-only and silently produce no artifacts (a real-audit lesson).
- **FP-check is static, verify is live** — separated so "I couldn't reproduce" handwaves don't kill real source-level bugs.
- **Patch-bypass mining** — for every prior CVE, fetch the patch diff and check sibling files for the same root cause untouched. Highest-value class in practice.

## Requirements

- VS Code with GitHub Copilot Chat, and/or Claude Code CLI
- A POSIX shell (`bash`) for install
- For target audits: typically `sqlite3` available so the agent can query `audit.db`

## License

MIT (see [LICENSE](LICENSE)).
