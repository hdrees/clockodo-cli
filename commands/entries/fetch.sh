#!/usr/bin/env bash
# =============================================================================
# commands/entries/fetch.sh — Fetches the time entries of a range.
#
# Shared by `entries list` and `entries summary`. Uses the enhanced list, so
# customer, project, subproject and service names are included (the API
# limits enhanced requests to 300 per 15 minutes).
#
# Dependencies: lib/pagination.sh.
# =============================================================================

set -euo pipefail

# fetch_entries_in_range
#   GETs every page of /v2/entries for the range, optionally for one user.
#   args:    $1 = time_since (UTC, YYYY-MM-DDTHH:MM:SSZ)
#            $2 = time_until (UTC, exclusive)
#            $3 = user ID to filter by (empty → every user the key may see)
#   stdout:  `{ "entries": [ … ], "paging": … }`
#   exit:    0 on success, 1 on API errors (state file has the details)
fetch_entries_in_range() {
    local time_since="$1" time_until="$2" users_id="${3:-}"
    local path="/v2/entries?time_since=${time_since}&time_until=${time_until}&enhanced_list=1"
    if [[ -n "${users_id}" ]]; then
        path+="&filter%5Busers_id%5D=${users_id}"
    fi
    clockodo_api_get_all "${path}" entries
}
