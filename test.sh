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

  # Makes git subcommands know the repo location
  export GIT_WORK_TREE="${REPO}"
  export GIT_DIR="${REPO}/.git"
}

purge_test_git_dir() {
  [[ -e "${REPO}" ]] && rm -rf "${REPO}"

  unset GIT_WORK_TREE
  unset GIT_DIR
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

do_commit() {
  [[ $# -eq 2 ]] || fail "do_commit args: <dummy-filename-to-touch> <commit-message>"
  touch "${REPO}/$1"
  git add "$1"
  git commit -am "$2"
  return $?
}

test_plain_commit() {
  setup_test_git_dir
  autohook_install
  git rev-parse --verify HEAD >/dev/null 2>&1 && fail "Expecting HEAD to be invalid ref at start"
  do_commit "initial" "Initial commit"
  git rev-parse --verify HEAD >/dev/null 2>&1 || fail "Expecting HEAD to be valid ref after first commit"
  [[ $( git rev-list HEAD | wc -l ) == 1 ]] || fail "Expected one commit to exist after initial"
  purge_test_git_dir
}

test_pre_commit_hook_must_be_executable() {
  setup_test_git_dir
  autohook_install
  do_commit "initial" "Initial commit"
  [[ $( git rev-list HEAD | wc -l ) == 1 ]] || fail "Expected one commit to exist after initial"
  mkdir "${REPO}/.hooks/pre-commit"
  cat >"${REPO}/.hooks/pre-commit/no-no-never" <<EOF
#!/bin/sh
exit 1
EOF
  do_commit "dummy" "Just trying"
  [[ $( git rev-list HEAD | wc -l ) == 2 ]] || fail "Expected pre-commit hook to be ignored, since not executable"
  purge_test_git_dir
}

test_pre_commit_hook_rejects_commit() {
  setup_test_git_dir
  autohook_install
  do_commit "initial" "Initial commit"
  [[ $( git rev-list HEAD | wc -l ) == 1 ]] || fail "Expected one commit to exist after initial"
  mkdir "${REPO}/.hooks/pre-commit"
  cat >"${REPO}/.hooks/pre-commit/no-no-never" <<EOF
#!/bin/sh
exit 1
EOF
  chmod +x "${REPO}/.hooks/pre-commit/no-no-never"
  do_commit "dummy" "Just trying"
  [[ $( git rev-list HEAD | wc -l ) == 1 ]] || fail "Expected commit attempt to have failed, due to pre-commit hook"
  purge_test_git_dir
}

test install_autohook
test plain_commit
test pre_commit_hook_must_be_executable
test pre_commit_hook_rejects_commit
