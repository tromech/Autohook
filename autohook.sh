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
    run_hooks "${CALLED_NAME}"
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
      if [[ $# -ge 1 && "${1}" == "install" ]]; then
        install
      else
        error "To install autohook, call with arg: 'install'"
        exit 1
      fi
    fi
  fi
}

run_hooks() {
  local HOOK_TYPE="${1}"

  GIT_ROOT=$(git rev-parse --show-toplevel)
  SYMLINKS_DIR="${GIT_ROOT}/${HOOKS_DIRNAME}/${HOOK_TYPE}"
  FILES=("$SYMLINKS_DIR"/*)
  FILES_COUNT="${#FILES[@]}"
  if [[ $FILES_COUNT == 1 ]]; then
    if [[ "$(basename ${FILES[0]})" == "*" ]]; then
      FILES_COUNT=0
    fi
  fi
  debug "Found ${FILES_COUNT} symlinks as ${HOOK_TYPE}"

  if [[ $FILES_COUNT -gt 0 ]]; then
    HOOK_EXITCODE=0
    info "Running ${FILES_COUNT} $HOOK_TYPE script(s)..."
    for FILE in "${FILES[@]}"; do
      SCRIPT_NAME=$(basename $FILE)
      if [[ -x "${FILE}" ]]; then
        debug "BEGIN $SCRIPT_NAME"
        eval $FILE
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
  for HOOK_TYPE in "${HOOK_TYPES[@]}"; do
    HOOK_SYMLINK="${GIT_HOOKS_DIR}/${HOOK_TYPE}"
    ln -s "$AUTOHOOK_LINKTARGET" "$HOOK_SYMLINK"
  done
}

main "$@"
