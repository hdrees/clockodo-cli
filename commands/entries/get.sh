#!/usr/bin/env bash
# =============================================================================
# commands/entries/get.sh — Shows a single time entry by ID.
# Usage: `clockodo entries get <id> [--json|--help|-h]`
#
# /v2/entries/{id} wraps the entry in `entry` (not `data`), so the --json
# envelope is built with emit_json_success from that field.
#
# Dependencies: lib/http.sh, commands/entries/ui.sh.
# =============================================================================

set -euo pipefail

# cmd_entries_get
#   GETs /v2/entries/{id} and prints the result.
#   args:   $1 = entry ID (numeric) or --help/-h
#   exit:   0 on success, 1 on missing/invalid ID or API errors
cmd_entries_get() {
    if has_help_arg "$@"; then
        print_entries_help
        return 0
    fi

    local id="${1:-}"
    validate_numeric_id entry "${id}" || return 1

    local json
    if ! json="$(clockodo_api_get "/v2/entries/${id}")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_success "$(echo "${json}" | jq '.entry')"
    else
        print_entry_detail "$(echo "${json}" | jq '.entry')"
    fi
}
