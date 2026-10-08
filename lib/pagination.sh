#!/usr/bin/env bash
# =============================================================================
# lib/pagination.sh — Walks paginated Clockodo list endpoints.
#
# Sourced by the entry script (clockodo) after lib/http.sh. Public API:
#
#   clockodo_api_get_all <path>
#       Fetches every page of a paginated list endpoint (uniform Clockodo
#       paging scheme: `page` and `items_per_page` query params, response
#       carries a `paging.count_pages` field). Prints a single JSON envelope
#       on stdout of the same shape as a single-page response, so callers
#       cannot tell pagination apart from a non-paginated reply:
#
#           { "data": [<all items>], "paging": { "count_items": N } }
#
#       Most endpoints wrap their items in `data`; older ones use another
#       key (e.g. /v2/entries → `entries`). Pass that key as second argument;
#       the merged envelope then carries the items under the same key.
#
# Errors propagate the same way as for clockodo_api_get: stash via the
# state file in lib/http.sh, return non-zero, action code calls
# emit_api_failure (lib/helper.sh), which reads that state file.
#
# Page size defaults to 1000; override via CLOCKODO_ITEMS_PER_PAGE. The
# value is capped at the endpoint's maximum from the Clockodo API spec
# (see _max_items_per_page), so one override works for every list.
# =============================================================================

set -euo pipefail

# Default page size; valid for every list endpoint this CLI uses.
DEFAULT_ITEMS_PER_PAGE=1000

# _max_items_per_page
#   Prints the largest `items_per_page` the endpoint accepts (OpenAPI spec,
#   https://docs.clockodo.com/openapi.yaml). Most list endpoints allow 5000;
#   the ones listed explicitly allow less and reject larger values.
#   args:    $1 = endpoint path (a query string is ignored)
#   stdout:  maximum page size
_max_items_per_page() {
    # `${1%%\?*}` = the path without its query string.
    case "${1%%\?*}" in
        /v2/usersNonbusinessDays)                                   echo 100 ;;
        /v3/projects/reports)                                       echo 250 ;;
        /v2/entries|/v2/workTimes/changeRequests|/v3/teams|/v3/users|/v3/usersNonbusinessGroups)
                                                                    echo 1000 ;;
        *)                                                          echo 5000 ;;
    esac
}

# _items_per_page_for
#   Prints the page size for the endpoint: CLOCKODO_ITEMS_PER_PAGE (or the
#   default), capped at the endpoint maximum. Non-numeric or zero overrides
#   fall back to the default.
#   args:    $1 = endpoint path
#   stdout:  page size
_items_per_page_for() {
    local requested="${CLOCKODO_ITEMS_PER_PAGE:-${DEFAULT_ITEMS_PER_PAGE}}"
    [[ "${requested}" =~ ^[1-9][0-9]*$ ]] || requested="${DEFAULT_ITEMS_PER_PAGE}"

    local maximum
    maximum="$(_max_items_per_page "$1")"
    # The regex above rules out leading zeros, so no octal surprise here.
    if (( requested > maximum )); then
        echo "${maximum}"
    else
        echo "${requested}"
    fi
}

# clockodo_api_get_all
#   args:    $1 = endpoint path (may already contain a query string)
#            $2 = optional items key of the response (default: data)
#   stdout:  merged JSON envelope (see file header)
#   exit:    0 on success, 1 if any page request failed
clockodo_api_get_all() {
    local path="$1"
    local items_key="${2:-data}"
    local items_per_page
    items_per_page="$(_items_per_page_for "${path}")"

    # Pick the right separator: `&` when the path already has a query string,
    # `?` otherwise.
    local sep="?"
    [[ "${path}" == *\?* ]] && sep="&"

    local page=1
    local pages=()
    local page_json count_pages

    while :; do
        # `if !` disarms `set -e` so we can react to failure cleanly. The
        # state file in lib/http.sh has the status + body for the caller.
        if ! page_json="$(clockodo_api_get "${path}${sep}page=${page}&items_per_page=${items_per_page}")"; then
            return 1
        fi
        pages+=("${page_json}")

        # Stop when we've consumed the last page. `// 1` covers responses
        # without a paging block (treat as single page).
        count_pages="$(echo "${page_json}" | jq -r '.paging.count_pages // 1')"
        (( page >= count_pages )) && break
        page=$(( page + 1 ))
    done

    # Merge every page in a single jq invocation. `map(.[$key] // [])`
    # tolerates malformed pages that omit the items key; previously a `null`
    # would have crashed the accumulator. Also avoids the O(N²) re-parse
    # of the growing accumulator across pages. `{($key): …}` uses the
    # runtime value of $key as object key.
    printf '%s\n' "${pages[@]}" | jq -s --arg key "${items_key}" \
        'map(.[$key] // []) | add as $all | {($key):$all, paging:{count_items:($all|length)}}'
}
