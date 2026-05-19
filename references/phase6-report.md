# Phase 6: Report Generation

## Purpose

Create the final audit report as a single `report.md` file in a timestamped audit directory.

## Directory Creation

```
audit-YYYYMMDD-HHMMSS/
└── report.md
```

Use the current date and time for the directory name. If PoC scripts were created during the audit, place them alongside the report.

## Report Template

```markdown
# Security Audit Report

**Target**: {application_name} {version}
**Date**: {date}
**Auditor**: {auditor_name_or_tool}
**Methodology**: Parallel feature-mapped codebase audit

---

## Executive Summary

{1-2 paragraph overview of the audit scope, approach, and key results}

**Finding Summary**:

| Severity | Count |
|----------|-------|
| Critical | {n} |
| High     | {n} |
| Medium   | {n} |
| Low      | {n} |
| **Total** | **{n}** |

---

## Architecture Overview

{Brief description of the application architecture, technology stack, deployment model,
 and security-relevant design decisions. Include a diagram if helpful.}

### Attack Surface

| Entry Point | Method | Authentication | Feature Group |
|-------------|--------|----------------|---------------|
{table rows from cba_attack_surface}

---

## Findings

{For each confirmed finding, ordered by severity then by F-N ID:}

### F-{N}: {Title}

| Attribute | Value |
|-----------|-------|
| **Severity** | {CRITICAL/HIGH/MEDIUM/LOW} |
| **CWE** | {CWE-NNN: Name} |
| **CVSS** | {score if calculable} |
| **Attacker Position** | {unauthenticated/authenticated/admin/local} |
| **Boundary Crossed** | {description} |
| **Affected Component** | {file:line or endpoint} |

#### Description

{2-4 paragraph technical description of the vulnerability, including:
 - What the vulnerability is
 - Why it exists (root cause)
 - Where in the code it manifests}

#### Data Flow

```
{source} → {processing steps} → {sink}
```

#### Impact

{What an attacker achieves. Be specific and realistic.}

#### Proof of Concept

```
{HTTP request, curl command, or script}
```

{If live-tested, include the server response.}

#### Remediation

{Specific fix recommendation with code-level guidance.}

---

## False Positive Analysis

{Summary of the FP-check process and its results.}

| Category | Count | Examples |
|----------|-------|---------|
| Hard Exclusion matches | {n} | {brief list} |
| Precedent rule matches | {n} | {brief list} |
| Capability Validity failures | {n} | {brief list} |
| Duplicates merged | {n} | {brief list} |

{Optionally include a paragraph on patterns observed — e.g., "Most FPs were due to
 the application's consistent use of parameterized queries, which eliminated
 all SQL injection candidates."}

---

## Recommendations

### Immediate (Critical/High findings)

{Numbered list of urgent fixes, one per finding}

### Short-term (Medium findings)

{Numbered list of fixes for medium findings}

### Long-term (Architectural)

{Broader security improvements suggested by the audit}

---

## Appendix

### Methodology

This audit used a parallel feature-mapped approach:
1. Source detection and reconnaissance
2. Feature mapping via {N} parallel subagents
3. Deep vulnerability hunting via {N} parallel subagents
4. False-positive verification using the fp-check-pivot methodology
5. Report generation

### Feature Groups Audited

| Group | Name | Features Mapped | Findings (pre-FP) | Confirmed |
|-------|------|-----------------|-------------------|-----------|
{table rows from cba_feature_groups joined with finding counts}

### Tools Used

- {list of tools: source code analysis, IDA Pro MCP, live testing, etc.}
```

## Severity Calibration

Use these definitions consistently:

| Severity | Criteria |
|----------|----------|
| **CRITICAL** | Unauthenticated RCE, complete authentication bypass, or data breach affecting all users. CVSS ≥ 9.0. |
| **HIGH** | Authenticated RCE, SSRF with internal network access, SQL injection with data access, privilege escalation from user to admin. CVSS 7.0-8.9. |
| **MEDIUM** | Information disclosure of sensitive data, CSRF on sensitive operations, stored XSS, denial of service with amplification. CVSS 4.0-6.9. |
| **LOW** | Information disclosure of non-sensitive data, reflected XSS requiring specific interaction, configuration weaknesses. CVSS < 4.0. |

## Writing Style

- **Technical precision**: Use exact file paths, function names, line numbers
- **No speculation**: Every claim must be backed by code evidence or PoC output
- **Attacker perspective**: Write impact from the attacker's point of view
- **Actionable remediation**: Give specific code-level fixes, not generic advice like "validate input"
- **Concise findings**: Each finding should be self-contained and readable in 2 minutes
