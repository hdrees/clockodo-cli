#!/usr/bin/env bash
# =============================================================================
# commands/absences/ui.sh — Presentation helpers for the absences group.
#
# AbsenceV4 is a oneOf hour|day absence; both variants share id, users_id,
# date_since, date_until, type, status, count_days, count_hours. The `type`
# and `status` fields are integer enums — they are mapped to their canonical
# names from the OpenAPI spec for readability.
# =============================================================================

set -euo pipefail

# _absence_jq_lookups
#   Echoes a jq snippet that defines `_type_name` and `_status_name`
#   functions. Re-used by both renderers — keeps the enum tables in one place.
#
#   Enum values are sourced from OpenAPI:
#     AbsenceStatus (0–4) and AbsenceType (1–15).
_absence_jq_lookups() {
    cat <<'JQ'
def _type_name:
    {
        "1": "RegularHoliday",
        "2": "SpecialLeave",
        "3": "OverTimeReduction",
        "4": "SickSelf",
        "5": "SickChild",
        "6": "School",
        "7": "MaternityProtection",
        "8": "HomeOffice",
        "9": "OutOfOffice",
        "10": "SpecialLeaveUnpaid",
        "11": "SickSelfUnpaid",
        "12": "SickChildUnpaid",
        "13": "Quarantine",
        "14": "MilitaryService",
        "15": "SickSelfWithCertificate"
    }[tostring] // tostring;
def _status_name:
    {
        "0": "Enquired",
        "1": "Approved",
        "2": "Declined",
        "3": "ApprovalCancelled",
        "4": "Cancelled"
    }[tostring] // tostring;
JQ
}

# print_absences_table
#   Writes the absences list as an aligned table to stdout.
#   args:    $1 = JSON with top-level `{ "data": [ … ] }`.
#   columns: ID, Users_id, Type, Since, Until, Status, Days
print_absences_table() {
    local json="$1"
    {
        printf 'ID\tUsers_id\tType\tSince\tUntil\tStatus\tDays\n'
        echo "${json}" | jq -r "
            $(_absence_jq_lookups)
            .data
            | sort_by(.users_id, .date_since)
            | .[]
            | [
                .id,
                .users_id,
                (.type | _type_name),
                .date_since,
                (.date_until // \"-\"),
                (.status | _status_name),
                (.count_days // \"-\")
              ]
            | @tsv"
    } | column -t -s $'\t'
}

# print_absence_detail
#   Renders a single absence as a Key/Value block.
#   args:    $1 = JSON with top-level `{ "data": { … } }`.
print_absence_detail() {
    local json="$1"
    echo "${json}" | jq -r "
        $(_absence_jq_lookups)
        .data
        | (
            \"ID:              \(.id)\",
            \"Users_id:        \(.users_id)\",
            \"Type:            \(.type | _type_name) (\(.type))\",
            \"Status:          \(.status | _status_name) (\(.status))\",
            \"Date_since:      \(.date_since)\",
            \"Date_until:      \(.date_until // \"-\")\",
            (if .count_days != null then \"Count_days:      \(.count_days)\" else empty end),
            (if .count_hours != null then \"Count_hours:     \(.count_hours)\" else empty end),
            (if .sick_note != null then \"Sick_note:       \(.sick_note)\" else empty end),
            (if .note then \"Note:            \(.note)\" else empty end),
            (if .public_note then \"Public_note:     \(.public_note)\" else empty end),
            (if .date_enquired then \"Date_enquired:   \(.date_enquired)\" else empty end),
            (if .date_approved then \"Date_approved:   \(.date_approved)\" else empty end),
            (if .approved_by then \"Approved_by:     \(.approved_by)\" else empty end)
          )"
}
