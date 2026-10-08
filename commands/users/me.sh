#!/usr/bin/env bash
# =============================================================================
# commands/users/me.sh — Shows the currently authenticated user.
# Usage: `clockodo users me [--json|--help|-h]`
#
# Uses fetch_current_user (lib/user_argument.sh): /v4/users/me, cached for
# USERS_ME_CACHE_TTL with CACHE=1 (per account, so it cannot go stale
# relative to a different API key).
# =============================================================================

set -euo pipefail

# cmd_users_me
#   GETs /v4/users/me and prints the result (Key/Value block or JSON envelope).
cmd_users_me() {
    if has_help_arg "$@"; then
        print_users_help
        return 0
    fi

    local json
    if ! json="$(fetch_current_user)"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_data "${json}"
    else
        print_user_detail "${json}"
    fi
}
