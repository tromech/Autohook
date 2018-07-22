#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BASE="${SCRIPT_DIR}/tmp"
REPO="${BASE}/test-repo"

mkdir -p "${BASE}"
cd "${BASE}"

_TEST="\033[33m"
_OK="\033[32m"
_FAIL="\033[31m"
_RST="\033[0m"

test_msg() {
  echo -e "${_TEST}?︎ $@${_RST}" >&2
}
okay_msg() {
  echo -e "${_OK}✔︎ $@${_RST}" >&2
}
fail_msg() {
  echo -e "${_FAIL}✘ $@${_RST}" >&2
}

fail() {
  fail_msg "Failure:" "$@"
  exit 1
}

# Core test-function - Runs each test in a subprocess. Allows tests
#      to exit on assertion failures without stopping the whole script
# $1 - name of test to run (function "test_${1}" must exist)
test() {
  local TEST_FUNCTION="test_${1}"

  if [[ $( type -t "${TEST_FUNCTION}" ) == "function" ]]; then
    test_msg "Running testcase ${TEST_FUNCTION}..."
    TEST_OUTPUT=$( ${TEST_FUNCTION} 2>&1 )
    TEST_RESULT=$?
    [[ -n "$TEST_OUTPUT" ]] && echo "$TEST_OUTPUT"
    if [[ ${TEST_RESULT} -eq 0 ]]; then
      okay_msg "Testcase ${TEST_FUNCTION}: pass"
    else
      fail_msg "Testcase ${TEST_FUNCTION}: fail"
    fi
  else
    fail "Couldn't find test-function ${TEST_FUNCTION}"
  fi
}

setup_test_git_dir() {
  purge_test_git_dir
  mkdir -p "${REPO}"
  cd "${REPO}"
  git init . &>/dev/null || fail "Failed to init git directory"
  cd - >/dev/null
}

purge_test_git_dir() {
  [[ -e "${REPO}" ]] && rm -rf "${REPO}"
}

autohook_install() {
  mkdir "${REPO}/.hooks"
  cp "${REPO}/../../autohook.sh" "${REPO}/.hooks/" || fail "Can't copy autohook.sh"
  "${REPO}/.hooks/autohook.sh" install || fail "autohook install failed"
}

test_install_autohook() {
  setup_test_git_dir
  HOOK_TYPES=("applypatch-msg" "commit-msg" "post-applypatch" "post-checkout" "post-commit" "post-merge" "post-receive"
    "post-rewrite" "post-update" "pre-applypatch" "pre-auto-gc" "pre-commit" "pre-push" "pre-rebase" "pre-receive"
    "prepare-commit-msg" "update")
  for HT in "${HOOK_TYPES[@]}"; do
    [[ -h "${REPO}/.git/hooks/${HT}" ]] && fail "Link for ${HT} already installed"
  done
  autohook_install
  for HT in "${HOOK_TYPES[@]}"; do
    [[ -h "${REPO}/.git/hooks/${HT}" ]] || fail "Link for ${HT} didn't get installed"
    TARGET=$(realpath "${REPO}/.git/hooks/${HT}")
    [[ "$TARGET" == "${REPO}/.hooks/autohook.sh" ]] || fail "Link for ${HT} points to ${TARGET} - expected ${REPO}/.hooks/autohook.sh"
  done
  purge_test_git_dir
}

test install_autohook
