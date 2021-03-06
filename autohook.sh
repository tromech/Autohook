#!/usr/bin/env bash

# Autohook
# A very, very small Git hook manager with focus on automation
# Author:   Nik Kantar <http://nkantar.com>
# Version:  2.1.1
# Website:  https://github.com/nkantar/Autohook

set -u

HOOKS_DIRNAME=.hooks
AUTOHOOK_SCRIPTNAME=autohook.sh

DEBUG=false

HOOK_TYPES=(
  "applypatch-msg"
  "commit-msg"
  "post-applypatch"
  "post-checkout"
  "post-commit"
  "post-merge"
  "post-receive"
  "post-rewrite"
  "post-update"
  "pre-applypatch"
  "pre-auto-gc"
  "pre-commit"
  "pre-push"
  "pre-rebase"
  "pre-receive"
  "prepare-commit-msg"
  "update"
)

error() {
  builtin echo "[Autohook ERROR] $@";
}
warn() {
  builtin echo "[Autohook WARN] $@";
}
info() {
  builtin echo "[Autohook INFO] $@";
}
debug() {
  if [[ $DEBUG == "true" ]]; then
    builtin echo "[Autohook DEBUG] $@";
  fi
}

called_as_hook() {
  CALLED_NAME="${1}"
  for HOOK_TYPE in "${HOOK_TYPES[@]}"; do
    if [[ "$CALLED_NAME" == "$HOOK_TYPE" ]]; then
      return 0
    fi
  done
  return 1
}

main() {
  CALLED_NAME=$(basename $0)

  if called_as_hook "${CALLED_NAME}" ; then
    HOOK_TYPE="${CALLED_NAME}"
    run_hooks "$@"
  else
    # Script got called directly (usually, for installing autohook)
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    cd "${SCRIPT_DIR}"

    if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
      error "script doesn't seem to be in a git work-tree, aborting"
      exit 1
    fi
    GIT_ROOT=$(git rev-parse --show-toplevel)
    if [[ "${GIT_ROOT}/${HOOKS_DIRNAME}" != "${SCRIPT_DIR}" ]]; then
      error "expecting to be placed in '${HOOKS_DIRNAME}'-subdir of git work-tree, aborting. Found ourselves at: ${SCRIPT_DIR}"
      exit 1
    fi
    cd "${GIT_ROOT}"
    if [[ "${CALLED_NAME}" == "${AUTOHOOK_SCRIPTNAME}" ]]; then
      if [[ $# -eq 2 && "${1}" == "install" ]]; then
        install "${2}"
      else
        error "To install autohook, call with arg: 'install <scope>'"
        exit 1
      fi
    fi
  fi
}

run_hooks() {
  GIT_ROOT=$(git rev-parse --show-toplevel)
  AUTOHOOKS_BASEDIR="${GIT_ROOT}/${HOOKS_DIRNAME}"
  if [[ ! -f "${AUTOHOOKS_BASEDIR}/.installed-scope" ]]; then
    error "Can't find autohook installed-scope, re-run install again first"
    exit 1
  fi
  SCOPE=$(cat "${AUTOHOOKS_BASEDIR}/.installed-scope")
  if [[ ! -d "${AUTOHOOKS_BASEDIR}/${SCOPE}" ]]; then
    error "Can't find scope-dir of autohook at ${AUTOHOOKS_BASEDIR}/${SCOPE}, re-run install again first?"
    exit 1
  fi
  SYMLINKS_DIR="${AUTOHOOKS_BASEDIR}/${SCOPE}/${HOOK_TYPE}"
  FILES=("$SYMLINKS_DIR"/*)
  FILES_COUNT="${#FILES[@]}"
  if [[ $FILES_COUNT == 1 ]]; then
    if [[ "$(basename ${FILES[0]})" == "*" ]]; then
      FILES_COUNT=0
    fi
  fi
  debug "Found ${FILES_COUNT} symlinks as ${HOOK_TYPE}"

  # Should preserve e.g. trailing newline this way
  STDIN=$(cat && echo end)
  STDIN=${STDIN%end}

  if [[ $FILES_COUNT -gt 0 ]]; then
    HOOK_EXITCODE=0
    info "Running ${FILES_COUNT} $HOOK_TYPE script(s)..."
    for FILE in "${FILES[@]}"; do
      SCRIPT_NAME=$(basename $FILE)
      if [[ -x "${FILE}" ]]; then
        debug "BEGIN $SCRIPT_NAME"
        printf %s "${STDIN}" | "${FILE}" "$@"
        SCRIPT_EXITCODE=$?
        if [[ $SCRIPT_EXITCODE != 0 ]]; then
          HOOK_EXITCODE=$SCRIPT_EXITCODE
        fi
        debug "FINISH $SCRIPT_NAME (exit code ${SCRIPT_EXITCODE})"
      else
        warn "Skipping ${SCRIPT_NAME}, not executable"
      fi
    done
    if [[ $HOOK_EXITCODE != 0 ]]; then
      info "A $HOOK_TYPE script yielded negative exit code $HOOK_EXITCODE"
      exit $HOOK_EXITCODE
    fi
  fi
}

install() {
  GIT_HOOKS_DIR=".git/hooks"
  if [[ ! -d "${GIT_HOOKS_DIR}" ]]; then
    error "Cannot find hooks-dir of git at ${GIT_HOOKS_DIR}, aborting"
    exit 1
  fi
  AUTOHOOK_LINKTARGET="../../${HOOKS_DIRNAME}/${AUTOHOOK_SCRIPTNAME}"
  if [[ $# -eq 1 ]]; then
    SCOPE="$1"
    if [[ -d "${HOOKS_DIRNAME}/${SCOPE}" ]]; then
      for HOOK_TYPE in "${HOOK_TYPES[@]}"; do
        HOOK_SYMLINK="${GIT_HOOKS_DIR}/${HOOK_TYPE}"
        if [[ ! -e "${HOOK_SYMLINK}" ]]; then
          info "Preparing hook for ${HOOK_TYPE}"
          ln -s "$AUTOHOOK_LINKTARGET" "$HOOK_SYMLINK"
        elif [[ -L "${HOOK_SYMLINK}" && "$(realpath "${HOOK_SYMLINK}")" == "$(realpath "${GIT_HOOKS_DIR}/${AUTOHOOK_LINKTARGET}")" ]]; then
          info "Preparing hook for ${HOOK_TYPE} (refresh)"
          ln -sf "$AUTOHOOK_LINKTARGET" "$HOOK_SYMLINK"
        else
          warn "Cannot set git-hook for ${HOOK_TYPE} (exists, not overriding)"
        fi
      done
      echo "$SCOPE" > "${HOOKS_DIRNAME}/.installed-scope"
    else
      error "Can't install with scope ${SCOPE}, can't find hooks base-dir ${HOOKS_DIRNAME}/${SCOPE}"
      exit 1
    fi
  fi
}

main "$@"
