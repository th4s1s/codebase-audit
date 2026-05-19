# codebase-audit

A structured, multi-phase security audit skill for GitHub Copilot Chat. Drives parallel subagents through recon, live-instance deployment, deep vulnerability hunting, false-positive review, and per-finding live PoC verification, then stitches everything into a vendor-facing report.

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

Each phase is independently invokable as a slash command, or you can run the full pipeline.

## Install

```bash
git clone https://github.com/th4s1s/codebase-audit.git
cd codebase-audit
./install.sh
```

This:
1. Copies `SKILL.md`, `workflows/`, and `references/` into `~/.copilot/skills/codebase-audit/` (override with `--prefix`)
2. Installs slash-command prompt files into your VS Code user prompts folder (auto-detects native macOS/Linux/Windows or vscode-server/WSL/Remote-SSH; pass `--insiders` for VS Code Insiders)

Reload VS Code after install. The slash commands appear in Copilot Chat:

| Slash command | Phase |
|---|---|
| `/codebase-audit` | Full pipeline |
| `/codebase-audit-recon` | Source detection + feature mapping |
| `/codebase-audit-deploy` | Live instance deployment |
| `/codebase-audit-audit` | CVE ingest + patch-bypass mining + deep audit |
| `/codebase-audit-fpcheck` | Static false-positive review |
| `/codebase-audit-verify` | Per-finding live PoC (run inside a forked conversation) |
| `/codebase-audit-report` | Final report + disclosure summary |

You can also trigger the skill by phrase: *"audit this app"*, *"find vulnerabilities in this project"*, or `/codebase-audit:recon`.

### Uninstall

```bash
./install.sh --uninstall
```

## Layout

```
codebase-audit/
├── SKILL.md                    # entrypoint; sub-command router; lessons summary
├── install.sh
├── workflows/                  # one per sub-command
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
└── prompts/                    # VS Code slash-command prompts
    ├── codebase-audit.prompt.md
    └── codebase-audit-<phase>.prompt.md
```

## Key design choices

- **Parallel-first**: feature mapping, deep audit, and FP-check each spawn subagents per group/batch. Verification spawns one fork per finding.
- **Memory-persistent across compactions**: every phase rewrites a resume note in session memory and a live-instance note in repo memory.
- **`general-purpose` subagents only** for write-needed work — `Explore` agents are read-only and will silently produce no artifacts (a real-audit lesson).
- **FP-check is static, verify is live** — separated to prevent "I couldn't reproduce" handwaves from killing real source-level bugs.
- **Patch-bypass mining** — for every prior CVE, fetch the patch diff and check sibling files for the same root cause untouched. Highest-value class in practice.

## Requirements

- VS Code with GitHub Copilot Chat
- A POSIX shell (`bash`) for install
- For target audits: typically `sqlite3` available in your environment so the agent can query `audit.db`

## License

MIT (see [LICENSE](LICENSE)).
