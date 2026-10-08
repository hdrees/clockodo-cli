#!/usr/bin/env bash
# =============================================================================
# commands/cache/delete.sh — Deletes a single cache entry.
# Usage: `clockodo cache delete <key|path> [--json|--help|-h]`
#
# Dependencies: lib/cache.sh, commands/cache/guards.sh.
# =============================================================================

set -euo pipefail

# cmd_cache_delete
#   Deletes the cache entry given by key (see `cache list`) or endpoint path.
#   args:   $1 = key or endpoint path (or --help / -h)
#   stdout: confirmation line, or the JSON envelope ({"deleted": <key>})
#   exit:   0 if deleted, 1 on a missing/invalid argument or unknown entry
cmd_cache_delete() {
    if has_help_arg "$@"; then
        print_cache_help
        return 0
    fi
    reject_curl_for_cache_command || return 1

    local argument="${1:-}"
    if [[ -z "${argument}" ]]; then
        emit_argument_error "cache key or endpoint path is required (see: clockodo cache list)" "missing_argument"
        return 1
    fi

    # `|| status=$?` keeps `set -e` from aborting on the non-zero codes.
    local deleted_key status=0
    deleted_key="$(clockodo_cache_delete "${argument}")" || status=$?
    case "${status}" in
        0) ;;
        1)
            emit_argument_error "invalid cache key: ${argument} (keys contain only A-Z, a-z, 0-9, _ and -)"
            return 1
            ;;
        *)
            emit_argument_error "no cache entry for: ${argument}" "not_found"
            return 1
            ;;
    esac

    if is_json_output_mode; then
        emit_json_success "$(jq -n --arg key "${deleted_key}" '{deleted:$key}')"
    else
        echo "Deleted cache entry: ${deleted_key}"
    fi
}
