#!/usr/bin/env bash
# =============================================================================
# commands/targethours/list.sh — Lists target-hours entries.
# Usage: `clockodo targethours list [me|<user-id>] [--json|--help|-h]`
#
# Without argument: every user (no filter). With `me`: resolve the current
# user's ID via /v4/users/me. With a numeric ID: only that user.
#
# Dependencies: lib/user_argument.sh, lib/target_hours.sh,
# commands/targethours/ui.sh.
# =============================================================================

set -euo pipefail

# cmd_targethours_list
#   GETs /targethours (optionally with `users_id=…`, cached with CACHE=1)
#   and renders the result.
#   args:   [me|<user-id>] (or --help / -h)
cmd_targethours_list() {
    if has_help_arg "$@"; then
        print_targethours_help
        return 0
    fi

    resolve_user_argument "${1:-}" || return 1

    # fetch_target_hours normalizes the API's `.targethours` wrapper to `.data`.
    local json
    if ! json="$(fetch_target_hours "${RESOLVED_USER_ID}")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_data "${json}"
    else
        print_targethours_table "${json}"
    fi
}
