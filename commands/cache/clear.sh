#!/usr/bin/env bash
# =============================================================================
# commands/cache/clear.sh — Deletes every cache entry of the configured account.
# Usage: `clockodo cache clear [--json|--help|-h]`
#
# Dependencies: lib/cache.sh, commands/cache/guards.sh.
# =============================================================================

set -euo pipefail

# cmd_cache_clear
#   Deletes every cache entry of the configured account.
#   args:   --help / -h
#   stdout: confirmation line, or the JSON envelope ({"deleted_entries": <n>})
#   exit:   0 on success, 1 on --curl or unknown arguments
cmd_cache_clear() {
    if has_help_arg "$@"; then
        print_cache_help
        return 0
    fi
    reject_curl_for_cache_command || return 1
    if (( $# > 0 )); then
        emit_argument_error "unknown argument: $1"
        return 1
    fi

    local count
    count="$(clockodo_cache_clear)"

    if is_json_output_mode; then
        emit_json_success "$(jq -n --argjson count "${count}" '{deleted_entries:$count}')"
    else
        echo "Deleted ${count} cache entries."
    fi
}
