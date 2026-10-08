#!/usr/bin/env bash
# =============================================================================
# commands/entries/summary.sh — Day summary of one user's time entries.
# Usage: `clockodo entries summary [--me|--user <id>] [--date <YYYY-MM-DD>] [--json]`
#
# One request against /v2/entries (enhanced list) for the local day, plus
# /v4/users/me (for --me) and /targethours — both cached with CACHE=1, so a
# periodic caller (status bar, dashboard) costs one request per refresh.
#
# The running entry comes from the entries list itself (time entry without
# time_until), so /v2/clock is not needed. Its elapsed time is computed
# against the local clock.
#
# Dependencies: lib/user_argument.sh, lib/target_hours.sh,
# commands/entries/dates.sh, commands/entries/fetch.sh, commands/entries/ui.sh.
# =============================================================================

set -euo pipefail

# cmd_entries_summary
#   Parses the options, fetches entries and target hours of the day and
#   renders the summary.
#   args:   --me (default), --user <id>, --date <YYYY-MM-DD>, --help/-h
#   stdout: Key/Value block, or the JSON envelope in --json mode
#   exit:   0 on success, 1 on invalid options or API errors
cmd_entries_summary() {
    if has_help_arg "$@"; then
        print_entries_help
        return 0
    fi

    # Several requests per run — --curl could only show the first one.
    if is_curl_output_mode; then
        emit_argument_error "entries summary is not supported with --curl; use entries list --user <id> --curl"
        return 1
    fi

    local user_argument="" day=""
    while (( $# > 0 )); do
        case "$1" in
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
            --date)
                _entries_require_option_value "$1" "${2:-}" || return 1
                day="$2"
                shift
                ;;
            *)
                emit_argument_error "unknown option: $1"
                return 1
                ;;
        esac
        shift
    done

    day="${day:-$(local_today)}"
    if ! is_calendar_day "${day}" || ! local_day_start_utc "${day}" >/dev/null; then
        emit_argument_error "--date must be YYYY-MM-DD (got: ${day})"
        return 1
    fi

    resolve_user_argument "${user_argument:-me}" || return 1
    local users_id="${RESOLVED_USER_ID}"

    local entries_json target_json
    if ! entries_json="$(fetch_entries_in_range "$(local_day_start_utc "${day}")" "$(local_day_end_utc "${day}")" "${users_id}")"; then
        emit_api_failure
        return 1
    fi
    if ! target_json="$(fetch_target_hours "${users_id}")"; then
        emit_api_failure
        return 1
    fi

    local summary
    summary="$(_entries_build_summary "${entries_json}" "${target_json}" "${day}" "${users_id}")"

    if is_json_output_mode; then
        emit_json_success "${summary}"
    else
        print_entries_summary "${summary}"
    fi
}

# _entries_build_summary
#   Computes the day summary. All values are in seconds; durations come
#   from `duration`. The running entry has none yet (null) and counts with
#   its elapsed time up to now — unless the API already filled `duration`.
#   args:    $1 = entries JSON (`{ "entries": [ … ] }`)
#            $2 = target hours JSON (`{ "data": [ … ] }`, one user)
#            $3 = calendar day (YYYY-MM-DD), $4 = user ID
#   stdout:  summary object:
#            { date, users_id, current_time, count_entries, total_seconds,
#              start_of_day, running (entry + elapsed_seconds, or null),
#              target_seconds, delta_seconds, percent }
#            target_seconds/delta_seconds/percent are null without a valid
#            weekly target-hours rule (percent also for a target of 0).
_entries_build_summary() {
    local entries_json="$1" target_json="$2" day="$3" users_id="$4"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Both inputs go through stdin (`-s` slurps them into an array), as they
    # can be large; small values are passed as arguments.
    printf '%s\n%s\n' "${entries_json}" "${target_json}" | jq -s \
        --arg day "${day}" --arg now "${now}" --argjson users_id "${users_id}" "
        $(_entries_jq_helpers)
        $(target_hours_jq_definitions)
        (.[0].entries // []) as \$entries
        | (.[1].data // []) as \$rules
        | (first(\$entries[] | select(.type == 1 and .time_until == null)) // null) as \$running
        | (\$running != null and (\$running.duration | type) != \"number\") as \$running_uncounted
        | (if \$running == null then 0
           elif \$running_uncounted then [(\$now | _epoch) - (\$running.time_since | _epoch), 0] | max
           else \$running.duration
           end) as \$running_elapsed
        | ((\$entries | map(.duration // 0) | add // 0)
           + (if \$running_uncounted then \$running_elapsed else 0 end)) as \$total
        | (\$rules | target_seconds_for_day(\$day)) as \$target
        | {
            date: \$day,
            users_id: \$users_id,
            current_time: \$now,
            count_entries: (\$entries | length),
            total_seconds: \$total,
            start_of_day: (\$entries | map(.time_since) | min),
            running: (if \$running == null then null
                      else \$running + {elapsed_seconds: \$running_elapsed} end),
            target_seconds: \$target,
            delta_seconds: (if \$target == null then null else \$total - \$target end),
            percent: (if \$target == null or \$target == 0 then null
                      else (\$total / \$target * 100 | round) end)
          }"
}
