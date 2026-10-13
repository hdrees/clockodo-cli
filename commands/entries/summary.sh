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
# time_until). Its elapsed time is computed against the local clock.
#
# /v2/entries filters by the START of an entry (time_since inside the
# range), not by overlap: a clock started before local midnight is missing
# from the day's list. So for the authenticated user's today, a list
# without a running entry is followed by GET /v2/clock; a clock that
# started before the day is fetched once more from the enhanced list
# (names) and counts towards the day from midnight on (see
# _entries_fetch_carried_running).
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

    local day_start day_end
    day_start="$(local_day_start_utc "${day}")"
    day_end="$(local_day_end_utc "${day}")"

    local entries_json target_json
    if ! entries_json="$(fetch_entries_in_range "${day_start}" "${day_end}" "${users_id}")"; then
        emit_api_failure
        return 1
    fi

    # /v2/clock only knows the authenticated user's clock, and only today
    # can have a clock running since before the day.
    local carried_json="null"
    if [[ "${user_argument:-me}" == "me" && "${day}" == "$(local_today)" ]] \
        && ! _entries_has_running_entry "${entries_json}"; then
        if ! carried_json="$(_entries_fetch_carried_running "${day_start}" "${users_id}")"; then
            emit_api_failure
            return 1
        fi
    fi

    if ! target_json="$(fetch_target_hours "${users_id}")"; then
        emit_api_failure
        return 1
    fi

    local summary
    summary="$(_entries_build_summary "${entries_json}" "${target_json}" "${carried_json}" "${day}" "${day_start}" "${users_id}")"

    if is_json_output_mode; then
        emit_json_success "${summary}"
    else
        print_entries_summary "${summary}"
    fi
}

# _entries_has_running_entry
#   Returns 0 when the entries list holds a running time entry (type 1
#   without time_until).
#   args:  $1 = entries JSON (`{ "entries": [ … ] }`)
_entries_has_running_entry() {
    # `-e` sets the exit code from the result: 0 for true, 1 for false.
    jq -e 'any(.entries[]?; .type == 1 and .time_until == null)' <<<"$1" >/dev/null
}

# _entries_fetch_carried_running
#   Looks for a clock of the authenticated user that started before the day
#   and is still running ("carried over" past midnight). /v2/clock has no
#   names, so the entry is fetched once more from the enhanced list
#   (range: its start up to the day start); should that miss it, the plain
#   /v2/clock entry is used.
#   args:    $1 = day start (UTC, YYYY-MM-DDTHH:MM:SSZ), $2 = user ID
#   stdout:  the running entry, or `null` when no clock runs or it started
#            inside the day (then it is in the day's list anyway, or started
#            after that list was fetched)
#   exit:    0 on success, 1 on API errors (state file has the details)
_entries_fetch_carried_running() {
    local day_start="$1" users_id="$2"

    local clock_json running_json running_since
    clock_json="$(clockodo_api_get /v2/clock)" || return 1
    running_json="$(jq -c '.running // null' <<<"${clock_json}")"
    # `// empty` prints nothing for a missing or null value.
    running_since="$(jq -r '.time_since // empty' <<<"${running_json}")"

    # Both timestamps are UTC in the same YYYY-MM-DDTHH:MM:SSZ form, so the
    # string comparison is a time comparison.
    if [[ -z "${running_since}" || ! "${running_since}" < "${day_start}" ]]; then
        printf 'null'
        return 0
    fi

    local earlier_json
    earlier_json="$(fetch_entries_in_range "${running_since}" "${day_start}" "${users_id}")" || return 1
    # The input is the earlier list; `first(…) // $clock` falls back to the
    # /v2/clock entry when the list does not contain it.
    jq -c --argjson clock "${running_json}" \
        'first(.entries[]? | select(.id == $clock.id)) // $clock' <<<"${earlier_json}"
}

# _entries_build_summary
#   Computes the day summary. All values are in seconds; durations come
#   from `duration`. The running entry has none yet (null) and counts with
#   its elapsed time up to now — unless the API already filled `duration`.
#   A clock carried over from before the day counts from the day start only;
#   the day's start_of_day is then the day start itself.
#   args:    $1 = entries JSON (`{ "entries": [ … ] }`)
#            $2 = target hours JSON (`{ "data": [ … ] }`, one user)
#            $3 = running entry carried over from before the day, or `null`
#                 (see _entries_fetch_carried_running)
#            $4 = calendar day (YYYY-MM-DD)
#            $5 = day start (UTC, YYYY-MM-DDTHH:MM:SSZ), $6 = user ID
#   stdout:  summary object:
#            { date, users_id, current_time, count_entries, total_seconds,
#              start_of_day, running (entry + elapsed_seconds +
#              started_before_day, or null), target_seconds, delta_seconds,
#              percent }
#            running.elapsed_seconds is the whole elapsed time, also for a
#            carried-over clock. target_seconds/delta_seconds/percent are
#            null without a valid weekly target-hours rule (percent also for
#            a target of 0).
_entries_build_summary() {
    local entries_json="$1" target_json="$2" carried_json="$3"
    local day="$4" day_start="$5" users_id="$6"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # The inputs go through stdin (`-s` slurps them into an array), as they
    # can be large; small values are passed as arguments.
    printf '%s\n%s\n%s\n' "${entries_json}" "${target_json}" "${carried_json}" | jq -s \
        --arg day "${day}" --arg day_start "${day_start}" --arg now "${now}" \
        --argjson users_id "${users_id}" "
        $(_entries_jq_helpers)
        $(target_hours_jq_definitions)
        (.[0].entries // []) as \$entries
        | (.[1].data // []) as \$rules
        | .[2] as \$carried
        | (\$carried != null) as \$is_carried
        | (first(\$entries[] | select(.type == 1 and .time_until == null)) // \$carried) as \$running
        | (\$running != null and (\$running.duration | type) != \"number\") as \$running_uncounted
        | (if \$running == null then 0
           elif \$running_uncounted or \$is_carried then [(\$now | _epoch) - (\$running.time_since | _epoch), 0] | max
           else \$running.duration
           end) as \$running_elapsed
        | (if \$is_carried then [(\$now | _epoch) - (\$day_start | _epoch), 0] | max
           elif \$running_uncounted then \$running_elapsed
           else 0
           end) as \$running_extra
        | ((\$entries | map(.duration // 0) | add // 0) + \$running_extra) as \$total
        | (\$rules | target_seconds_for_day(\$day)) as \$target
        | {
            date: \$day,
            users_id: \$users_id,
            current_time: \$now,
            count_entries: ((\$entries | length) + (if \$is_carried then 1 else 0 end)),
            total_seconds: \$total,
            start_of_day: (if \$is_carried then \$day_start else (\$entries | map(.time_since) | min) end),
            running: (if \$running == null then null
                      else \$running + {elapsed_seconds: \$running_elapsed, started_before_day: \$is_carried} end),
            target_seconds: \$target,
            delta_seconds: (if \$target == null then null else \$total - \$target end),
            percent: (if \$target == null or \$target == 0 then null
                      else (\$total / \$target * 100 | round) end)
          }"
}
