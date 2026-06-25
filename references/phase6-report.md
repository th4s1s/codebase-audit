# Report template (per-finding live + source consolidated)

The lean, maintainer-facing vulnerability-report format used by [../workflows/report.md](../workflows/report.md) in both modes:

- **Live, per-finding (in the fork)**: one file `reports/audit-<ts>/artifacts/<FINDING-ID>-vuln-report.md`.
- **Source-only, consolidated (in the orchestrator)**: one `reports/audit-<ts>/report.md` with one finding-section per true positive, using the same headings.

Model these on the Redis audit reports (e.g. `G2-F1-vuln-report.md`): same structure and depth, with the lean style below.

## Sections (exact, in order)

```markdown
# <FINDING-ID>: <one-line title; a CWE id is fine, e.g. (CWE-476)>

## Affected Version
- <product> version: `<x.y.z>`
- Commit: `<sha>` (tag/branch if known)
- optional build string in a ```text block

## Summary
1-2 short paragraphs. What the bug is, and the genuine attacker path (who controls
which input, reaching which sink). Live: state it was confirmed on the stock build
and that a control run with honest input behaves normally. Source-only: state plainly
that this is a source-level finding, NOT live-verified.

## Root Cause
The code-level explanation. Cite `src/file.c:line`. Show the flaw and the flawed
caller in minimal code blocks (only the relevant lines, annotated). Trace the data
flow from attacker-controlled input to the sink. Note any guard that does NOT stop it.

## Steps to reproduce
Live: the bash setup; a Control (honest-input) run FIRST; then the attack run(s).
Inline the PoC ("Save as `poc.py`") and stage a runnable copy at `poc/<name>`. Paste
the REAL captured output verbatim (curl -i / server log / exit status).
Source-only: a reproduction GUIDE - concrete steps, inputs, and conditions to trigger
it, derived from source - with NO execution and NO captured output. Label it as a
source-level guide.

## Impact
The concrete attacker capability and what is lost; the trust boundary crossed. Honest
severity in prose (CRITICAL / HIGH / MEDIUM / LOW + a one-line justification). No CVSS
score, no severity table.
```

## Annotated example (abridged, from a real report)

````markdown
# G2-F1: NULL-pointer dereference in `ACLLoadFromFile()` crashes the server via `ACL LOAD` or at startup (CWE-476)

## Affected Version
- Redis version: `8.8.0`
- Commit: `5a693aae` (tag `8.8.0`)

## Summary
`ACLLoadFromFile()` (`src/acl.c`) parses an ACL file line by line. When the selector
merge helper hits an unmatched `(` it frees its array and returns `NULL` but leaves
`*merged_argc >= 1`; the caller omits the `continue` and then indexes the NULL array,
so `ACL LOAD` (or a malformed `aclfile` at startup) crashes the process with SIGSEGV.
Confirmed on the stock 8.8.0 build; a control run with a valid ACL file stays healthy.

## Root Cause
`ACLMergeSelectorArguments()` returns `NULL` without resetting `*merged_argc`:
```c
/* src/acl.c:2097 - unmatched '(' */
if (open_bracket_start != -1) {
    ...
    return NULL;            /* *merged_argc still > 0 */
}
```
The caller does not skip the line and dereferences the NULL array:
```c
/* src/acl.c:2396 */
if (!acl_args) { errors = sdscatprintf(...); }   /* no continue */
for (int j = 0; j < merged_argc; j++)
    acl_args[j] = sdstrim(acl_args[j], ...);      /* acl_args == NULL -> SIGSEGV */
```
Reachable at runtime (`ACL LOAD` -> `ACLLoadFromFile`, `src/acl.c:3018`) and at
startup (`ACLLoadUsersAtStartup`, `src/acl.c:2585`).

## Steps to reproduce
Save as `poc.sh` (runnable copy at `poc/poc.sh`):
```bash
mkdir -p /tmp/g2-live
printf 'user default on nopass ~* &* +@all\nuser bob on (+get\n' > /tmp/g2-live/users.acl
src/redis-server --port 6399 --daemonize yes --dir /tmp/g2-live \
  --aclfile /tmp/g2-live/users.acl --logfile poc.log
src/redis-cli -p 6399 ACL LOAD
```
Captured output:
```text
$ src/redis-cli -p 6399 ACL LOAD
Error: Server closed the connection
$ src/redis-cli -p 6399 PING
Could not connect to Redis at 127.0.0.1:6399: Connection refused
```
The server log shows `signal: 11` in the `ACLLoadFromFile` frame. A control run with a
valid ACL file returns `OK` and the server stays up.

## Impact
A principal able to write the `aclfile` plants one malformed line; a later `ACL LOAD`
by an admin, or the next restart, crashes the server (SIGSEGV) instead of the
documented "reject the file, keep previous ACLs". Denial of service across a trust
boundary (file-writer to admin/restart). Severity: HIGH (low precondition on shared
hosts, deterministic crash).
````

## Severity (prose, no CVSS)

Judge severity from the attacker's concrete gain and state it in one line in *Impact*:

- **CRITICAL** - unauthenticated RCE, full auth bypass, or breach of all users' data.
- **HIGH** - authenticated RCE, SSRF to the internal network, SQLi with data access, user-to-admin escalation, or a remotely reachable crash/DoS across a trust boundary.
- **MEDIUM** - sensitive info disclosure, CSRF or stored XSS on sensitive operations, amplified DoS.
- **LOW** - non-sensitive disclosure, interaction-heavy reflected XSS, configuration weakness.

Apply the Marginal Gain Test: a self-healing, self-only, or operator-misconfiguration condition is Informational, not a vuln. Lead with the honest verdict; never inflate or defend an overstated rating under pushback.

## Writing style

- Technical precision: exact paths, function names, line numbers, values.
- Measured, not asserted: state what you observed and quantified ("observed M/N", "effectively unbounded, expected N iterations"); never "it would crash" or a bare "infinite" / "always" / "never".
- Actionable: the Root Cause and Impact should make the fix obvious; a one-line fix may be folded into Root Cause. Keep it lean - no separate Remediation or References section unless a patch-bypass needs the prior CVE/GHSA cited inline.
- **No em-dashes.** Minimal `**`/`*`. Use `code spans` for symbols and paths.
- Self-contained and reproducible: inline the PoC AND stage a runnable copy in `poc/` (live mode). Embed the real output. No prebuilt binaries. Never reference a `reports/audit-<ts>/` path.
- Each finding readable in a couple of minutes.
