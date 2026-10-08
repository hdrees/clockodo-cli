#!/usr/bin/env bash
# =============================================================================
# commands/entries/stop.sh — Stops the running clock entry.
# Usage: `clockodo entries stop [<id>] [--json|--help|-h]`
#
# Without an ID the running entry of the authenticated user is looked up via
# /v2/clock first. Stopping is DELETE /v2/clock/{id}; the response
# (ClockStopV2) carries the stopped entry and has no `data` wrapper.
#
# Dependencies: lib/http.sh, commands/entries/ui.sh.
# =============================================================================

set -euo pipefail

# cmd_entries_stop
#   Stops the given or the currently running clock entry.
#   args:   $1 = optional entry ID (numeric) or --help/-h
#   stdout: confirmation line, or the JSON envelope in --json mode
#   exit:   0 on success, 1 on invalid ID, no running entry or API errors
cmd_entries_stop() {
    if has_help_arg "$@"; then
        print_entries_help
        return 0
    fi

    local entry_id="${1:-}"

    if [[ -z "${entry_id}" ]]; then
        # The lookup is a real request, which --curl must not send.
        if is_curl_output_mode; then
            emit_argument_error "entry ID is required with --curl" "missing_argument"
            return 1
        fi
        entry_id="$(_entries_running_entry_id)" || {
            emit_api_failure
            return 1
        }
        if [[ -z "${entry_id}" ]]; then
            _entries_report_no_running_entry
            return 1
        fi
    fi

    if ! [[ "${entry_id}" =~ ^[0-9]+$ ]]; then
        emit_argument_error "entry ID must be numeric (got: ${entry_id})"
        return 1
    fi

    local response
    if ! response="$(clockodo_api_delete "/v2/clock/${entry_id}")"; then
        emit_api_failure
        return 1
    fi

    if is_json_output_mode; then
        emit_json_success "${response}"
    else
        echo "${response}" | jq -r "
            $(_entries_jq_helpers)
            \"Stopped: entry ID \(.stopped.id // \"?\") (duration \(.stopped.duration | _duration))\",
            (if .stopped_has_been_truncated then \"Note: the entry was shortened to the maximum duration of 24h.\" else empty end)"
    fi
}

# _entries_running_entry_id
#   Prints the ID of the authenticated user's running entry, or nothing when
#   the clock is not running.
#   exit:  0 on success, 1 if the /v2/clock request failed
_entries_running_entry_id() {
    local json
    json="$(clockodo_api_get /v2/clock)" || return 1
    # `// empty` prints nothing for a null `running`.
    echo "${json}" | jq -r '.running.id // empty'
}

# _entries_report_no_running_entry
#   Reports that there is nothing to stop (code `not_running` in --json mode).
_entries_report_no_running_entry() {
    if is_json_output_mode; then
        emit_json_failure "no running entry" "not_running"
    else
        echo "Error: no running entry" >&2
    fi
}
