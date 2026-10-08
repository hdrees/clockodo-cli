#!/usr/bin/env bash
# =============================================================================
# lib/resource_actions.sh — Shared `list` and `get` flow for cached
# resources with an `active` flag (customers, projects, subprojects,
# services, users).
#
# The group's action files keep their `cmd_<group>_<action>` function and
# only pass the group-specific parts (help function, endpoint, TTL,
# renderer) to these runners.
#
# Sourced by the entry script (clockodo). Dependencies: lib/helper.sh,
# lib/http.sh, lib/pagination.sh, lib/cache.sh, lib/active_state.sh.
#
# Public API:
#   run_state_filtered_list <help_fn> <list_path> <ttl> <renderer> [args...]
#   run_cached_get <help_fn> <label> <list_path> <ttl> <renderer> [args...]
# =============================================================================

set -euo pipefail

# run_state_filtered_list
#   `list` action: parses `--state`, fetches every page of <list_path>
#   (cached) and renders the result as text or --json envelope.
#   args:    $1 = help function (e.g. print_customers_help)
#            $2 = list endpoint without query string (e.g. /v3/customers)
#            $3 = cache TTL in seconds
#            $4 = text renderer, called with the response JSON
#            $5… = the action's arguments
#   exit:    0 on success or help, 1 on invalid arguments or API errors
run_state_filtered_list() {
    local help_function="$1" list_path="$2" ttl="$3" renderer="$4"
    shift 4

    if has_help_arg "$@"; then
        "${help_function}"
        return 0
    fi

    # Parse `--state`; on failure the subshell output is the error message.
    local active_state
    if ! active_state="$(parse_active_state_option "$@")"; then
        emit_argument_error "${active_state}"
        return 1
    fi

    local json
    if ! json="$(clockodo_api_get_all_cached "$(path_with_active_state "${list_path}" "${active_state}")" "${ttl}")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_data "${json}"
    else
        "${renderer}" "${json}"
    fi
}

# run_cached_get
#   `get` action: validates the ID and GETs <list_path>/<id>, preferring an
#   entry from a fresh list cache (see clockodo_api_get_cached_via_list).
#   Never filtered by state.
#   args:    $1 = help function (e.g. print_customers_help)
#            $2 = label for error messages (e.g. "customer")
#            $3 = list endpoint (e.g. /v3/customers)
#            $4 = cache TTL in seconds (same constant as the list action)
#            $5 = text renderer, called with the response JSON
#            $6… = the action's arguments (the first one is the ID)
#   exit:    0 on success or help, 1 on invalid arguments or API errors
run_cached_get() {
    local help_function="$1" label="$2" list_path="$3" ttl="$4" renderer="$5"
    shift 5

    if has_help_arg "$@"; then
        "${help_function}"
        return 0
    fi

    local id="${1:-}"
    validate_numeric_id "${label}" "${id}" || return 1

    local json
    if ! json="$(clockodo_api_get_cached_via_list "${list_path}/${id}" "${list_path}" "${id}" "${ttl}")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_data "${json}"
    else
        "${renderer}" "${json}"
    fi
}
