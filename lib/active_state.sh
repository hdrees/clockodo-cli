#!/usr/bin/env bash
# =============================================================================
# lib/active_state.sh — `--state active|inactive|all` option for list actions
# whose resources carry an `active` flag (customers, projects, subprojects,
# services, users).
#
# Sourced by the entry script (clockodo). No dependencies on other lib files.
#
# The state maps to Clockodo's deepObject filter `filter[active]=<bool>`,
# sent URL-encoded (`%5B` / `%5D`) so curl does not treat the brackets as a
# glob pattern. `all` sends no filter at all.
#
# Public API:
#   parse_active_state_option <args...>  — parses `--state` from list args.
#   path_with_active_state <path> <state> — appends the matching filter.
# =============================================================================

set -euo pipefail

# Default when `--state` is not given: only active resources.
ACTIVE_STATE_DEFAULT="active"

# is_valid_active_state
#   args:  $1 = candidate value
#   exit:  0 for active|inactive|all, 1 otherwise
is_valid_active_state() {
    [[ "${1:-}" == "active" || "${1:-}" == "inactive" || "${1:-}" == "all" ]]
}

# parse_active_state_option
#   Parses the arguments of a list action. Accepts `--state <value>` and
#   `--state=<value>`; any other argument is rejected. Help flags are not
#   handled here — callers check them first via has_help_arg.
#   args:    $@ = the action's arguments
#   stdout:  on success the state (active|inactive|all, default active);
#            on failure the error message, so callers running this in
#            `$(…)` can forward it to emit_argument_error.
#   exit:    0 on success, 1 on an unknown argument or invalid value
parse_active_state_option() {
    local state="${ACTIVE_STATE_DEFAULT}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --state)
                # `${2:-}` → empty when the value is missing (set -u safe).
                if [[ -z "${2:-}" ]]; then
                    echo "--state requires a value (active, inactive or all)"
                    return 1
                fi
                state="$2"
                shift 2
                ;;
            --state=*)
                # `${1#--state=}` strips the option name, leaving the value.
                state="${1#--state=}"
                shift
                ;;
            *)
                echo "unknown argument: $1"
                return 1
                ;;
        esac
    done

    if ! is_valid_active_state "${state}"; then
        echo "--state must be active, inactive or all (got: ${state})"
        return 1
    fi

    printf '%s' "${state}"
}

# path_with_active_state
#   Appends the `filter[active]` query parameter matching the state.
#   args:    $1 = endpoint path (may already contain a query string)
#            $2 = state (active|inactive|all)
#   stdout:  the path, with `filter%5Bactive%5D=true|false` unless state is all
path_with_active_state() {
    local path="$1" state="$2"

    local filter_value
    case "${state}" in
        active)   filter_value="true" ;;
        inactive) filter_value="false" ;;
        *)
            printf '%s' "${path}"
            return 0
            ;;
    esac

    # `&` when the path already has a query string, `?` otherwise.
    local separator="?"
    [[ "${path}" == *\?* ]] && separator="&"

    printf '%s%sfilter%%5Bactive%%5D=%s' "${path}" "${separator}" "${filter_value}"
}
