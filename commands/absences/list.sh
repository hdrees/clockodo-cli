#!/usr/bin/env bash
# =============================================================================
# commands/absences/list.sh — Lists absences.
# Usage: `clockodo absences list [me|<user-id>] [--json|--help|-h]`
#
# Without argument: every user (no filter). With `me`: resolve the current
# user's ID via /v4/users/me. With a numeric ID: only that user.
#
# Filter is passed via Clockodo's deepObject query syntax: `filter%5Busers_id%5D=…`.
#
# Dependencies: lib/user_argument.sh, commands/absences/ui.sh.
# =============================================================================

set -euo pipefail

# cmd_absences_list
#   GETs /v4/absences (optionally with `filter%5Busers_id%5D=…`) and renders.
#   args:   [me|<user-id>] (or --help / -h)
cmd_absences_list() {
    if has_help_arg "$@"; then
        print_absences_help
        return 0
    fi

    resolve_user_argument "${1:-}" || return 1

    local path="/v4/absences"
    if [[ -n "${RESOLVED_USER_ID}" ]]; then
        path+="?filter%5Busers_id%5D=${RESOLVED_USER_ID}"
    fi

    local json
    if ! json="$(clockodo_api_get "${path}")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_data "${json}"
    else
        print_absences_table "${json}"
    fi
}
