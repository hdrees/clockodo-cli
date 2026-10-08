#!/usr/bin/env bash
# =============================================================================
# lib/user_argument.sh — Resolves a `me|<user-id>` argument to a user ID.
#
# Used by actions that filter by user (absences list, targethours list,
# entries list --me). `me` costs a lookup request against /v4/users/me,
# which --curl must not send, so it is rejected in --curl mode.
#
# Sourced by the entry script (clockodo). Dependencies: lib/helper.sh,
# lib/http.sh, lib/cache.sh.
#
# Public API:
#   fetch_current_user                     — GET /v4/users/me (cached).
#   resolve_user_argument <me|user-id|"">  — sets RESOLVED_USER_ID.
# =============================================================================

set -euo pipefail

# Cache TTL (seconds) for /v4/users/me with CACHE=1. The ID of the
# authenticated user never changes; the other fields (name, …) rarely do.
# The cache is per account (see lib/cache.sh), so it cannot leak across keys.
USERS_ME_CACHE_TTL=3600

# fetch_current_user
#   GETs the authenticated user, cached for USERS_ME_CACHE_TTL with CACHE=1.
#   stdout:  `{ "data": { "id": …, … } }`
#   exit:    0 on success, 1 on API errors (state file has the details)
fetch_current_user() {
    clockodo_api_get_cached /v4/users/me "${USERS_ME_CACHE_TTL}"
}

# Result of resolve_user_argument. A global instead of stdout, because the
# function reports its own errors (failure envelope on stdout in --json
# mode) and therefore must not run inside `$(…)`.
RESOLVED_USER_ID=""

# resolve_user_argument
#   Resolves the argument to a numeric user ID.
#   args:    $1 = "me", a numeric user ID, or empty (no filter)
#   result:  RESOLVED_USER_ID = the user ID, empty when $1 is empty
#   stdout:  failure envelope in --json mode
#   stderr:  error message in text mode
#   exit:    0 on success, 1 on invalid argument, `me` with --curl or a
#            failed lookup (error already reported)
resolve_user_argument() {
    local argument="${1:-}"
    RESOLVED_USER_ID=""

    if [[ -z "${argument}" ]]; then
        return 0
    fi

    if [[ "${argument}" =~ ^[0-9]+$ ]]; then
        RESOLVED_USER_ID="${argument}"
        return 0
    fi

    if [[ "${argument}" != "me" ]]; then
        emit_argument_error "user ID must be 'me' or numeric (got: ${argument})"
        return 1
    fi

    if is_curl_output_mode; then
        emit_argument_error "'me' is not supported with --curl; pass a numeric user ID"
        return 1
    fi

    local me_json
    if ! me_json="$(fetch_current_user)"; then
        emit_api_failure
        return 1
    fi
    RESOLVED_USER_ID="$(echo "${me_json}" | jq -r '.data.id')"
}
