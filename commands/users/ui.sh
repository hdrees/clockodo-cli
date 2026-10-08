#!/usr/bin/env bash
# =============================================================================
# commands/users/ui.sh — Presentation helpers for the users group.
#
# The list table is the shared print_id_name_table (lib/ui.sh).
# =============================================================================

set -euo pipefail

# print_user_detail
#   Renders a single user as a Key/Value block (text mode).
#   args:    $1 = user JSON with top-level `{ "data": { … } }`
print_user_detail() {
    local json="$1"
    # `// empty` removes the line entirely when the field is missing; the
    # caller-facing layout stays compact and only shows fields the API
    # actually returned for this user.
    echo "${json}" | jq -r '.data
        | (
            "ID:        \(.id)",
            "Name:      \(.name)",
            (if .number then "Number:    \(.number)" else empty end),
            "Active:    \(.active)",
            (if .teams_id then "Teams_id:  \(.teams_id)" else empty end),
            (if .initials then "Initials:  \(.initials)" else empty end),
            (if .language then "Language:  \(.language)" else empty end),
            (if .timezone then "Timezone:  \(.timezone)" else empty end),
            (if .email then "Email:     \(.email)" else empty end)
          )'
}
