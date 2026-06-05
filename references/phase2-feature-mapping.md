# Phase 2: Feature Mapping

## Purpose

Divide the application into logical feature groups, then map every feature to its implementing source code. This creates the structured attack surface inventory that Phase 4 auditors use.

## Feature Group Taxonomy

### Grouping Heuristics (in priority order)

1. **Authentication boundary**: Group auth-related code together (login, sessions, tokens, MFA, SSO, password reset)
2. **Core data processing**: The application's primary function — what it does to data (scan, transform, validate, render)
3. **File/data handling**: Upload, download, storage, archive, quarantine operations
4. **Configuration & admin**: Settings management, user management, role management
5. **Network/external**: Outbound connections, webhooks, integrations, federation
6. **Internal infrastructure**: IPC, messaging, database layer, caching
7. **External API surface**: Public endpoints, SDK/client-facing APIs
8. **Unauthenticated surface**: Anything accessible without credentials

### Naming Convention

| ID | Name Pattern | Examples |
|----|-------------|----------|
| G1 | Auth & Session | Login, MFA, token management |
| G2 | Core Processing | File scanning, data transformation |
| G3 | Config & Admin | Settings, user CRUD, policies |
| G4 | Storage & Data | Quarantine, archive, backup |
| G5 | Network & External | Webhooks, proxy, federation |
| G6 | Infrastructure | IPC, database, messaging |
| G7 | API Surface | REST endpoints, gRPC, GraphQL |
| G8 | Unauthenticated | Public pages, health checks, registration |

Adapt names to the target application. Not all groups will exist for every target.

### Size Guidelines

| Metric | Minimum | Ideal | Maximum |
|--------|---------|-------|---------|
| Groups | 3 | 6-8 | 12 |
| Files per group | 3 | 10-30 | 100 |
| Features per group | 2 | 5-15 | 30 |

If a group exceeds the maximum, split it. If below the minimum, merge with a related group.

## Subagent Prompt Template

Replace `{placeholders}` with actual values. The entire prompt is passed to the subagent-spawning tool (see SKILL.md → *Cross-client tool mapping*).

```
You are a security researcher mapping features to source code for a security audit.

## Your Assignment
Feature group: {group_id} — {group_name}
Description: {group_description}
Key directories to focus on: {key_directories}

## Source Access
{source_access_instructions}

For source code: Use your file-search and file-read tools (grep/glob to locate files, then read their contents).
For IDA Pro: Use ida-pro-mcp tools (decompile, analyze_function, entity_query, find_regex, etc.)

## What to Map

For each feature in this group, document:

1. **Feature name**: What does it do?
2. **Entry points**: API endpoints, CLI commands, event handlers, scheduled tasks
3. **Key source files**: The files that implement this feature
4. **Authentication requirements**: None, user-level, admin-level, internal-only
5. **Input sources**: HTTP headers, query params, body, file uploads, environment variables, database
6. **Data flow**: Where does user-controlled data go? Follow from input → processing → output/storage
7. **Trust boundaries crossed**: Does data cross privilege levels, network boundaries, or process boundaries?
8. **Security-relevant observations**: Anything that looks like it could be a vulnerability (but don't investigate deeply — just note it)

## Output Format

Return a structured markdown document with one section per feature:

### Feature: {name}
- **Entry point**: `METHOD /path` or `function_name()` at `file:line`
- **Files**: `file1.cpp`, `file2.cpp`, ...
- **Auth**: none / user / admin
- **Inputs**: list of input sources
- **Data flow**: source → processing → sink
- **Trust boundary**: yes/no, which boundary
- **Observations**: any security-relevant notes

## Thoroughness Level
Be THOROUGH. Read every file in the assigned directories. Don't skip files because they look boring.
Follow imports/includes to understand dependencies. Document internal helper functions that handle user data.

## Known Prior Art
{known_findings_summary}
```

### Source Access Instructions (fill into template)

**Source code only:**
```
Source code is at: {source_path}
Language: {language}
Use glob to find files, grep to search, and your file-read tool to read content.
```

**IDA Pro only:**
```
Binary analysis via IDA Pro MCP. The binary is {binary_name}.
- Use entity_query to find functions/strings/imports
- Use decompile to read function pseudocode
- Use analyze_function for compact analysis (callees, callers, strings)
- Use find_regex to search strings
- Use callgraph to trace call paths
- Use xrefs_to to find references to specific functions/data
```

**Both:**
```
You have TWO sources. Use source code as primary (better names, comments, types).
Use IDA Pro to verify compiled behavior when source is ambiguous.

Source code: {source_path} ({language})
IDA Pro: {binary_name} on port {port}

Prioritize source code for understanding logic. Use IDA for:
- Confirming compiled code matches source (no #ifdef differences)
- Finding strings or constants not obvious from source
- Tracing actual call paths (template instantiation, virtual dispatch)
```

## Mapping Output Storage

After all subagents return:

1. **Session files**: Save each group's full output to `files/{group_id}-mapping.md`
2. **SQL attack surface**:
   ```sql
   INSERT INTO cba_attack_surface (group_id, endpoint, method, auth_required, description)
   VALUES (?, ?, ?, ?, ?);
   ```
3. **SQL observations**:
   ```sql
   INSERT INTO cba_security_observations (group_id, observation, severity_hint, location)
   VALUES (?, ?, ?, ?);
   ```

## Quality Checks

Before presenting mappings to the user, verify:

- [ ] Every group has at least 2 features mapped
- [ ] Every mapped feature has at least one source file reference
- [ ] No source files are mapped to multiple groups (or if they are, it's intentional and documented)
- [ ] Authentication requirements are specified for every entry point
- [ ] At least 1 security observation exists per group (if zero, the mapping was too shallow)
