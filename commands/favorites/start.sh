#!/usr/bin/env bash
# =============================================================================
# commands/favorites/start.sh — Starts a Clockodo favorite.
#
# Two call variants:
#   1. with ID:      clockodo favorites start 12345
#   2. interactive:  clockodo favorites start   (picker via bash select)
#
# Dependencies: lib/http.sh, lib/cache.sh, commands/favorites/ui.sh;
# FAVORITES_CACHE_TTL is defined in commands/favorites/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_favorites_start
#   Starts a favorite via POST /v2/favorites/{id}/start.
#   args:   $1 optional favorite ID (numeric) or "--help"/"-h"
#   stdout: confirmation line with the entry ID
#   stderr: error text on cancel, invalid ID, or HTTP error
#   exit:   0 on success, 1 on cancel/invalid ID or API errors.
cmd_favorites_start() {
    if has_help_arg "$@"; then
        print_favorites_help
        return 0
    fi

    # `${1:-}` → empty string when no argument is given; required for set -u.
    local favorite_id="${1:-}"

    # --- Interactive selection when no ID was passed ----------------------
    if [[ -z "${favorite_id}" ]]; then
        # Interactive picker is incompatible with --json mode (no stdout
        # noise, no stdin prompts) and with --curl (the picker would need a
        # real list request). Require an explicit ID instead.
        if is_json_output_mode || is_curl_output_mode; then
            emit_argument_error "favorite ID is required in --json and --curl mode" "missing_argument"
            return 1
        fi
        local json
        if ! json="$(clockodo_api_get_cached /v2/favorites "${FAVORITES_CACHE_TTL}")"; then
            emit_api_failure
            return 1
        fi
        favorite_id="$(echo "${json}" | select_favorite)" || {
            echo "Aborted." >&2
            return 1
        }
    fi

    validate_numeric_id favorite "${favorite_id}" || return 1

    # --- API call ----------------------------------------------------------
    local response
    if ! response="$(clockodo_api_post "/v2/favorites/${favorite_id}/start")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_success "${response}"
    else
        # Short confirmation. `.running.id` is the ID of the freshly started
        # clock entry; `// "?"` catches the case where the field is missing.
        echo "${response}" | jq -r '"Started: entry ID \(.running.id // "?")"'
    fi
}
