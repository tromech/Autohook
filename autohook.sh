#!/usr/bin/env bash

# Autohook
# A very, very small Git hook manager with focus on automation
# Author:   Nik Kantar <http://nkantar.com>
# Version:  2.1.1
# Website:  https://github.com/nkantar/Autohook

DEBUG=false

info() {
  builtin echo "[Autohook INFO] $@";
}

debug() {
  if [[ $DEBUG == "true" ]]; then
    builtin echo "[Autohook DEBUG] $@";
  fi
}

install() {
  hook_types=(
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

  repo_root=$(git rev-parse --show-toplevel)
  hooks_dir="$repo_root/.git/hooks"
  autohook_linktarget="../../$base_dirname/autohook.sh"
  for hook_type in "${hook_types[@]}"; do
    hook_symlink="$hooks_dir/$hook_type"
    ln -s $autohook_linktarget $hook_symlink
  done
}


main() {
  calling_file=$(basename $0)

  base_dirname=.hooks
  if [[ $calling_file == "autohook.sh" ]]; then
    command=$1
    if [[ $command == "install" ]]; then
      install
    fi
  else
    repo_root=$(git rev-parse --show-toplevel)
    hook_type=$calling_file
    symlinks_dir="$repo_root/$base_dirname/$hook_type"
    files=("$symlinks_dir"/*)
    number_of_symlinks="${#files[@]}"
    if [[ $number_of_symlinks == 1 ]]; then
      if [[ "$(basename ${files[0]})" == "*" ]]; then
        number_of_symlinks=0
      fi
    fi
    debug "Looking for $hook_type scripts to run...found $number_of_symlinks"
    if [[ $number_of_symlinks -gt 0 ]]; then
      hook_exit_code=0
      info "Running ${number_of_symlinks} $hook_type script(s)..."
      for file in "${files[@]}"; do
        scriptname=$(basename $file)
        debug "BEGIN $scriptname"
        eval $file
        script_exit_code=$?
        if [[ $script_exit_code != 0 ]]; then
          hook_exit_code=$script_exit_code
        fi
        debug "FINISH $scriptname (exit code ${script_exit_code})"
      done
      if [[ $hook_exit_code != 0 ]]; then
        info "A $hook_type script yielded negative exit code $hook_exit_code"
        exit $hook_exit_code
      fi
    fi
  fi
}


main "$@"
