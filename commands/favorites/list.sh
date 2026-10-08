#!/usr/bin/env bash
# =============================================================================
# commands/favorites/list.sh — Lists all Clockodo favorites as a table.
#
# Usage: `clockodo favorites list [--json|--help|-h]`
#
# The table keeps the API order — the user-defined favorite order in
# Clockodo is a domain order.
#
# Dependencies: lib/cache.sh, commands/favorites/ui.sh;
# FAVORITES_CACHE_TTL is defined in commands/favorites/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_favorites_list
#   Fetches /v2/favorites and renders the result as a formatted table.
#   args:   $1 optional "--help" / "-h"
#   stdout: table with ID and name
#   exit:   0 on success, otherwise propagated from _clockodo_request.
cmd_favorites_list() {
    # Allow --help / -h directly on the action.
    if has_help_arg "$@"; then
        print_favorites_help
        return 0
    fi

    # API call. The `if !` form disarms `set -e` so we can react to failure
    # and build a proper failure envelope in --json mode.
    local json
    if ! json="$(clockodo_api_get_cached /v2/favorites "${FAVORITES_CACHE_TTL}")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_data "${json}"
    else
        print_favorites_table "${json}"
    fi
}
