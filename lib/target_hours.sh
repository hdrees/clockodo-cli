#!/usr/bin/env bash
# =============================================================================
# lib/target_hours.sh — Target hours (Sollstunden): cached fetch and the
# target of a single day.
#
# Shared by `targethours list` and `entries summary` (different groups,
# hence a lib file instead of commands/targethours/).
#
# Sourced by the entry script (clockodo). Dependencies: lib/http.sh,
# lib/cache.sh, jq.
#
# Public API:
#   fetch_target_hours [users_id]      — GET /targethours, cached.
#   target_hours_jq_definitions        — jq function `target_seconds_for_day`.
# =============================================================================

set -euo pipefail

# Cache TTL (seconds) for /targethours with CACHE=1. Target-hour rules
# change rarely (contract changes), so one hour is safe.
TARGETHOURS_CACHE_TTL=3600

# fetch_target_hours
#   GETs the target-hour rules, optionally of one user, cached for
#   TARGETHOURS_CACHE_TTL with CACHE=1. Normalizes Clockodo's non-standard
#   `.targethours` wrapper to the project convention `.data`.
#   args:    $1 = user ID (empty → every user the key may see)
#   stdout:  `{ "data": [ … ] }`
#   exit:    0 on success, 1 on API errors (state file has the details)
fetch_target_hours() {
    local users_id="${1:-}"
    local path="/targethours"
    [[ -n "${users_id}" ]] && path+="?users_id=${users_id}"

    local raw
    raw="$(clockodo_api_get_cached "${path}" "${TARGETHOURS_CACHE_TTL}")" || return 1
    jq '{data: .targethours}' <<<"${raw}"
}

# target_hours_jq_definitions
#   Echoes the jq function `target_seconds_for_day($day)`, applied to the
#   array of rules of ONE user:
#     - the rule is valid when date_since <= $day <= date_until (an empty
#       date_until is open-ended); with several valid rules the one with the
#       latest date_since wins;
#     - weekly rules: the hours of the weekday (`monday` … `sunday`) in
#       seconds; `workday_<weekday> == false` means 0;
#     - monthly rules: null — a monthly target has no fixed daily share;
#     - no valid rule: null.
#   $day is a calendar day (YYYY-MM-DD); its weekday is computed on UTC
#   midnight, which is the same weekday as the local calendar day.
target_hours_jq_definitions() {
    cat <<'JQ'
def _weekday_of($day): "\($day)T00:00:00Z" | fromdate | strftime("%A") | ascii_downcase;
def target_seconds_for_day($day):
    map(select((.date_since // "") <= $day and ((.date_until // "") == "" or .date_until >= $day)))
    | (max_by(.date_since // "") // null) as $rule
    | _weekday_of($day) as $weekday
    | if $rule == null or $rule.type == "monthly" then null
      elif $rule["workday_\($weekday)"] == false then 0
      else (($rule[$weekday] // 0) * 3600 | round)
      end;
JQ
}
