# `/codebase-audit:recon` — Source Detection + Reconnaissance + Feature Mapping

**Purpose**: Detect the audit target, identify feature groups, and produce a complete code-to-feature mapping via parallel subagents. End by writing the resume note.

**Entry**: User invokes `/codebase-audit:recon` or "audit this app" (full pipeline).
**Exit**: All feature groups mapped, resume note saved, user gate before deploy phase.

---

## Step 1 — Create audit workspace

```bash
TS=$(date -u +%Y%m%d-%H%M%S)
AUDIT_DIR="reports/audit-${TS}"
mkdir -p "${AUDIT_DIR}/files" "${AUDIT_DIR}/artifacts"
sqlite3 "${AUDIT_DIR}/audit.db" "SELECT 1;"  # create empty DB
```

Record `AUDIT_DIR` — every later step uses it.

## Step 2 — Phase 0 source detection

Follow [../references/phase0-source-detection.md](../references/phase0-source-detection.md) exactly:

1. Probe IDA Pro MCP (`mcp_ida-pro-mcp_list_instances`).
2. Scan workspace for source-code indicators (build files, common dirs).
3. Use `vscode_askQuestions` with the appropriate prompt variant.
4. Insert into `cba_sources`.

## Step 3 — Reconnaissance

Use `grep`/`glob`/`semantic_search` (source) and/or `mcp_ida-pro-mcp_survey_binary` (IDA) in parallel to gather:

- Language(s) and framework(s)
- Build/deploy system (Dockerfile, docker-compose, Makefile, install scripts)
- Top-level directory layout
- Entry points (HTTP routes, RPC handlers, CLI commands, scheduled tasks)
- Authentication/authorization patterns
- Configuration loading
- Existing test instances or compose files (helps deploy phase later)

## Step 4 — Define feature groups

Based on codebase size (see [../references/phase2-feature-mapping.md](../references/phase2-feature-mapping.md) Size Guidelines):

| Codebase size | Group count |
|---|---|
| Small (<50 files / <100 functions) | 3-5 |
| Medium | 5-8 |
| Large (>500 files / >1000 functions) | 8-12 |

Use the naming convention `G1…Gn` with stable IDs (so subagent outputs and SQL rows align).

Present groups via `vscode_askQuestions`: "I've identified N feature groups. [list]. Should I proceed?" with `["Looks good — proceed", "Let me adjust the groups"]`.

Insert approved groups into `cba_feature_groups` (status='pending').

## Step 5 — Parallel feature mapping subagents

**CRITICAL agent-type rule**: use `general-purpose` (NOT `Explore`). Explore is read-only and silently produces no SQL inserts or artifact files. (See [../references/lessons-learned.md](../references/lessons-learned.md) item #1.)

Spawn ONE subagent per feature group, ALL in parallel (one `runSubagent` call per group in the same response).

Each subagent prompt (template from [../references/phase2-feature-mapping.md](../references/phase2-feature-mapping.md)) must include:

- Group ID + name + scope (key directories)
- Source access instructions (paths, IDA tool list)
- Instruction to write **two outputs**:
  1. Detailed mapping → `<AUDIT_DIR>/files/G<n>-mapping.md`
  2. SQL inserts into `cba_attack_surface` and `cba_security_observations`
- Instruction to return a compact summary (counts: features, endpoints, observations)

After all subagents return:
- Verify each `files/G<n>-mapping.md` exists and is non-trivial.
- `UPDATE cba_feature_groups SET status='mapped' WHERE id=?` for each.
- Query SQL to confirm counts.

## Step 6 — Write the resume note

Use [../references/resume-note-template.md](../references/resume-note-template.md). Save to `/memories/session/<project>-audit-resume.md`. Include:

- Audit dir + DB path
- Pipeline status (recon DONE; deploy/audit/fpcheck/verify/report NOT STARTED)
- Feature group table (id, name, mapping file)
- Phase-2 observation counts (severity hint × group)
- Top "must-investigate" leads (12-20 items from observations) — these become the prioritization input for the audit phase
- Quirks / environment notes
- Resumption commands

## Step 7 — USER GATE

Present:

> Reconnaissance + feature mapping complete. N groups mapped with M total security observations. Resume note saved.
>
> Next: `/codebase-audit:deploy` to bring up a live instance for later PoC verification, or `/codebase-audit:audit` if you'll skip live testing.
>
> Say **go deploy**, **go audit**, or **adjust** to revise mappings.

Do NOT auto-advance.

## Quality Checks

- [ ] `cba_sources` has one confirmed row
- [ ] `cba_feature_groups` has all groups with status='mapped'
- [ ] Every group has a `files/G<n>-mapping.md` ≥ 50 lines
- [ ] Every group has ≥ 1 row in `cba_security_observations` (zero means mapping was too shallow → re-run that group's subagent)
- [ ] Resume note exists and includes the must-investigate leads list
