#!/usr/bin/env bash
# =============================================================================
# commands/entries/dates.sh — Time-range helpers for the entries group.
#
# /v2/entries requires `time_since` and `time_until` as UTC timestamps
# (YYYY-MM-DDTHH:MM:SSZ). Users pass either such a timestamp or a calendar
# day (YYYY-MM-DD), which is interpreted in the local time zone and
# converted to UTC here.
#
# Dependencies: date (GNU or BSD), jq.
# =============================================================================

set -euo pipefail

# is_calendar_day
#   Returns 0 if the value has the shape YYYY-MM-DD.
#   args:  $1 = candidate value
is_calendar_day() {
    [[ "${1:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# is_utc_timestamp
#   Returns 0 if the value has the shape YYYY-MM-DDTHH:MM:SSZ.
#   args:  $1 = candidate value
is_utc_timestamp() {
    [[ "${1:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# local_today
#   Prints the current local calendar day as YYYY-MM-DD.
local_today() {
    date +%Y-%m-%d
}

# _local_midnight_epoch
#   Prints the Unix timestamp of 00:00 local time on the given day.
#   Tries GNU `date -d` first, then BSD `date -j -f`.
#   args:    $1 = calendar day (YYYY-MM-DD)
#   stdout:  epoch seconds
#   exit:    1 if the day is not a valid date
_local_midnight_epoch() {
    local day="$1"
    date -d "${day} 00:00:00" +%s 2>/dev/null \
        || date -j -f '%Y-%m-%d %H:%M:%S' "${day} 00:00:00" +%s 2>/dev/null
}

# _next_calendar_day
#   Prints the day after the given one (YYYY-MM-DD). The arithmetic runs on
#   UTC midnight in jq, so local DST switches cannot shift the result.
#   args:  $1 = calendar day (YYYY-MM-DD)
_next_calendar_day() {
    jq -rn --arg day "$1" '"\($day)T00:00:00Z" | fromdate + 86400 | strftime("%Y-%m-%d")'
}

# local_day_start_utc
#   Prints the UTC timestamp at which the given local day begins.
#   args:    $1 = calendar day (YYYY-MM-DD)
#   stdout:  YYYY-MM-DDTHH:MM:SSZ
#   exit:    1 if the day is not a valid date
local_day_start_utc() {
    local epoch
    epoch="$(_local_midnight_epoch "$1")" || return 1
    # `todate` formats epoch seconds as an ISO 8601 UTC timestamp.
    jq -rn --argjson epoch "${epoch}" '$epoch | todate'
}

# local_day_end_utc
#   Prints the UTC timestamp at which the given local day ends, i.e. the
#   start of the following local day (exclusive upper bound).
#   args:    $1 = calendar day (YYYY-MM-DD)
#   stdout:  YYYY-MM-DDTHH:MM:SSZ
#   exit:    1 if the day is not a valid date
local_day_end_utc() {
    local day="$1"
    _local_midnight_epoch "${day}" >/dev/null || return 1
    local_day_start_utc "$(_next_calendar_day "${day}")"
}
