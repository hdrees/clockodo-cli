#!/usr/bin/env bash
# =============================================================================
# commands/targethours/get.sh — Shows a single target-hours entry by ID.
# Usage: `clockodo targethours get <id> [--json|--help|-h]`
#
# Dependencies: commands/targethours/ui.sh.
# =============================================================================

set -euo pipefail

# cmd_targethours_get
#   GETs /targethours/{id} and prints the result.
#   args:    $1 numeric target-hours entry ID (or --help / -h)
cmd_targethours_get() {
    if has_help_arg "$@"; then
        print_targethours_help
        return 0
    fi

    local id="${1:-}"
    validate_numeric_id "target-hours entry" "${id}" || return 1

    local raw
    if ! raw="$(clockodo_api_get "/targethours/${id}")"; then
        emit_api_failure
        return 1
    fi

    # Same normalization as list.sh: the API wraps the entity in
    # `.targethoursRow`; we rewrap to `.data` for envelope/renderer parity.
    local normalized
    normalized="$(echo "${raw}" | jq '{data: .targethoursRow}')"

    if is_json_output_mode; then
        emit_json_data "${normalized}"
    else
        print_targethour_detail "${normalized}"
    fi
}
