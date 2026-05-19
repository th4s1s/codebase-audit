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
./install.sh                # install for both Copilot and Claude
# or:
./install.sh copilot        # Copilot Chat only
./install.sh claude         # Claude Code CLI only
./install.sh --insiders     # use VS Code Insiders paths
./install.sh --prefix DIR   # custom skill install root (default ~/.copilot/skills)
./install.sh --uninstall    # remove installed launchers
```

What the installer does:

1. Copies `SKILL.md`, `workflows/`, and `references/` into `~/.copilot/skills/codebase-audit/` (override with `--prefix`). This is the **single source of truth** — both clients read from here.
2. **Generates** launcher files with absolute paths baked in:
   - Copilot: one prompt file at `<vscode-prompts-dir>/codebase-audit.prompt.md`
   - Claude: `~/.claude/commands/codebase-audit.md` + `~/.claude/commands/codebase-audit/{recon,deploy,audit,fpcheck,verify,report}.md`

Launchers are not stored in the repo — they're produced by `install.sh` heredocs so there is zero duplication of skill content.

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

All sub-commands accept `$ARGUMENTS` for optional notes (`/codebase-audit:audit focus on G3`).

### Differences at a glance

| Aspect | Copilot Chat | Claude Code CLI |
|---|---|---|
| Slash-command surface | One: `/codebase-audit` (phase as argument) | Seven: `/codebase-audit[:phase]` |
| Sub-command autocomplete | ❌ not supported | ✅ via `commands/<name>/<sub>.md` |
| Argument passing | `${input:phase:...}` prompt or inline | `$ARGUMENTS` substitution |
| Launcher install location | `~/.vscode-server/data/User/prompts/` (Linux/remote), `~/Library/Application Support/Code/User/prompts/` (macOS), `%APPDATA%/Code/User/prompts/` (Windows) | `~/.claude/commands/` |
| Reload required after install | ✅ Developer: Reload Window | ❌ picked up automatically |
| Free-text trigger phrases | ✅ via skill `description` frontmatter | ❌ slash commands only |
| File-reference syntax | `[label](path)` markdown links | `@absolute/path` |

Both clients share the same `SKILL.md`, `workflows/`, and `references/` — the only target-specific bits are the launchers, which `install.sh` generates.

## Layout

```
codebase-audit/
├── SKILL.md                    # entrypoint; sub-command router; lessons summary
├── README.md
├── install.sh                  # generates launchers from heredocs
├── LICENSE
├── workflows/                  # one per phase (single source of truth)
│   ├── recon.md
│   ├── deploy.md
│   ├── audit.md
│   ├── fpcheck.md
│   ├── verify.md
│   └── report.md
└── references/
    ├── phase0-source-detection.md
    ├── phase2-feature-mapping.md
    ├── phase4-deep-audit.md
    ├── phase5-fp-check.md
    ├── phase6-report.md
    ├── resume-note-template.md
    ├── live-instance-template.md
    └── lessons-learned.md
```

## Key design choices

- **Parallel-first**: feature mapping, deep audit, and FP-check each spawn subagents per group/batch. Verification spawns one fork per finding.
- **Memory-persistent across compactions**: every phase rewrites a resume note in session memory and a live-instance note in repo memory.
- **`general-purpose` subagents only** for write-needed work — `Explore` agents are read-only and silently produce no artifacts (a real-audit lesson).
- **FP-check is static, verify is live** — separated so "I couldn't reproduce" handwaves don't kill real source-level bugs.
- **Patch-bypass mining** — for every prior CVE, fetch the patch diff and check sibling files for the same root cause untouched. Highest-value class in practice.
- **No launcher duplication** — `install.sh` generates Copilot prompts and Claude commands from inline templates with absolute paths baked in. The repo holds workflows/SKILL.md exactly once.

## Requirements

- VS Code with GitHub Copilot Chat, and/or Claude Code CLI
- A POSIX shell (`bash`) for install
- Typically `sqlite3` for `audit.db` queries during audits

## License

MIT (see [LICENSE](LICENSE)).
