#!/usr/bin/env bash
# =============================================================================
# commands/entries/ui.sh — Presentation helpers for the entries group.
#
# EntryV2 is a oneOf time | lumpsum value | lumpsum service entry. All
# variants share id, users_id, customers_id, time_since and text; time
# entries add time_until and duration (both null while the clock runs).
# Timestamps arrive in UTC and are rendered in the local time zone.
#
# Dependencies: jq.
# =============================================================================

set -euo pipefail

# _entries_jq_helpers
#   Echoes a jq snippet with the shared formatting functions, re-used by all
#   renderers of this group:
#     _epoch        UTC timestamp → epoch seconds. Strips fractional seconds
#                   first (`current_time` has milliseconds), which jq 1.6's
#                   `fromdateiso8601` cannot parse.
#     _local_time   UTC timestamp → "YYYY-MM-DD HH:MM:SS" local, "-" for null.
#     _duration     seconds → "H:MM:SS", "-" for null.
#     _type_name    EntryType enum (1–3) → name.
#     _single_line  collapses tabs/newlines so `column` keeps rows intact.
#   All times and durations are shown with seconds.
_entries_jq_helpers() {
    cat <<'JQ'
def _epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
def _two_digits: tostring | if length < 2 then "0" + . else . end;
def _local_time: if . == null then "-" else _epoch | strflocaltime("%Y-%m-%d %H:%M:%S") end;
def _duration:
    if . == null then "-"
    else floor as $seconds
        | "\($seconds / 3600 | floor):\($seconds % 3600 / 60 | floor | _two_digits):\($seconds % 60 | _two_digits)"
    end;
def _type_name: {"1": "Time", "2": "LumpsumValue", "3": "LumpsumService"}[tostring] // tostring;
def _single_line: gsub("[\t\n\r]+"; " ");
JQ
}

# print_entries_table
#   Writes the entry list as an aligned table, ordered chronologically.
#   args:    $1 = JSON with top-level `{ "entries": [ … ] }` (enhanced list,
#                 so customer and project names are present).
#   columns: ID, User, Since, Until, Duration, Customer, Project, Service, Text
print_entries_table() {
    local json="$1"
    {
        printf 'ID\tUser\tSince\tUntil\tDuration\tCustomer\tProject\tService\tText\n'
        # Empty cells would let `column` merge columns, hence `// "-"` and
        # the explicit empty-text check.
        echo "${json}" | jq -r "
            $(_entries_jq_helpers)
            .entries
            | sort_by(.time_since)
            | .[]
            | [
                .id,
                ((.users_name // \"-\") | _single_line),
                (.time_since | _local_time),
                (if .type == 1 and .time_until == null then \"running\" else (.time_until | _local_time) end),
                (.duration | _duration),
                ((.customers_name // \"-\") | _single_line),
                ((.projects_name // \"-\") | _single_line),
                ((.services_name // \"-\") | _single_line),
                ((.text // \"\") | _single_line | if . == \"\" then \"-\" else . end)
              ]
            | @tsv"
    } | column -t -s $'\t'
}

# print_entry_detail
#   Renders a single entry as a Key/Value block. For a running entry the
#   elapsed time is computed against the given server time.
#   args:    $1 = entry JSON object (not wrapped)
#            $2 = optional server time (`current_time` of /v2/clock)
print_entry_detail() {
    local entry_json="$1"
    local current_time="${2:-}"
    echo "${entry_json}" | jq -r --arg now "${current_time}" "
        $(_entries_jq_helpers)
        (if .time_until == null and \$now != \"\"
            then (\$now | _epoch) - (.time_since | _epoch)
            else null end) as \$elapsed
        | (
            \"ID:              \(.id)\",
            \"Type:            \(.type | _type_name) (\(.type))\",
            \"Users_id:        \(.users_id)\",
            \"Customers_id:    \(.customers_id)\" + (if .customers_name then \" (\(.customers_name))\" else \"\" end),
            (if .projects_id then \"Projects_id:     \(.projects_id)\" + (if .projects_name then \" (\(.projects_name))\" else \"\" end) else empty end),
            (if .subprojects_id then \"Subprojects_id:  \(.subprojects_id)\" + (if .subprojects_name then \" (\(.subprojects_name))\" else \"\" end) else empty end),
            (if .services_id then \"Services_id:     \(.services_id)\" + (if .services_name then \" (\(.services_name))\" else \"\" end) else empty end),
            (if .billable != null then \"Billable:        \(.billable)\" else empty end),
            \"Time_since:      \(.time_since | _local_time)\",
            (if .type == 1 then \"Time_until:      \(if .time_until == null then \"running\" else (.time_until | _local_time) end)\" else empty end),
            (if .duration != null then \"Duration:        \(.duration | _duration)\" else empty end),
            (if \$elapsed != null then \"Elapsed:         \(\$elapsed | _duration)\" else empty end),
            (if .text then \"Text:            \(.text)\" else empty end)
          )"
}

# print_entries_summary
#   Renders the day summary of `entries summary` as a Key/Value block.
#   Times in local time, durations as H:MM:SS; the delta is signed
#   (negative = still to work).
#   args:    $1 = summary object (see _entries_build_summary)
print_entries_summary() {
    local summary_json="$1"
    echo "${summary_json}" | jq -r "
        $(_entries_jq_helpers)
        def _signed_duration: if . == null then \"-\" elif . < 0 then \"-\" + (-. | _duration) else \"+\" + _duration end;
        def _entry_path: [.customers_name, .projects_name, .subprojects_name, .services_name]
            | map(select(. != null and . != \"\")) | join(\" / \") | _single_line;
        (
            \"Date:            \(.date)\",
            \"Users_id:        \(.users_id)\",
            \"Entries:         \(.count_entries)\",
            \"Start_of_day:    \(.start_of_day | _local_time)\",
            \"Total:           \(.total_seconds | _duration)\",
            \"Target:          \(.target_seconds | _duration)\",
            \"Delta:           \(.delta_seconds | _signed_duration)\",
            \"Percent:         \(if .percent == null then \"-\" else \"\(.percent)%\" end)\",
            (if .running == null then \"Running:         -\"
             else
                \"Running:         entry ID \(.running.id) since \(.running.time_since | _local_time) (\(.running.elapsed_seconds | _duration))\",
                \"Running_path:    \(.running | _entry_path)\"
             end)
        )"
}
