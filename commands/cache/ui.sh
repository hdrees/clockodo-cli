#!/usr/bin/env bash
# =============================================================================
# commands/cache/ui.sh — Presentation helpers for the cache group.
#
# Dependencies: jq, column.
# =============================================================================

set -euo pipefail

# print_cache_entries_table
#   Writes the cache statistics as an aligned table, sorted by key, plus a
#   summary line. Durations as H:MM:SS; a negative remaining TTL is shown
#   as "expired", unknown values as "-".
#   args:    $1 = JSON array of cache entry statistics (clockodo_cache_entries)
#            $2 = cache directory (for the summary line)
print_cache_entries_table() {
    local entries_json="$1" cache_dir="$2"

    if [[ "$(jq 'length' <<<"${entries_json}")" == "0" ]]; then
        echo "No cache entries in ${cache_dir}."
        return 0
    fi

    {
        printf 'Key\tItems\tSize\tAge\tTTL\tRemaining\n'
        jq -r '
            def _two_digits: tostring | if length < 2 then "0" + . else . end;
            def _duration:
                if . == null then "-"
                else floor as $seconds
                    | "\($seconds / 3600 | floor):\($seconds % 3600 / 60 | floor | _two_digits):\($seconds % 60 | _two_digits)"
                end;
            .[]
            | if .invalid then [.key, "invalid", "-", "-", "-", "-"]
              else [
                .key,
                .items,
                "\(.size_bytes) B",
                (.age_seconds | _duration),
                (.ttl_seconds | _duration),
                (if .remaining_seconds == null then "-"
                 elif .remaining_seconds < 0 then "expired"
                 else (.remaining_seconds | _duration) end)
              ]
              end
            | @tsv' <<<"${entries_json}"
    } | column -t -s $'\t'

    echo
    jq -r --arg dir "${cache_dir}" '
        "\(length) entries, \(map(.items // 0) | add) items, \(map(.size_bytes // 0) | add) bytes in \($dir)"' <<<"${entries_json}"
    if ! is_cache_enabled; then
        echo "Note: caching is off — enable it with CACHE=1."
    fi
}
