#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BASE="${SCRIPT_DIR}/tmp"
REPO="${BASE}/test-repo"
REPO2="${BASE}/test-repo2"

SILENT_RUN=true

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

assert_equal_or_fail() {
  local CONTEXT="${1}"

  local EXPECTED="${2}"
  local ACTUAL="${3}"

  if [[ "${EXPECTED}" != "${ACTUAL}" ]]; then
    fail_msg "Comparison failure: ${CONTEXT}\n  Expected: '${EXPECTED}'\n    Actual: '${ACTUAL}'"
    exit 1
  fi
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
    if [[ "${SILENT_RUN}" != "true" ]]; then
      [[ -n "$TEST_OUTPUT" ]] && echo "$TEST_OUTPUT"
    fi
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

setup_2nd_bare_git_dir() {
  purge_2nd_bare_git_dir
  mkdir -p "${REPO2}"

  OLD_GIT_WORK_TREE="${GIT_WORK_TREE}"
  OLD_GIT_DIR="${GIT_DIR}"

  unset GIT_WORK_TREE
  unset GIT_DIR

  cd "${REPO2}"
  git init --bare . &>/dev/null || fail "Failed to init 2nd (bare) git directory"
  cd - >/dev/null

  export GIT_WORK_TREE="${OLD_GIT_WORK_TREE}"
  export GIT_DIR="${OLD_GIT_DIR}"
}

purge_2nd_bare_git_dir() {
  [[ -e "${REPO2}" ]] && rm -rf "${REPO2}"
}

autohook_install() {
  mkdir "${REPO}/.hooks"
  cp "${REPO}/../../autohook.sh" "${REPO}/.hooks/" || fail "Can't copy autohook.sh"
  mkdir "${REPO}/.hooks/scope"
  "${REPO}/.hooks/autohook.sh" install scope || fail "autohook install failed"
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
  mkdir -p "${REPO}/.hooks/scope/pre-commit"
  cat >"${REPO}/.hooks/pre-commit/scope/no-no-never" <<EOF
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
  mkdir "${REPO}/.hooks/scope/pre-commit"
  cat >"${REPO}/.hooks/scope/pre-commit/no-no-never" <<EOF
#!/bin/sh
exit 1
EOF
  chmod +x "${REPO}/.hooks/scope/pre-commit/no-no-never"
  do_commit "dummy" "Just trying"
  [[ $( git rev-list HEAD | wc -l ) == 1 ]] || fail "Expected commit attempt to have failed, due to pre-commit hook"
  purge_test_git_dir
}

test_multiple_pre_commits_hooks_order() {
  setup_test_git_dir
  autohook_install
  do_commit "initial" "Initial commit"
  [[ $( git rev-list HEAD | wc -l ) == 1 ]] || fail "Expected one commit to exist after initial"
  mkdir "${REPO}/.hooks/scope/pre-commit"
  cat >"${REPO}/.hooks/scope/pre-commit/01-first" <<EOF
#!/bin/sh
echo -n 1 >> "${REPO}/tmp-hooks-output"
EOF
  cat >"${REPO}/.hooks/scope/pre-commit/02-second" <<EOF
#!/bin/sh
echo -n 2 >> "${REPO}/tmp-hooks-output"
EOF
  cat >"${REPO}/.hooks/scope/pre-commit/03-third" <<EOF
#!/bin/sh
echo -n 3 >> "${REPO}/tmp-hooks-output"
EOF
  chmod +x "${REPO}"/.hooks/scope/pre-commit/*
  do_commit "dummy" "Something"
  [[ $( git rev-list HEAD | wc -l ) == 2 ]] || fail "Expected two commits after commit"
  [[ -f "${REPO}/tmp-hooks-output" ]] || fail "Expected result file from hooks not found"
  [[ "$( cat "${REPO}/tmp-hooks-output" )" == "123" ]] || fail "Expected result 123, from hooks in order"
  purge_test_git_dir
}

test_commit_msg_hook_override() {
  setup_test_git_dir
  autohook_install
  do_commit "initial" "Initial commit"
  [[ $( git rev-list HEAD | wc -l ) == 1 ]] || fail "Expected one commit to exist after initial"
  mkdir "${REPO}/.hooks/scope/commit-msg"
  cat >"${REPO}/.hooks/scope/commit-msg/override" <<EOF
#!/bin/sh
MSGFILE="\$1"
if [ ! -f "\$MSGFILE" ]; then
  echo "Error: can't find message file \$MSGFILE"
  exit 1
fi
echo "Nope -> I'll tell you what a subject line is" > "\$MSGFILE"
EOF
echo $?
#  cat "${REPO}/.hooks/scope/commit-msg/override"
  chmod +x "${REPO}/.hooks/scope/commit-msg/override"
  do_commit "dummy" "Whatever" || fail "Unexpected failure of commit"
  [[ $( git rev-list HEAD | wc -l ) == 2 ]] || fail "Expected two commits to exist after another commit"
  COMMIT_MSG=$(git show -s --format="%s" HEAD)
  [[ "$COMMIT_MSG" == "Nope -> I'll tell you what a subject line is" ]] || fail "Expected full commit msg override, but found: '${COMMIT_MSG}'"
  purge_test_git_dir
}

test_pre_push_hook_args_and_stdin() {
  setup_test_git_dir
  autohook_install
  do_commit "initial" "Initial commit"
  [[ $( git rev-list HEAD | wc -l ) == 1 ]] || fail "Expected one commit to exist after initial" 

  setup_2nd_bare_git_dir
  git remote add other "${REPO2}" || fail "Failed to add remote"
  git push other master || fail "Failed pushing to remote"

  mkdir "${REPO}/.hooks/scope/pre-push"
  cat >"${REPO}/.hooks/scope/pre-push/sample" <<EOF
#!/bin/sh
mkdir -p "${REPO}/tmp/"
echo -n "\$1" > "${REPO}/tmp/push-remote-name"
echo -n "\$2" > "${REPO}/tmp/push-remote-url"
cat > "${REPO}/tmp/push-stdin"
exit 0
EOF
  chmod +x "${REPO}/.hooks/scope/pre-push/sample"
  do_commit "foo" "Something"
  do_commit "bar" "Something else"
  do_commit "baz" "And yet some more"
  [[ $( git rev-list HEAD | wc -l ) == 4 ]] || fail "Expected 2nd commit to be created"

  git push other master || fail "Failed pushing to remote"
  [[ -f "${REPO}/tmp/push-remote-name" ]] || fail "Expected file from hook not found (name)"
  [[ -f "${REPO}/tmp/push-remote-url" ]] || fail "Expected file from hook not found (url)"
  [[ "$(cat ${REPO}/tmp/push-remote-name)" == "other" ]] || fail "Unexpected content of remote url: '$(cat ${REPO}/tmp/push-remote-name)'"
  [[ "$(cat ${REPO}/tmp/push-remote-url)" == "${REPO2}" ]] || fail "Unexpected content of remote url: '$(cat ${REPO}/tmp/push-remote-url)'"

  [[ -f "${REPO}/tmp/push-stdin" ]] || fail "Expected file from hook not found (stdin)"
  [[ $( cat "${REPO}/tmp/push-stdin" | wc -l ) -eq 1 ]] || fail "Expected 1 result line from hook"
  ACTUAL_PUSH_LINE=$(cat "${REPO}/tmp/push-stdin")

  SHA_OLD=$(git show -s --format="%H" HEAD~3)
  SHA_NEW=$(git show -s --format="%H" HEAD)
  EXPECTED_PUSH_LINE="refs/heads/master ${SHA_NEW} refs/heads/master ${SHA_OLD}"

  assert_equal_or_fail "check for stdin" "${EXPECTED_PUSH_LINE}" "${ACTUAL_PUSH_LINE}"
  purge_2nd_bare_git_dir
  purge_test_git_dir
}

test install_autohook
test plain_commit
test pre_commit_hook_must_be_executable
test pre_commit_hook_rejects_commit
test multiple_pre_commits_hooks_order
test commit_msg_hook_override
test pre_push_hook_args_and_stdin
