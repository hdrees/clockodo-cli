#!/usr/bin/env bash
# =============================================================================
# commands/targethours/ui.sh — Presentation helpers for the targethours group.
#
# TargetHourV1 is a oneOf weekly|monthly with disjoint fields. Both variants
# share id/users_id/type/date_since/date_until; weekly carries per-weekday
# hours, monthly carries `monthly_target`.
# =============================================================================

set -euo pipefail

# print_targethours_table
#   Writes the target-hours list as an aligned table to stdout.
#   args:    $1 = JSON wrapped as `{ "data": [ … ] }` (already normalized
#                 from the API's `.targethours` envelope).
#   columns: ID, Users_id, Type, Since, Until, Target
#            (Target = `monthly_target` for monthly entries, sum of weekday
#            hours for weekly entries.)
print_targethours_table() {
    local json="$1"
    {
        printf 'ID\tUsers_id\tType\tSince\tUntil\tTarget\n'
        # Sort by users_id (asc), then by date_since (asc) for predictable output.
        # `// "-"` keeps the column alignment when fields are null.
        echo "${json}" | jq -r '.data
            | sort_by(.users_id, .date_since)
            | .[]
            | [
                .id,
                .users_id,
                .type,
                .date_since,
                (.date_until // "-"),
                (
                    if .type == "monthly" then .monthly_target
                    else (.monday + .tuesday + .wednesday + .thursday + .friday + .saturday + .sunday)
                    end
                )
              ]
            | @tsv'
    } | column -t -s $'\t'
}

# print_targethour_detail
#   Renders a single target-hours entry as a Key/Value block.
#   args:    $1 = JSON wrapped as `{ "data": { … } }`.
print_targethour_detail() {
    local json="$1"
    # Branch on `type` so weekly entries show per-weekday hours and monthly
    # entries show the monthly target. Lines for absent fields are dropped
    # via `// empty` to keep the block compact.
    echo "${json}" | jq -r '.data
        | (
            "ID:                    \(.id)",
            "Users_id:              \(.users_id)",
            "Type:                  \(.type)",
            "Date_since:            \(.date_since)",
            "Date_until:            \(.date_until // "-")",
            (if .surcharge_models_id then "Surcharge_models_id:   \(.surcharge_models_id)" else empty end),
            (if has("test_data") then "Test_data:             \(.test_data)" else empty end),
            (if .type == "monthly" then
                ("Monthly_target:        \(.monthly_target) h"),
                ("Workday_monday:        \(.workday_monday)"),
                ("Workday_tuesday:       \(.workday_tuesday)"),
                ("Workday_wednesday:     \(.workday_wednesday)"),
                ("Workday_thursday:      \(.workday_thursday)"),
                ("Workday_friday:        \(.workday_friday)"),
                ("Workday_saturday:      \(.workday_saturday)"),
                ("Workday_sunday:        \(.workday_sunday)"),
                (if .compensation_monthly != null then "Compensation_monthly:  \(.compensation_monthly) h" else empty end)
             else
                ("Monday:                \(.monday) h"),
                ("Tuesday:               \(.tuesday) h"),
                ("Wednesday:             \(.wednesday) h"),
                ("Thursday:              \(.thursday) h"),
                ("Friday:                \(.friday) h"),
                ("Saturday:              \(.saturday) h"),
                ("Sunday:                \(.sunday) h"),
                (if .compensation_daily != null then "Compensation_daily:    \(.compensation_daily) min" else empty end),
                (if .compensation_monthly != null then "Compensation_monthly:  \(.compensation_monthly) min" else empty end)
             end),
            (if .holiday_fixed_credit != null then "Holiday_fixed_credit:  \(.holiday_fixed_credit)" else empty end)
          )'
}
