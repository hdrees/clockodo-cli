#!/usr/bin/env bash
# =============================================================================
# lib/upgrade.sh — `clockodo upgrade`: updates the git checkout of the CLI to
# the latest `main` of its `origin` remote.
#
# Fast-forward only: the upgrade refuses a checkout that is not on `main`,
# has uncommitted changes to tracked files, or has local commits that are not
# on `origin/main`, so it never merges, rebases or discards anything.
# Untracked files (e.g. .env) are left alone. With --dry-run it fetches and
# reports the available update without applying it.
#
# A top-level command, dispatched by the entry script before .env is loaded:
# it talks to git only, nothing is sent to Clockodo.
#
# Dependencies: lib/helper.sh, git, jq. Requires REPO_ROOT.
# =============================================================================

set -euo pipefail

# Remote and branch the upgrade follows.
UPGRADE_REMOTE="origin"
UPGRADE_BRANCH="main"

# print_upgrade_help
#   Help text for `clockodo upgrade`.
print_upgrade_help() {
    cat <<'EOF'
clockodo upgrade — update the CLI to the latest main branch

Usage:
  clockodo upgrade [--dry-run] [--json]

Fetches origin/main and fast-forwards the local checkout. Refuses when the
checkout is not on main, has uncommitted changes to tracked files or local
commits that are not on origin/main; nothing is merged or discarded.
Untracked files such as .env are not touched.

  --dry-run   Fetch only and report whether an update is available.

Not supported with --curl (nothing is sent to the Clockodo API).
EOF
}

# cmd_upgrade
#   Checks the checkout, fetches and fast-forwards it.
#   args:    $1 optional --help/-h
#   stdout:  result line, or the JSON envelope in --json mode
#            ({status, previous_version, current_version, previous_commit,
#            current_commit, commits}; status up_to_date | upgraded |
#            update_available (--dry-run) | ahead)
#   exit:    0 on success, 1 if the checkout cannot be upgraded
cmd_upgrade() {
    if has_help_arg "$@"; then
        print_upgrade_help
        return 0
    fi
    if is_curl_output_mode; then
        emit_argument_error "upgrade sends no API request; --curl is not supported"
        return 1
    fi
    if (( $# > 0 )); then
        emit_argument_error "unknown argument: $1"
        return 1
    fi

    _upgrade_check_checkout || return 1

    local git_error
    if ! git_error="$(git -C "${REPO_ROOT}" fetch --quiet "${UPGRADE_REMOTE}" "${UPGRADE_BRANCH}" 2>&1)"; then
        _report_upgrade_failure "git fetch ${UPGRADE_REMOTE} ${UPGRADE_BRANCH} failed: ${git_error}" "fetch_failed"
        return 1
    fi

    # FETCH_HEAD is the commit just fetched, independent of how the remote's
    # tracking refs are configured.
    local previous_commit fetched_commit
    previous_commit="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
    fetched_commit="$(git -C "${REPO_ROOT}" rev-parse FETCH_HEAD)"

    if [[ "${previous_commit}" == "${fetched_commit}" ]]; then
        _report_upgrade_result up_to_date "${previous_commit}" "${previous_commit}"
        return 0
    fi
    if git -C "${REPO_ROOT}" merge-base --is-ancestor FETCH_HEAD HEAD; then
        _report_upgrade_result ahead "${previous_commit}" "${previous_commit}"
        return 0
    fi
    if ! git -C "${REPO_ROOT}" merge-base --is-ancestor HEAD FETCH_HEAD; then
        _report_upgrade_failure "local ${UPGRADE_BRANCH} has commits that are not on ${UPGRADE_REMOTE}/${UPGRADE_BRANCH}; merge or rebase manually" "diverged"
        return 1
    fi

    if is_dry_run_mode; then
        _report_upgrade_result update_available "${previous_commit}" "${fetched_commit}"
        return 0
    fi

    if ! git_error="$(git -C "${REPO_ROOT}" merge --ff-only --quiet FETCH_HEAD 2>&1)"; then
        _report_upgrade_failure "fast-forward failed: ${git_error}" "upgrade_failed"
        return 1
    fi
    _report_upgrade_result upgraded "${previous_commit}" "${fetched_commit}"
}

# _upgrade_check_checkout
#   Preconditions: git installed, REPO_ROOT is a git checkout on the upgrade
#   branch, no uncommitted changes to tracked files.
#   exit:  0 if all hold, 1 (error reported) otherwise
_upgrade_check_checkout() {
    if ! command -v git >/dev/null 2>&1; then
        _report_upgrade_failure "'git' is not installed" "missing_dependency"
        return 1
    fi
    if ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _report_upgrade_failure "${REPO_ROOT} is not a git checkout; reinstall with git clone" "not_a_git_checkout"
        return 1
    fi

    local branch
    # `-q` prints nothing (exit 1) on a detached HEAD instead of an error.
    branch="$(git -C "${REPO_ROOT}" symbolic-ref --short -q HEAD || true)"
    if [[ "${branch}" != "${UPGRADE_BRANCH}" ]]; then
        _report_upgrade_failure "checkout is on '${branch:-detached HEAD}', not on ${UPGRADE_BRANCH}" "not_on_main"
        return 1
    fi

    # `--untracked-files=no`: untracked files (.env, caches) are no obstacle.
    if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=no)" ]]; then
        _report_upgrade_failure "checkout has uncommitted changes to tracked files; commit or stash them first" "dirty_worktree"
        return 1
    fi
}

# _upgrade_version_at
#   Prints the CLI version recorded in the entry script of a commit.
#   args:    $1 = commit
#   stdout:  MAJOR.MINOR.PATCH, or "unknown"
_upgrade_version_at() {
    local script
    script="$(git -C "${REPO_ROOT}" show "$1:clockodo" 2>/dev/null || true)"
    # Multi-line regex match: `BASH_REMATCH[1]` holds the captured version.
    local version_pattern='CLOCKODO_CLI_VERSION="([0-9]+\.[0-9]+\.[0-9]+)"'
    if [[ "${script}" =~ ${version_pattern} ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "unknown"
    fi
}

# _report_upgrade_result
#   args:    $1 = status (up_to_date | upgraded | update_available | ahead),
#            $2 = commit before, $3 = commit after (the fetched one for
#            update_available)
#   stdout:  result line, or the JSON envelope in --json mode
_report_upgrade_result() {
    local status="$1" previous_commit="$2" current_commit="$3"
    local previous_version current_version commits
    previous_version="$(_upgrade_version_at "${previous_commit}")"
    current_version="$(_upgrade_version_at "${current_commit}")"
    commits="$(git -C "${REPO_ROOT}" rev-list --count "${previous_commit}..${current_commit}")"

    if is_json_output_mode; then
        emit_json_success "$(jq -n \
            --arg status "${status}" \
            --arg previous_version "${previous_version}" \
            --arg current_version "${current_version}" \
            --arg previous_commit "${previous_commit}" \
            --arg current_commit "${current_commit}" \
            --argjson commits "${commits}" \
            '{status:$status, previous_version:$previous_version, current_version:$current_version,
              previous_commit:$previous_commit, current_commit:$current_commit, commits:$commits}')"
        return 0
    fi

    case "${status}" in
        up_to_date)       echo "Already up to date (${previous_version})." ;;
        ahead)            echo "Local ${UPGRADE_BRANCH} is ahead of ${UPGRADE_REMOTE}/${UPGRADE_BRANCH} (${previous_version}), nothing to upgrade." ;;
        update_available) echo "Update available: ${previous_version} → ${current_version} (${commits} commits). Run without --dry-run to apply." ;;
        upgraded)         echo "Upgraded: ${previous_version} → ${current_version} (${commits} commits)." ;;
    esac
}

# _report_upgrade_failure
#   Failure envelope in --json mode, "Error: …" on stderr otherwise.
#   args:  $1 = message, $2 = code
_report_upgrade_failure() {
    if is_json_output_mode; then
        emit_json_failure "$1" "$2"
    else
        echo "Error: $1" >&2
    fi
}
