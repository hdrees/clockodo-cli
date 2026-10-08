#!/usr/bin/env bash
# =============================================================================
# commands/cache/list.sh — Lists the cache entries (statistics only).
# Usage: `clockodo cache list [--json|--help|-h]`
#
# Dependencies: lib/cache.sh, commands/cache/guards.sh, commands/cache/ui.sh.
# =============================================================================

set -euo pipefail

# cmd_cache_list
#   Prints the statistics of every cache entry of the configured account.
#   args:   --help / -h
#   stdout: table + summary, or the JSON envelope in --json mode
#           (data = array of entry statistics, see _cache_entry_statistics)
#   exit:   0 on success, 1 on --curl or unknown arguments
cmd_cache_list() {
    if has_help_arg "$@"; then
        print_cache_help
        return 0
    fi
    reject_curl_for_cache_command || return 1
    if (( $# > 0 )); then
        emit_argument_error "unknown argument: $1"
        return 1
    fi

    local entries_json
    entries_json="$(clockodo_cache_entries)"

    if is_json_output_mode; then
        emit_json_success "${entries_json}"
    else
        print_cache_entries_table "${entries_json}" "$(_cache_dir)"
    fi
}
