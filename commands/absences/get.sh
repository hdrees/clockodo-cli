#!/usr/bin/env bash
# =============================================================================
# commands/absences/get.sh — Shows a single absence by ID.
# Usage: `clockodo absences get <id> [--json|--help|-h]`
#
# Dependencies: commands/absences/ui.sh.
# =============================================================================

set -euo pipefail

# cmd_absences_get
#   GETs /v4/absences/{id} and prints the result.
#   args:   $1 numeric absence ID (or --help / -h)
cmd_absences_get() {
    if has_help_arg "$@"; then
        print_absences_help
        return 0
    fi

    local id="${1:-}"
    validate_numeric_id absence "${id}" || return 1

    local json
    if ! json="$(clockodo_api_get "/v4/absences/${id}")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_data "${json}"
    else
        print_absence_detail "${json}"
    fi
}
