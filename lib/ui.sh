#!/usr/bin/env bash
# =============================================================================
# lib/ui.sh — Renderers shared by several command groups.
#
# Group-specific renderers stay in commands/<group>/ui.sh.
#
# Sourced by the entry script (clockodo). Dependencies: jq, column.
#
# Public API:
#   print_id_name_table <json>  — ID/Name table, sorted by name.
#   print_json_document <json>  — pretty-printed JSON.
# =============================================================================

set -euo pipefail

# print_id_name_table
#   Writes a list as an aligned table (ID, Name) to stdout, sorted
#   alphabetically by name (case-insensitive) — the API order is not stable
#   across endpoints, so we normalize here for predictable text output.
#   args:    $1 = JSON with top-level `{ "data": [ … ] }`
print_id_name_table() {
    local json="$1"
    # Header + data rows are passed to `column` together so both line up
    # against the same column widths. Missing or empty names become "-" so
    # the columns stay aligned.
    {
        printf 'ID\tName\n'
        echo "${json}" | jq -r '.data | sort_by(.name // "" | ascii_downcase) | .[] | [.id, (.name // "" | if . == "" then "-" else . end)] | @tsv'
    } | column -t -s $'\t'
}

# print_json_document
#   Pretty-prints a JSON document (text output of detail actions without a
#   dedicated Key/Value renderer).
#   args:    $1 = JSON
print_json_document() {
    echo "$1" | jq .
}
