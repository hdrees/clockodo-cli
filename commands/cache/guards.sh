#!/usr/bin/env bash
# =============================================================================
# commands/cache/guards.sh — Argument checks shared by the cache actions.
#
# Dependencies: lib/helper.sh.
# =============================================================================

set -euo pipefail

# reject_curl_for_cache_command
#   The cache actions send no API request, so there is no curl command to
#   print; --curl is rejected instead of silently doing the action.
#   exit:  0 outside --curl mode, 1 (error reported) in --curl mode
reject_curl_for_cache_command() {
    if is_curl_output_mode; then
        emit_argument_error "cache commands send no API requests; --curl is not supported"
        return 1
    fi
}
