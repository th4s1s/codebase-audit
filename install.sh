#!/usr/bin/env bash
# install.sh — Install the codebase-audit skill for GitHub Copilot Chat and/or
# Claude Code CLI.
#
# Launcher files live in prompts/ (Copilot) and claude/commands/ (Claude) as
# templates. install.sh just copies them with __SKILL_DIR__ substituted by the
# actual install path so the launchers work from any project CWD.
#
# Usage:
#   ./install.sh                  # install for both (auto-detect)
#   ./install.sh copilot          # only Copilot Chat
#   ./install.sh claude           # only Claude Code CLI
#   ./install.sh --insiders       # use VS Code Insiders paths
#   ./install.sh --prefix DIR     # custom skill install root (default: ~/.copilot/skills)
#   ./install.sh --uninstall      # remove installed launcher files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_NAME="codebase-audit"

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

# Copy a template file, replacing __SKILL_DIR__ with $SKILL_DIR. Use '|' as
# sed delimiter so '/' characters in SKILL_DIR don't need escaping.
copy_template() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "${dst}")"
  sed -e "s|__SKILL_DIR__|${SKILL_DIR}|g" "${src}" > "${dst}"
  echo "  -> ${dst}"
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

install_copilot() {
  echo "[copilot] target prompts dir: ${COPILOT_PROMPTS_DIR}"
  install_skill_files
  for f in "${SCRIPT_DIR}/prompts/"*.prompt.md; do
    [[ -e "$f" ]] || continue
    copy_template "$f" "${COPILOT_PROMPTS_DIR}/$(basename "$f")"
  done
}

install_claude() {
  echo "[claude] target commands dir: ${CLAUDE_COMMANDS_DIR}"
  install_skill_files
  # Top-level command
  if [[ -f "${SCRIPT_DIR}/claude/commands/${SKILL_NAME}.md" ]]; then
    copy_template \
      "${SCRIPT_DIR}/claude/commands/${SKILL_NAME}.md" \
      "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}.md"
  fi
  # Namespaced sub-commands
  if [[ -d "${SCRIPT_DIR}/claude/commands/${SKILL_NAME}" ]]; then
    for f in "${SCRIPT_DIR}/claude/commands/${SKILL_NAME}/"*.md; do
      [[ -e "$f" ]] || continue
      copy_template "$f" "${CLAUDE_COMMANDS_DIR}/${SKILL_NAME}/$(basename "$f")"
    done
  fi
}

uninstall_copilot() {
  echo "[copilot] removing prompts"
  for f in "${SCRIPT_DIR}/prompts/"*.prompt.md; do
    [[ -e "$f" ]] || continue
    rm -f "${COPILOT_PROMPTS_DIR}/$(basename "$f")"
  done
}

uninstall_claude() {
  echo "[claude] removing commands"
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
