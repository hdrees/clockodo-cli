#!/usr/bin/env bash
# =============================================================================
# commands/favorites/ui.sh — Presentation and interactive helpers specific
# to the `favorites` group.
#
# Sourced by the entry script (clockodo) alongside the help text and the
# action file. Defines the table renderer and the interactive picker used
# by the favorites actions.
#
# Prerequisites: jq.
# =============================================================================

set -euo pipefail

# print_favorites_table
#   Writes the favorite list as an aligned table (ID, Name) to stdout.
#
#   args:    $1 = favorite JSON (top-level `{ "data": [ … ] }`)
#   stdout:  table with header
print_favorites_table() {
    local json="$1"
    # Subshell block: header + data rows are passed to `column` together so
    # both line up against the same column widths.
    {
        printf 'ID\tName\n'
        # Missing, null or empty names become "-" so column does not choke.
        echo "${json}" | jq -r '.data[] | [.id, (.name // "" | if . == "" then "-" else . end)] | @tsv'
    } | column -t -s $'\t'
}

# select_favorite
#   Presents the user with a list of favorites and prints the chosen ID.
#
#   input:    favorite JSON via stdin (top-level `{ "data": [ … ] }`).
#   stdout:   numeric favorite ID
#   stderr:   "No favorites found." if the list is empty
#   exit:     0 on selection, 1 on cancel or empty list
#
#   Uses the bash builtin `select` (no external picker dependency).
select_favorite() {
    # Read the full JSON from stdin. `cat` without arguments reads stdin.
    local json
    json="$(cat)"

    # One line per favorite: "<id>\t<name>". Missing, null and empty names
    # (Clockodo allows favorites without a name) become "(no name)" — an
    # empty label could not be picked.
    local lines
    lines="$(echo "${json}" | jq -r '.data[] | "\(.id)\t\(.name // "" | if . == "" then "(no name)" else . end)"')"

    if [[ -z "${lines}" ]]; then
        echo "No favorites found." >&2
        return 1
    fi

    # Split IDs and labels into parallel arrays so we can look up the ID by
    # the user's index choice.
    local ids=() labels=()
    # `IFS=$'\t'` sets the field separator to tab (only for this read).
    # `<<<"${lines}"` is a here-string: pipes ${lines} into read's stdin.
    while IFS=$'\t' read -r id name; do
        ids+=("${id}")
        labels+=("${name}")
    done <<<"${lines}"

    # PS3 is the prompt that `select` prints.
    PS3="Select favorite: "
    local picked
    # `select` shows a numbered list; $REPLY holds the picked number.
    # `</dev/tty` is required when the caller's stdin has already been
    # consumed — otherwise select would not see any keyboard input.
    select picked in "${labels[@]}"; do
        if [[ -n "${picked}" ]]; then
            # Bash arrays are 0-indexed; REPLY is 1-indexed. select also
            # accepts input like ` 2` or `+2`, so non-digits are dropped
            # (`${REPLY//[^0-9]/}`) before `10#` forces base 10 — otherwise
            # `010` would be read as octal (8).
            local choice="${REPLY//[^0-9]/}"
            echo "${ids[$(( 10#${choice} - 1 ))]}"
            return 0
        fi
    done </dev/tty
    return 1
}
