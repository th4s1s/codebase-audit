#!/usr/bin/env bash
# install.sh — Install the codebase-audit skill for GitHub Copilot Chat and/or
# Claude Code CLI.
#
# Design: each client gets its OWN self-contained copy of the skill.
#   - Copilot install root: ~/.copilot/skills/codebase-audit/
#       (newer Copilot Chat auto-registers SKILL.md as a slash command —
#        no separate prompt-launcher file is installed)
#   - Claude install root:  ~/.claude/skills/codebase-audit/
#       launchers:          ~/.claude/commands/codebase-audit.md
#                           ~/.claude/commands/codebase-audit/*.md
#
# Claude launchers contain the literal string __SKILL_DIR__; install.sh
# sed-substitutes it with the client's own SKILL_DIR so each set of launchers
# points at its own copy. Installing one client does not touch the other.
#
# Usage:
#   ./install.sh                  # install for both clients
#   ./install.sh copilot          # only Copilot Chat
#   ./install.sh claude           # only Claude Code CLI
#   ./install.sh --insiders       # use VS Code Insiders paths
#   ./install.sh --uninstall      # remove the selected clients' launchers
#                                 # AND their skill install dirs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_NAME="codebase-audit"

# ---- args ----
TARGETS=()
INSIDERS=0
UNINSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    copilot|claude|all) TARGETS+=("$1"); shift ;;
    --insiders) INSIDERS=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]] || [[ " ${TARGETS[*]} " == *" all "* ]]; then
  TARGETS=(copilot claude)
fi

# ---- per-client paths ----
COPILOT_SKILL_DIR="${HOME}/.copilot/skills/${SKILL_NAME}"
CLAUDE_SKILL_DIR="${HOME}/.claude/skills/${SKILL_NAME}"
CLAUDE_COMMANDS_DIR="${HOME}/.claude/commands"

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

COPILOT_PROMPTS_DIR="$(detect_copilot_prompts_dir)"

# ---- sanity ----
if [[ ! -f "${SCRIPT_DIR}/SKILL.md" ]]; then
  echo "ERROR: SKILL.md not found next to install.sh." >&2
  exit 1
fi

# ---- helpers ----

# Copy SKILL.md + workflows/ + references/ from SCRIPT_DIR into $1.
# Skips if target is the same as SCRIPT_DIR (e.g. cloned directly into install
# location).
install_skill_files() {
  local target="$1"
  mkdir -p "${target}"
  local abs_target
  abs_target="$(cd "${target}" && pwd -P)"
  if [[ "${SCRIPT_DIR}" == "${abs_target}" ]]; then
    echo "  (source dir IS install dir; skipping skill file copy)"
    return
  fi
  echo "  Copying skill content -> ${target}"
  cp -f "${SCRIPT_DIR}/SKILL.md" "${target}/SKILL.md"
  for sub in workflows references; do
    if [[ -d "${SCRIPT_DIR}/${sub}" ]]; then
      mkdir -p "${target}/${sub}"
      cp -f "${SCRIPT_DIR}/${sub}/"*.md "${target}/${sub}/" 2>/dev/null || true
    fi
  done
}

# sed-substitute __SKILL_DIR__ in $1 with $3, write result to $2.
# Uses '|' as sed delimiter so '/' in paths needs no escaping.
copy_template() {
  local src="$1" dst="$2" skill_dir="$3"
  mkdir -p "$(dirname "${dst}")"
  sed -e "s|__SKILL_DIR__|${skill_dir}|g" "${src}" > "${dst}"
  echo "  -> ${dst}"
}

install_copilot() {
  echo "[copilot]"
  echo "  skill dir:     ${COPILOT_SKILL_DIR}"
  install_skill_files "${COPILOT_SKILL_DIR}"
  # Legacy cleanup: older installs dropped a prompt-launcher file in the
  # VS Code prompts dir. Newer Copilot Chat auto-registers SKILL.md as a
  # slash command, so the launcher is now redundant and causes a duplicate
  # `/codebase-audit` autocomplete entry. Remove it if present.
  local legacy="${COPILOT_PROMPTS_DIR}/${SKILL_NAME}.prompt.md"
  if [[ -f "${legacy}" ]]; then
    echo "  removing legacy prompt launcher: ${legacy}"
    rm -f "${legacy}"
  fi
}

install_claude() {
  echo "[claude]"
  echo "  skill dir:     ${CLAUDE_SKILL_DIR}"
  echo "  commands dir:  ${CLAUDE_COMMANDS_DIR}"
  install_skill_files "${CLAUDE_SKILL_DIR}"
  # Top-level command
  if [[ -f "${SCRIPT_DIR}/claude/commands/${SKILL_NAME}.md" ]]; then
    copy_template \
      "${SCRIPT_DIR}/claude/commands/${SKILL_NAME}.md" \
      "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}.md" \
      "${CLAUDE_SKILL_DIR}"
  fi
  # Namespaced sub-commands
  if [[ -d "${SCRIPT_DIR}/claude/commands/${SKILL_NAME}" ]]; then
    for f in "${SCRIPT_DIR}/claude/commands/${SKILL_NAME}/"*.md; do
      [[ -e "$f" ]] || continue
      copy_template "$f" \
        "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}/$(basename "$f")" \
        "${CLAUDE_SKILL_DIR}"
    done
  fi
}

uninstall_skill_dir() {
  local target="$1"
  local abs_target
  abs_target="$(cd "${target}" 2>/dev/null && pwd -P || echo /nonexistent)"
  if [[ -d "${target}" && "${SCRIPT_DIR}" != "${abs_target}" ]]; then
    echo "  removing ${target}"
    rm -rf "${target}"
  else
    echo "  (skipping ${target} — does not exist OR is the source dir)"
  fi
}

uninstall_copilot() {
  echo "[copilot] uninstalling"
  # Remove the legacy prompt launcher if present (older installs only).
  rm -f "${COPILOT_PROMPTS_DIR}/${SKILL_NAME}.prompt.md"
  uninstall_skill_dir "${COPILOT_SKILL_DIR}"
}

uninstall_claude() {
  echo "[claude] uninstalling"
  rm -f "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}.md"
  rm -rf "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}"
  uninstall_skill_dir "${CLAUDE_SKILL_DIR}"
}

# ---- run ----
echo "Targets: ${TARGETS[*]}"
echo

if [[ "${UNINSTALL}" == "1" ]]; then
  for t in "${TARGETS[@]}"; do
    case "$t" in
      copilot) uninstall_copilot ;;
      claude)  uninstall_claude ;;
    esac
  done
  echo
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
  echo "  The slash command is registered automatically from SKILL.md — there is"
  echo "  no separate prompt-launcher file. To run a specific phase, type e.g."
  echo "  '/codebase-audit recon' (or 'deploy' / 'audit' / 'fpcheck' /"
  echo "  'verify <ids>' / 'report')."
fi
if [[ " ${TARGETS[*]} " == *" claude "* ]]; then
  echo
  echo "Claude Code CLI: '/codebase-audit', '/codebase-audit:recon', :deploy, :audit,"
  echo "  :fpcheck, :verify <ids>, :report"
  echo "  (Claude also auto-loads the skill from ~/.claude/skills/${SKILL_NAME}/ based"
  echo "   on description triggers, e.g. 'audit this app'.)"
fi
