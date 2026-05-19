# Audit Pipeline — Execution Workflow

This is the master execution sequence. The orchestrator reads this file and follows it phase by phase.

---

## Phase 0: Source Detection

**Entry**: User has asked to audit an application.
**Degrees of Freedom**: Low — follow the detection logic exactly.

### Actions

1. **Probe for IDA Pro MCP**: Call `ida-pro-mcp-list_instances` (or equivalent MCP health check). If it returns instances, record each binary name and port as an available source.

2. **Check for source code path**: Look at the current working directory and immediate children for source code indicators:
   - Directories containing `.cpp`, `.c`, `.h`, `.py`, `.js`, `.ts`, `.java`, `.go`, `.rs` files
   - Build files (`CMakeLists.txt`, `Makefile`, `package.json`, `Cargo.toml`, `pom.xml`, `go.mod`)
   - If found, record the root path as the source code directory

3. **Ask the user** using `ask_user`:
   - If BOTH sources detected: "I found source code at `{path}` and IDA Pro MCP connected to `{binary}`. Which should I use for the audit?"
     - Choices: `["Both source code + IDA Pro (Recommended)", "Source code only", "IDA Pro binary analysis only"]`
   - If ONLY source detected: "I found source code at `{path}`. Is this the target, or do you also have a binary loaded in IDA Pro?"
     - Choices: `["Source code only (Recommended)", "I also have IDA Pro — let me connect it"]`
   - If ONLY IDA Pro detected: "I see IDA Pro MCP connected to `{binary}`. Do you also have source code available?"
     - Choices: `["IDA Pro only (Recommended)", "I have source code too — let me provide the path"]`
   - If NEITHER detected: Ask freeform: "Where is your target? Provide a source code path, or connect IDA Pro MCP to a binary and tell me when ready."

4. **Record source configuration** in a SQL table:
   ```sql
   CREATE TABLE IF NOT EXISTS cba_sources (
       id TEXT PRIMARY KEY,
       type TEXT NOT NULL, -- 'source', 'ida', 'both'
       source_path TEXT,
       ida_binary TEXT,
       ida_port INTEGER
   );
   ```

**Exit**: Source configuration recorded. At least one source is available and confirmed by user.

---

## Phase 1: Reconnaissance

**Entry**: Phase 0 complete. Sources confirmed.
**Degrees of Freedom**: Medium — adapt to what's available, but cover all items.

### Actions

1. **If source code available**: Use `glob` and `grep` to identify:
   - Language(s) and framework(s)
   - Build system
   - Directory structure (top 2 levels)
   - Entry points (main files, route definitions, API endpoints)
   - Authentication/authorization patterns
   - Configuration files

2. **If IDA Pro available**: Call `ida-pro-mcp-survey_binary` to get:
   - File metadata, segments, entry points
   - Top strings and functions by xref count
   - Import categories
   - Call graph summary

3. **If both**: Run steps 1 and 2 in parallel.

4. **Determine feature group count**: Based on codebase size:
   - Small (< 50 files or < 100 functions): 3-5 groups
   - Medium (50-500 files or 100-1000 functions): 5-8 groups
   - Large (> 500 files or > 1000 functions): 8-12 groups

5. **Propose groups to user**: Use `ask_user` to present the proposed feature groups:
   "I've identified N feature areas. Here's my proposed grouping: [list]. Should I proceed with this grouping?"
   - Choices: `["Looks good — proceed", "Let me adjust the groups"]`

6. **Store recon results** in SQL:
   ```sql
   CREATE TABLE IF NOT EXISTS cba_feature_groups (
       id TEXT PRIMARY KEY,
       name TEXT NOT NULL,
       description TEXT,
       key_directories TEXT, -- comma-separated
       entry_points TEXT,    -- comma-separated
       status TEXT DEFAULT 'pending' -- pending, mapped, audited
   );
   ```

**Exit**: Feature groups defined in `cba_feature_groups` table. User approved.

---

## Phase 2: Feature Mapping (Parallel Subagents)

**Entry**: Phase 1 complete. Feature groups defined.
**Degrees of Freedom**: High for subagents (they explore freely), Low for orchestrator (follow the template).

### Actions

1. **Read** `references/phase2-feature-mapping.md` for the subagent prompt template.

2. **Spawn one subagent per feature group** using the Task tool:
   - **Agent type**: `Explore` (for source code) or `general-purpose` (if IDA Pro is needed)
   - **Model**: `claude-opus-4.5` or later (use the best available model for accuracy)
   - **Prompt**: Fill the template from `phase2-feature-mapping.md` with group-specific context
   - Launch ALL subagents in parallel (one Task call per group, all in the same response)

3. **Collect results**: As each subagent returns, extract:
   - Feature list with source file locations
   - Entry points and API endpoints
   - Authentication requirements per feature
   - Security-relevant observations

4. **Store mappings**:
   - Save each group's full mapping to `files/<group-id>-mapping.md` in the session directory
   - Insert attack surface entries into SQL:
     ```sql
     CREATE TABLE IF NOT EXISTS cba_attack_surface (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         group_id TEXT NOT NULL,
         endpoint TEXT,
         method TEXT,
         auth_required TEXT, -- 'none', 'user', 'admin'
         description TEXT
     );
     ```
   - Insert security observations into SQL:
     ```sql
     CREATE TABLE IF NOT EXISTS cba_security_observations (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         group_id TEXT NOT NULL,
         observation TEXT,
         severity_hint TEXT, -- 'high', 'medium', 'low'
         location TEXT
     );
     ```

5. **Update group status**: `UPDATE cba_feature_groups SET status = 'mapped' WHERE id = ?`

6. **Present summary to user**: Show a table of all groups with mapping statistics (features found, endpoints, observations).

7. **USER GATE**: Tell the user: "Feature mapping is complete. Review the mappings above. Say **go** when you're ready for the deep audit phase, or ask me to adjust any group."
   - **Do NOT proceed past this point without explicit user approval.**

**Exit**: All groups have status `mapped`. Mappings saved to session files and SQL. User has said "go".

---

## Phase 3: Known Findings Ingest

**Entry**: User said "go". All groups mapped.
**Degrees of Freedom**: Low — mechanical dedup.

### Actions

1. **Check for prior findings**: Query any existing audit findings from previous sessions:
   - Check `audit_findings` table (from prior audit skill runs)
   - Check for `findings/` or `findings-draft/` directories in the workspace
   - Ask user: "Do you have findings from a prior audit that I should avoid duplicating?"

2. **Build the known-findings list**: Compile a deduplicated list of already-known vulnerabilities with their titles and locations. This list is passed to every Phase 4 subagent to prevent re-discovery.

3. **Store known findings**:
   ```sql
   CREATE TABLE IF NOT EXISTS cba_known_findings (
       id TEXT PRIMARY KEY,
       title TEXT NOT NULL,
       location TEXT,
       source TEXT -- 'prior_audit', 'user_provided'
   );
   ```

**Exit**: Known findings list compiled (may be empty for first audit).

---

## Phase 4: Deep Audit (Parallel Subagents)

**Entry**: Phase 3 complete. Known findings loaded.
**Degrees of Freedom**: High for subagents (adversarial creativity), Low for orchestrator.

### Actions

1. **Read** `references/phase4-deep-audit.md` for the subagent prompt template.

2. **Create findings table**:
   ```sql
   CREATE TABLE IF NOT EXISTS cba_findings (
       id TEXT PRIMARY KEY,          -- e.g., 'G1-F1'
       group_id TEXT NOT NULL,
       title TEXT NOT NULL,
       severity TEXT NOT NULL,       -- CRITICAL, HIGH, MEDIUM, LOW
       confidence INTEGER NOT NULL,  -- 1-10
       location TEXT NOT NULL,
       root_cause TEXT NOT NULL,
       impact TEXT NOT NULL,
       verified TEXT DEFAULT 'source', -- source, live-poc, ida-confirmed
       boundary_crossed TEXT,        -- auth, authz, confidentiality, etc.
       attacker_position TEXT,       -- unauthenticated, authenticated, admin, local
       cwe TEXT
   );
   ```

3. **Spawn one subagent per feature group** using the Task tool:
   - **Agent type**: `general-purpose`
   - **Model**: `claude-opus-4.5` or later
   - **Prompt**: Fill the template from `phase4-deep-audit.md` with:
     - The group's mapping file content
     - The known-findings list (to avoid duplicates)
     - Source access instructions (paths, IDA Pro MCP tool names)
     - The target instance URL/creds if provided by user for live testing
   - Launch ALL subagents in parallel

4. **Collect and insert findings**: Parse each subagent's output and INSERT into `cba_findings`.

5. **Live PoC verification** (if test instance available):
   - For each finding that a subagent marked as verifiable, note it
   - Subagents with shell access can test directly; others document the HTTP request

6. **Update group status**: `UPDATE cba_feature_groups SET status = 'audited' WHERE id = ?`

7. **Present finding summary**: Show a table grouped by severity with counts per group.

**Exit**: All groups have status `audited`. Findings stored in `cba_findings`.

---

## Phase 5: FP-Check Verification (Parallel Subagents)

**Entry**: Phase 4 complete. All findings in `cba_findings`.
**Degrees of Freedom**: Low — follow `fp-check-pivot` skill methodology exactly.

### Actions

1. **Read** `references/phase5-fp-check.md` for batching strategy and prompt template.

2. **Create verdicts table**:
   ```sql
   CREATE TABLE IF NOT EXISTS cba_fp_verdicts (
       finding_id TEXT PRIMARY KEY,
       verdict TEXT NOT NULL,        -- TRUE_POSITIVE, FALSE_POSITIVE, DUPLICATE
       reason TEXT,
       final_severity TEXT,
       final_id TEXT,                -- F-N numbering for report
       merged_into TEXT              -- for duplicates
   );
   ```

3. **Batch findings**: Group into batches of 8-12 findings each, by feature group or severity tier. Each batch must be independently verifiable.

4. **Spawn one subagent per batch**:
   - **Agent type**: `general-purpose`
   - **Model**: `claude-opus-4.5` or later
   - **Prompt**: Include the `fp-check-pivot` SKILL.md instructions, the canonical FP rules, and the finding details. See `phase5-fp-check.md` for the template.
   - Each subagent must:
     - Re-read every cited source file to verify claims (Capability Validity rule 3)
     - Apply all 18 Hard Exclusions
     - Apply all 10 Precedent rules
     - Apply the Marginal Gain Test (HE #17) for admin-only findings
     - Return verdict + reason for each finding

5. **Collect verdicts**: INSERT into `cba_fp_verdicts`. Assign sequential `F-N` IDs to TRUE_POSITIVE findings.

6. **Deduplication pass**: Identify findings that describe the same root cause from different groups. Mark as DUPLICATE with `merged_into` pointing to the primary finding.

7. **Present FP-check summary**: Show counts (TP, FP, DUP) and the list of confirmed findings.

**Exit**: Every finding has a verdict in `cba_fp_verdicts`. No unverified findings remain.

---

## Phase 6: Report Generation

**Entry**: Phase 5 complete. All verdicts recorded.
**Degrees of Freedom**: Low — follow the report template exactly.

### Actions

1. **Create audit directory**: `audit-<YYYYMMDD-HHMMSS>/` in the current working directory.

2. **Read** `references/phase6-report.md` for the report template.

3. **Query confirmed findings**:
   ```sql
   SELECT f.*, v.final_severity, v.final_id, v.reason as fp_reason
   FROM cba_findings f
   JOIN cba_fp_verdicts v ON f.id = v.finding_id
   WHERE v.verdict = 'TRUE_POSITIVE'
   ORDER BY
       CASE v.final_severity
           WHEN 'CRITICAL' THEN 1
           WHEN 'HIGH' THEN 2
           WHEN 'MEDIUM' THEN 3
           WHEN 'LOW' THEN 4
       END,
       v.final_id;
   ```

4. **Write `report.md`** using the template, including:
   - Executive summary with finding counts by severity
   - Architecture overview
   - Each confirmed finding with full details
   - False positive analysis summary (rejection categories and counts)
   - Recommendations grouped by priority

5. **Announce completion**: Tell the user where the report is and summarize the key findings.

**Exit**: `audit-<timestamp>/report.md` exists with all confirmed findings.

---

## Resumption Logic

If the skill is invoked and prior state exists:

| State | Action |
|-------|--------|
| `cba_sources` exists | Skip Phase 0, confirm sources still valid |
| `cba_feature_groups` all `mapped` | Skip Phases 0-2, ask user if mappings are still current |
| `cba_findings` populated | Skip Phases 0-4, offer to re-run FP-check or go straight to report |
| `cba_fp_verdicts` populated | Skip to Phase 6 (report generation) |
| Nothing exists | Start from Phase 0 |

Always ask the user before skipping: "I found existing [mappings/findings/verdicts] from a prior run. Should I reuse them or start fresh?"
