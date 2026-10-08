#!/usr/bin/env bash
# =============================================================================
# commands/entries/list.sh — Lists time entries or shows the running one.
# Usage:
#   clockodo entries list [--me|--user <id>] [--since <date>] [--until <date>] [--json]
#   clockodo entries list --running [--json]
#
# Range mode walks the paginated /v2/entries (enhanced list, so customer and
# project names are included). `--running` asks /v2/clock instead, which
# only knows the clock of the authenticated user.
#
# Dependencies: lib/http.sh, lib/user_argument.sh, commands/entries/dates.sh,
# commands/entries/fetch.sh, commands/entries/ui.sh.
# =============================================================================

set -euo pipefail

# cmd_entries_list
#   Parses the options and dispatches to the range or the running mode.
#   args:   --me, --user <id>, --running, --since <date>, --until <date>,
#           --help/-h
#   stdout: table / detail block, or the JSON envelope in --json mode
#   exit:   0 on success, 1 on invalid options or API errors
cmd_entries_list() {
    local user_argument="" show_running=0 range_since="" range_until=""

    while (( $# > 0 )); do
        case "$1" in
            --help|-h)
                print_entries_help
                return 0
                ;;
            --me)
                _entries_set_user_argument "${user_argument}" me || return 1
                user_argument="me"
                ;;
            --user)
                _entries_require_option_value "$1" "${2:-}" || return 1
                _entries_set_user_argument "${user_argument}" "$2" || return 1
                user_argument="$2"
                shift
                ;;
            --running) show_running=1 ;;
            --since)
                _entries_require_option_value "$1" "${2:-}" || return 1
                range_since="$2"
                shift
                ;;
            --until)
                _entries_require_option_value "$1" "${2:-}" || return 1
                range_until="$2"
                shift
                ;;
            *)
                emit_argument_error "unknown option: $1"
                return 1
                ;;
        esac
        shift
    done

    if (( show_running )); then
        if [[ -n "${range_since}" || -n "${range_until}" || -n "${user_argument}" ]]; then
            emit_argument_error "--running cannot be combined with --since/--until/--me/--user"
            return 1
        fi
        _entries_show_running
        return
    fi

    _entries_list_range "${user_argument}" "${range_since}" "${range_until}"
}

# _entries_set_user_argument
#   Rejects a second user filter (--me and --user are mutually exclusive).
#   args:  $1 = user argument chosen so far (empty if none), $2 = new one
#   exit:  0 if no filter was chosen before, 1 (error reported) otherwise
_entries_set_user_argument() {
    if [[ -n "$1" ]]; then
        emit_argument_error "--me and --user can only be given once and not together"
        return 1
    fi
}

# _entries_require_option_value
#   Reports a missing value for an option that expects one.
#   args:  $1 = option name, $2 = the value that followed it (may be empty)
#   exit:  0 if a value is present, 1 (error reported) otherwise
_entries_require_option_value() {
    local option="$1" value="$2"
    if [[ -z "${value}" || "${value}" == --* ]]; then
        emit_argument_error "${option} requires a value" "missing_argument"
        return 1
    fi
}

# _entries_show_running
#   GETs /v2/clock and renders the running entry of the authenticated user.
#   stdout: detail block, "No running entry." or the JSON envelope (the full
#           clock payload: running, stopped, current_time)
_entries_show_running() {
    local json
    if ! json="$(clockodo_api_get /v2/clock)"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_success "${json}"
        return 0
    fi

    if [[ "$(echo "${json}" | jq '.running == null')" == "true" ]]; then
        echo "No running entry."
        return 0
    fi

    print_entry_detail "$(echo "${json}" | jq '.running')" "$(echo "${json}" | jq -r '.current_time')"
}

# _entries_list_range
#   Fetches all entries of a time range and renders them.
#   args:   $1 = user filter: "me", a user ID or empty (all users)
#           $2 = --since value (empty → today)
#           $3 = --until value (empty → day of --since)
_entries_list_range() {
    local user_argument="$1"
    local range_since="${2:-$(local_today)}"
    local range_until="${3:-}"

    # Validate before converting: the conversions run inside `$(…)`, where
    # an error envelope on stdout would be captured instead of printed.
    _entries_validate_range_value --since "${range_since}" || return 1
    if [[ -z "${range_until}" ]]; then
        if ! is_calendar_day "${range_since}"; then
            emit_argument_error "--until is required when --since is a timestamp" "missing_argument"
            return 1
        fi
        range_until="${range_since}"
    fi
    _entries_validate_range_value --until "${range_until}" || return 1

    local time_since time_until
    time_since="$(_entries_range_start_utc "${range_since}")"
    time_until="$(_entries_range_end_utc "${range_until}")"

    # --me needs a lookup request first, which --curl must not send.
    if [[ "${user_argument}" == "me" ]] && is_curl_output_mode; then
        emit_argument_error "--me is not supported with --curl; pass --user <id>"
        return 1
    fi
    resolve_user_argument "${user_argument}" || return 1

    local json
    if ! json="$(fetch_entries_in_range "${time_since}" "${time_until}" "${RESOLVED_USER_ID}")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_success "$(echo "${json}" | jq '.entries')"
    else
        print_entries_table "${json}"
    fi
}

# _entries_validate_range_value
#   Accepts a UTC timestamp or an existing calendar day.
#   args:  $1 = option name (for the message), $2 = value
#   exit:  0 if valid, 1 (error reported) otherwise
_entries_validate_range_value() {
    local option="$1" value="$2"
    if is_utc_timestamp "${value}"; then
        return 0
    fi
    if is_calendar_day "${value}" && local_day_start_utc "${value}" >/dev/null; then
        return 0
    fi
    emit_argument_error "${option} must be YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ (got: ${value})"
    return 1
}

# _entries_range_start_utc
#   Converts a validated --since value into the UTC timestamp for `time_since`.
#   args:    $1 = calendar day or UTC timestamp
#   stdout:  UTC timestamp
_entries_range_start_utc() {
    local value="$1"
    if is_utc_timestamp "${value}"; then
        echo "${value}"
    else
        local_day_start_utc "${value}"
    fi
}

# _entries_range_end_utc
#   Converts a validated --until value into the UTC timestamp for
#   `time_until`. A calendar day includes the whole day (next local midnight).
#   args:    $1 = calendar day or UTC timestamp
#   stdout:  UTC timestamp
_entries_range_end_utc() {
    local value="$1"
    if is_utc_timestamp "${value}"; then
        echo "${value}"
    else
        local_day_end_utc "${value}"
    fi
}
