#!/usr/bin/env bash
# install.sh — Install the codebase-audit skill into the Copilot skill folder
# and register VS Code slash-command prompts.
#
# Usage:
#   ./install.sh                # install for VS Code (stable)
#   ./install.sh --insiders     # install for VS Code Insiders
#   ./install.sh --uninstall    # remove installed files
#   ./install.sh --prefix DIR   # custom skill install root (default: ~/.copilot/skills)
#
# Re-running the script is safe; it overwrites prior versions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="codebase-audit"

# ---- args ----
INSIDERS=0
UNINSTALL=0
PREFIX="${HOME}/.copilot/skills"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --insiders) INSIDERS=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ---- detect VS Code prompts directory ----
detect_prompts_dir() {
  local code_dir
  if [[ "${INSIDERS}" == "1" ]]; then
    code_dir="Code - Insiders"
  else
    code_dir="Code"
  fi

  # 1) Remote / vscode-server (Linux container, WSL, SSH host)
  if [[ -d "${HOME}/.vscode-server/data/User" ]]; then
    echo "${HOME}/.vscode-server/data/User/prompts"; return
  fi
  if [[ "${INSIDERS}" == "1" && -d "${HOME}/.vscode-server-insiders/data/User" ]]; then
    echo "${HOME}/.vscode-server-insiders/data/User/prompts"; return
  fi

  # 2) Native installs
  case "$(uname -s)" in
    Darwin)
      echo "${HOME}/Library/Application Support/${code_dir}/User/prompts" ;;
    Linux)
      echo "${HOME}/.config/${code_dir}/User/prompts" ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "${APPDATA:-${HOME}/AppData/Roaming}/${code_dir}/User/prompts" ;;
    *)
      echo "${HOME}/.config/${code_dir}/User/prompts" ;;
  esac
}

PROMPTS_DIR="$(detect_prompts_dir)"
SKILL_DIR="${PREFIX}/${SKILL_NAME}"

echo "Skill install root : ${SKILL_DIR}"
echo "VS Code prompts dir: ${PROMPTS_DIR}"
echo

# ---- uninstall path ----
if [[ "${UNINSTALL}" == "1" ]]; then
  if [[ -d "${SKILL_DIR}" ]]; then
    echo "Removing ${SKILL_DIR}"
    rm -rf "${SKILL_DIR}"
  fi
  if [[ -d "${PROMPTS_DIR}" ]]; then
    for f in "${SCRIPT_DIR}/prompts/"*.prompt.md; do
      [[ -e "$f" ]] || continue
      target="${PROMPTS_DIR}/$(basename "$f")"
      if [[ -f "${target}" ]]; then
        echo "Removing ${target}"
        rm -f "${target}"
      fi
    done
  fi
  echo "Uninstalled."
  exit 0
fi

# ---- sanity: must run from a checkout that has SKILL.md ----
if [[ ! -f "${SCRIPT_DIR}/SKILL.md" ]]; then
  echo "ERROR: SKILL.md not found next to install.sh." >&2
  echo "Run this script from inside the cloned codebase-audit repo." >&2
  exit 1
fi

# ---- install skill files ----
# Resolve both paths to canonical form so we can detect in-place installs.
abs_script_dir="$(cd "${SCRIPT_DIR}" && pwd -P)"
mkdir -p "${SKILL_DIR}"
abs_skill_dir="$(cd "${SKILL_DIR}" && pwd -P)"

if [[ "${abs_script_dir}" == "${abs_skill_dir}" ]]; then
  echo "Skill source and install dir are the same; skipping skill file copy."
else
  echo "Copying skill files..."
  cp -f "${SCRIPT_DIR}/SKILL.md" "${SKILL_DIR}/SKILL.md"
  for sub in workflows references; do
    if [[ -d "${SCRIPT_DIR}/${sub}" ]]; then
      mkdir -p "${SKILL_DIR}/${sub}"
      cp -f "${SCRIPT_DIR}/${sub}/"*.md "${SKILL_DIR}/${sub}/" 2>/dev/null || true
    fi
  done
  echo "  -> ${SKILL_DIR}"
fi

# ---- install VS Code slash-command prompts ----
if [[ -d "${SCRIPT_DIR}/prompts" ]]; then
  mkdir -p "${PROMPTS_DIR}"
  echo "Installing slash-command prompts..."
  for f in "${SCRIPT_DIR}/prompts/"*.prompt.md; do
    [[ -e "$f" ]] || continue
    cp -f "$f" "${PROMPTS_DIR}/$(basename "$f")"
    echo "  -> ${PROMPTS_DIR}/$(basename "$f")"
  done
fi

echo
echo "Done. Reload VS Code, then type / in Copilot Chat to see:"
echo "    /codebase-audit"
echo "    /codebase-audit-recon"
echo "    /codebase-audit-deploy"
echo "    /codebase-audit-audit"
echo "    /codebase-audit-fpcheck"
echo "    /codebase-audit-verify       (use inside a forked conversation)"
echo "    /codebase-audit-report"
echo
echo "You can also still trigger the skill by phrase, e.g."
echo "    'audit this app'  or  '/codebase-audit:recon'"
