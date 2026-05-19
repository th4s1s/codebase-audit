#!/usr/bin/env bash
# install.sh — Install the codebase-audit skill for GitHub Copilot Chat and/or
# Claude Code CLI.
#
# Launcher files (prompts/ for Copilot, commands/ for Claude) are GENERATED
# from this script with absolute paths baked in — there is no duplication of
# SKILL.md or workflow content in the repo.
#
# Usage:
#   ./install.sh                  # install for both (auto-detect)
#   ./install.sh copilot          # only Copilot Chat
#   ./install.sh claude           # only Claude Code CLI
#   ./install.sh --insiders       # use VS Code Insiders paths
#   ./install.sh --prefix DIR     # custom skill install root (default: ~/.copilot/skills)
#   ./install.sh --uninstall      # remove installed files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_NAME="codebase-audit"
PHASES=(recon deploy audit fpcheck verify report)

# ---- args ----
TARGETS=()
INSIDERS=0
UNINSTALL=0
PREFIX="${HOME}/.copilot/skills"

while [[ $# -gt 0 ]]; do
  case "$1" in
    copilot|claude|all) TARGETS+=("$1"); shift ;;
    --insiders) INSIDERS=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]] || [[ " ${TARGETS[*]} " == *" all "* ]]; then
  TARGETS=(copilot claude)
fi

# ---- detect VS Code prompts directory ----
detect_copilot_prompts_dir() {
  local code_dir
  if [[ "${INSIDERS}" == "1" ]]; then code_dir="Code - Insiders"; else code_dir="Code"; fi

  if [[ -d "${HOME}/.vscode-server/data/User" ]]; then
    echo "${HOME}/.vscode-server/data/User/prompts"; return
  fi
  if [[ "${INSIDERS}" == "1" && -d "${HOME}/.vscode-server-insiders/data/User" ]]; then
    echo "${HOME}/.vscode-server-insiders/data/User/prompts"; return
  fi
  case "$(uname -s)" in
    Darwin) echo "${HOME}/Library/Application Support/${code_dir}/User/prompts" ;;
    Linux)  echo "${HOME}/.config/${code_dir}/User/prompts" ;;
    MINGW*|MSYS*|CYGWIN*) echo "${APPDATA:-${HOME}/AppData/Roaming}/${code_dir}/User/prompts" ;;
    *) echo "${HOME}/.config/${code_dir}/User/prompts" ;;
  esac
}

SKILL_DIR="${PREFIX}/${SKILL_NAME}"
COPILOT_PROMPTS_DIR="$(detect_copilot_prompts_dir)"
CLAUDE_COMMANDS_DIR="${HOME}/.claude/commands"

# ---- sanity ----
if [[ ! -f "${SCRIPT_DIR}/SKILL.md" ]]; then
  echo "ERROR: SKILL.md not found next to install.sh." >&2
  exit 1
fi

# ---- helpers ----

# Map phase -> short description used in launcher frontmatter
phase_description() {
  case "$1" in
    recon)    echo "Phase 1: source detection, reconnaissance, parallel feature mapping." ;;
    deploy)   echo "Phase 2: deploy live instance and document in repo memory." ;;
    audit)    echo "Phase 3: CVE ingest, patch-bypass mining, parallel deep audit." ;;
    fpcheck)  echo "Phase 4: static-only false-positive review of findings." ;;
    verify)   echo "Phase 5: per-finding live PoC (run inside a forked conversation)." ;;
    report)   echo "Phase 6: stitch verify artifacts into final report + disclosure summary." ;;
  esac
}

install_skill_files() {
  mkdir -p "${SKILL_DIR}"
  local abs_skill_dir
  abs_skill_dir="$(cd "${SKILL_DIR}" && pwd -P)"
  if [[ "${SCRIPT_DIR}" == "${abs_skill_dir}" ]]; then
    echo "  (skill source dir IS install dir; skipping skill file copy)"
    return
  fi
  echo "  Copying skill files -> ${SKILL_DIR}"
  cp -f "${SCRIPT_DIR}/SKILL.md" "${SKILL_DIR}/SKILL.md"
  for sub in workflows references; do
    if [[ -d "${SCRIPT_DIR}/${sub}" ]]; then
      mkdir -p "${SKILL_DIR}/${sub}"
      cp -f "${SCRIPT_DIR}/${sub}/"*.md "${SKILL_DIR}/${sub}/" 2>/dev/null || true
    fi
  done
}

# ---- Copilot launcher generator (single file, phase as argument) ----
generate_copilot_prompt() {
  local out="$1"
  cat > "${out}" <<EOF
---
mode: 'agent'
description: 'Codebase audit — pass a phase (recon | deploy | audit | fpcheck | verify | report) or leave blank for full pipeline.'
---

Run the **codebase-audit** skill installed at \`${SKILL_DIR}\`.

User-provided argument (may be empty): **\${input:phase:full — or one of: recon, deploy, audit, fpcheck, verify, report}**

First read [${SKILL_DIR}/SKILL.md](${SKILL_DIR}/SKILL.md) for context and routing rules. Then read the matching workflow file from \`${SKILL_DIR}/workflows/\`:

| Argument | Workflow to execute |
|---|---|
| \`recon\` | [${SKILL_DIR}/workflows/recon.md](${SKILL_DIR}/workflows/recon.md) |
| \`deploy\` | [${SKILL_DIR}/workflows/deploy.md](${SKILL_DIR}/workflows/deploy.md) |
| \`audit\` | [${SKILL_DIR}/workflows/audit.md](${SKILL_DIR}/workflows/audit.md) |
| \`fpcheck\` | [${SKILL_DIR}/workflows/fpcheck.md](${SKILL_DIR}/workflows/fpcheck.md) |
| \`verify\` | [${SKILL_DIR}/workflows/verify.md](${SKILL_DIR}/workflows/verify.md) — **must run in a forked conversation** |
| \`report\` | [${SKILL_DIR}/workflows/report.md](${SKILL_DIR}/workflows/report.md) |
| \`full\` / empty / other | Full pipeline: recon → deploy → audit → fpcheck → (instruct user to fork for verify) → report, gating between phases |

Before executing any phase, re-read the resume note at \`/memories/session/<project>-audit-resume.md\` and the live-instance note at \`/memories/repo/<project>-live-instance.md\` (if present) to orient.

Follow every Essential Principle and Rationalization-to-Reject in SKILL.md. Use **\`general-purpose\`** subagents for any write-needed parallel work — never \`Explore\`.
EOF
}

# ---- Claude launcher generators ----
generate_claude_full() {
  local out="$1"
  cat > "${out}" <<EOF
---
description: Run the full codebase-audit pipeline (recon → deploy → audit → fpcheck → verify → report).
argument-hint: "[optional: focus area or notes]"
---

Run the **full codebase-audit pipeline** on the current workspace.

Optional user note: \$ARGUMENTS

Read @${SKILL_DIR}/SKILL.md, then execute the phases in order, gating on user approval between each:

1. @${SKILL_DIR}/workflows/recon.md — source detection, feature mapping, resume note
2. @${SKILL_DIR}/workflows/deploy.md — deploy live instance, write live-instance note
3. @${SKILL_DIR}/workflows/audit.md — CVE ingest, patch-bypass mining, parallel deep audit
4. @${SKILL_DIR}/workflows/fpcheck.md — static false-positive review
5. @${SKILL_DIR}/workflows/verify.md — per-finding live PoC (forked conversations)
6. @${SKILL_DIR}/workflows/report.md — consolidated report + disclosure summary

Follow every Essential Principle and Rationalization-to-Reject in SKILL.md. Honor user gates between phases.
EOF
}

generate_claude_phase() {
  local phase="$1" out="$2" desc
  desc="$(phase_description "${phase}")"

  # verify phase has different argument-hint + extra fork rules
  local arg_hint='"[optional: focus or notes]"'
  local fork_block=""
  if [[ "${phase}" == "verify" ]]; then
    arg_hint='"<finding IDs, comma-separated, e.g. G1-F1,G1-F2>"'
    fork_block=$'\n\nHard rules:\n- This fork MUST NOT modify SQL state (no inserts/updates to `audit.db`)\n- Back up every config file before editing; verify restore at end\n- Re-read configs from disk before editing\n- Write one `artifacts/verify-<finding-id>.md` per finding (CONFIRMED / REFUTED / INCONCLUSIVE)\n- Return a summary table to the orchestrator'
  fi

  cat > "${out}" <<EOF
---
description: "Codebase audit — ${desc}"
argument-hint: ${arg_hint}
---

Run the **${phase}** phase of the codebase-audit skill.

Argument: \$ARGUMENTS

Read @${SKILL_DIR}/SKILL.md and the current resume note at \`/memories/session/<project>-audit-resume.md\` (if present), then execute @${SKILL_DIR}/workflows/${phase}.md.${fork_block}

Stop at the user gate before the next phase.
EOF
}

install_copilot() {
  echo "[copilot] target prompts dir: ${COPILOT_PROMPTS_DIR}"
  install_skill_files
  mkdir -p "${COPILOT_PROMPTS_DIR}"
  generate_copilot_prompt "${COPILOT_PROMPTS_DIR}/${SKILL_NAME}.prompt.md"
  echo "  -> ${COPILOT_PROMPTS_DIR}/${SKILL_NAME}.prompt.md"
}

install_claude() {
  echo "[claude] target commands dir: ${CLAUDE_COMMANDS_DIR}"
  install_skill_files
  mkdir -p "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}"
  generate_claude_full "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}.md"
  echo "  -> ${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}.md"
  for phase in "${PHASES[@]}"; do
    generate_claude_phase "${phase}" "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}/${phase}.md"
    echo "  -> ${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}/${phase}.md"
  done
}

uninstall_copilot() {
  echo "[copilot] removing ${COPILOT_PROMPTS_DIR}/${SKILL_NAME}.prompt.md"
  rm -f "${COPILOT_PROMPTS_DIR}/${SKILL_NAME}.prompt.md"
}

uninstall_claude() {
  echo "[claude] removing ${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}.md and ${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}/"
  rm -f "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}.md"
  rm -rf "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}"
}

uninstall_skill_files() {
  if [[ -d "${SKILL_DIR}" && "${SCRIPT_DIR}" != "$(cd "${SKILL_DIR}" && pwd -P 2>/dev/null || echo /nonexistent)" ]]; then
    echo "Removing skill dir ${SKILL_DIR}"
    rm -rf "${SKILL_DIR}"
  fi
}

# ---- run ----
echo "Targets: ${TARGETS[*]}"
echo "Skill install root: ${SKILL_DIR}"
echo

if [[ "${UNINSTALL}" == "1" ]]; then
  for t in "${TARGETS[@]}"; do
    case "$t" in
      copilot) uninstall_copilot ;;
      claude)  uninstall_claude ;;
    esac
  done
  uninstall_skill_files
  echo "Uninstalled."
  exit 0
fi

for t in "${TARGETS[@]}"; do
  case "$t" in
    copilot) install_copilot ;;
    claude)  install_claude ;;
  esac
done

echo
echo "Done."
if [[ " ${TARGETS[*]} " == *" copilot "* ]]; then
  echo
  echo "Copilot Chat (VS Code): reload window, then type '/codebase-audit'."
  echo "  You'll be prompted for a phase (or leave blank for the full pipeline)."
fi
if [[ " ${TARGETS[*]} " == *" claude "* ]]; then
  echo
  echo "Claude Code CLI: '/codebase-audit', '/codebase-audit:recon', :deploy, :audit,"
  echo "  :fpcheck, :verify <ids>, :report"
fi
