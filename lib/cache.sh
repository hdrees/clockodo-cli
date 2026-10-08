#!/usr/bin/env bash
# =============================================================================
# lib/cache.sh — Optional file-based caching for list/detail endpoints.
#
# Sourced by the entry script (clockodo) after lib/helper.sh, lib/http.sh
# and lib/pagination.sh (we wrap both `clockodo_api_get` and
# `clockodo_api_get_all`). The cache directory is resolved lazily, because
# it depends on CLOCKODO_API_URL / CLOCKODO_API_USER, which load_env sets after
# this file is sourced.
#
# Enable globally via `CACHE=1` (default: off). Cache files live in
# `${XDG_CACHE_HOME:-$HOME/.cache}/clockodo-cli/<account>/`, where
# <account> is a hash of API URL + user, so two accounts or instances never
# see each other's data. Files are keyed by the endpoint path including its
# query string (filtered list variants get their own file). Freshness is
# determined by file mtime + a per-endpoint TTL.
#
# Public API:
#   is_cache_enabled                                — guard for opt-in.
#   clockodo_cache_entries                          — statistics of every
#                                                     cache entry (JSON).
#   clockodo_cache_delete <key|path>                — deletes one entry.
#   clockodo_cache_clear                            — deletes every entry.
#   clockodo_api_get_cached <path> <ttl>            — single-shot GET, cached.
#   clockodo_api_get_all_cached <path> <ttl>        — paginated GET, cached.
#   clockodo_api_get_cached_via_list <detail_path> <list_path> <id> <ttl>
#                                                   — single-resource GET that
#                                                     prefers an entry from a
#                                                     fresh list cache.
#
# Per the design (see CLAUDE.md): list endpoints write cache files;
# single-resource GETs NEVER write their own cache file — they read from
# the corresponding list cache or fall back to the API.
# =============================================================================

set -euo pipefail

# Root of all cache data of this CLI (every account has a subdirectory).
CLOCKODO_CACHE_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/clockodo-cli"

# Directory name used before the per-account layout and the rename to
# `clockodo-cli`; removed on the next cache write (see _cache_remove_legacy_files).
CLOCKODO_LEGACY_CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/clockodo_cli"

# is_cache_enabled
#   Returns 0 when caching is opt-in via the CACHE env var. Always off in
#   --curl mode, so the printed command is the request that would really be
#   sent instead of being masked by a cache hit.
is_cache_enabled() {
    is_curl_output_mode && return 1
    [[ "${CACHE:-0}" == "1" ]]
}

# _cache_account_hash
#   Prints a short hash identifying the account (API URL + user).
#   Uses sha256sum (GNU) or shasum (BSD/macOS).
_cache_account_hash() {
    local account="${CLOCKODO_API_URL};${CLOCKODO_API_USER}"
    local digest
    if command -v sha256sum >/dev/null 2>&1; then
        digest="$(printf '%s' "${account}" | sha256sum)"
    else
        digest="$(printf '%s' "${account}" | shasum -a 256)"
    fi
    # `${digest:0:16}` = first 16 hex characters (drops the "  -" suffix).
    printf '%s' "${digest:0:16}"
}

# _cache_dir
#   Prints the cache directory of the configured account.
_cache_dir() {
    printf '%s/%s' "${CLOCKODO_CACHE_ROOT}" "$(_cache_account_hash)"
}

# _cache_file_name
#   The only place that knows the cache filename scheme:
#   "<path-key>.json" without, "<path-key>__<query-key>.json" with a query.
#   _cache_list_variant_pattern passes `*` as query key to match every variant.
#   args:    $1 = path key (see _cache_path_key), $2 = query key (may be empty)
#   stdout:  file name
_cache_file_name() {
    local path_key="$1" query_key="${2:-}"
    if [[ -z "${query_key}" ]]; then
        printf '%s.json' "${path_key}"
    else
        printf '%s__%s.json' "${path_key}" "${query_key}"
    fi
}

# _cache_path_key
#   Turns the path part of an endpoint into a filename-safe key.
#   args:    $1 = endpoint path (a query string is ignored)
#   stdout:  e.g. /v3/customers → v3_customers
_cache_path_key() {
    # `${1%%\?*}` = everything before the first `?` (the path itself).
    local path="${1%%\?*}"
    # Strip leading slash (so the key doesn't start with `_`).
    path="${path#/}"
    # Replace slashes with underscores.
    printf '%s' "${path//\//_}"
}

# _cache_query_key
#   Turns the query string of an endpoint into a filename-safe key.
#   args:    $1 = endpoint path (may include a query string)
#   stdout:  e.g. ?filter%5Bactive%5D=true → filter-active-true; empty
#            without a query string
_cache_query_key() {
    local path="$1"
    [[ "${path}" == *\?* ]] || return 0
    # `${path#*\?}` = everything after the first `?` (the query string).
    local query="${path#*\?}"
    # Make the query filename-safe: `%5B` → `-`, drop `%5D`, then every
    # remaining non-alphanumeric character (`=`, `&`, …) → `-`.
    query="${query//%5B/-}"
    query="${query//%5D/}"
    printf '%s' "${query//[^A-Za-z0-9_-]/-}"
}

# _cache_key_for_path
#   Turns an API path into a cache filename. The query string is part of the
#   key so filtered variants of a list (e.g. `?filter%5Bactive%5D=true`) get
#   their own file instead of overwriting each other.
#   args:    $1 = endpoint path (may include a query string).
#   stdout:  e.g. /v3/customers                          → v3_customers.json
#                 /v3/customers?filter%5Bactive%5D=true  → v3_customers__filter-active-true.json
_cache_key_for_path() {
    _cache_file_name "$(_cache_path_key "$1")" "$(_cache_query_key "$1")"
}

# _cache_list_variant_pattern
#   Prints the file name pattern matching every filtered variant of a list
#   (a name only, so callers can quote the directory and glob the name).
#   args:    $1 = list path without query string (e.g. /v3/customers)
#   stdout:  e.g. v3_customers__*.json
_cache_list_variant_pattern() {
    _cache_file_name "$(_cache_path_key "$1")" '*'
}

# _cache_file_path
#   Resolves a path to the absolute on-disk cache file location.
_cache_file_path() {
    printf '%s/%s' "$(_cache_dir)" "$(_cache_key_for_path "$1")"
}

# _cache_mtime
#   Prints the modification time (epoch seconds) of a file, 0 if unknown.
#   Tries GNU `stat -c` first, then BSD `stat -f`.
_cache_mtime() {
    stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || echo 0
}

# _cache_age_seconds
#   Echoes the age (in seconds) of a cache file, or empty when missing.
_cache_age_seconds() {
    local file="$1"
    [[ -f "${file}" ]] || return 0
    printf '%s' "$(( $(date +%s) - $(_cache_mtime "${file}") ))"
}

# _cache_is_fresh
#   args:    $1 = cache file, $2 = TTL in seconds.
#   exit:    0 when the file exists and (now - mtime) <= ttl, else 1.
_cache_is_fresh() {
    local file="$1" ttl="$2"
    [[ -f "${file}" ]] || return 1
    local age
    age="$(_cache_age_seconds "${file}")"
    (( age <= ttl ))
}

# _cache_log
#   args:    $1 = banner suffix (e.g. "HIT", "MISS", "HIT (from list)")
#            $2 = body line (the explanation)
#   Only writes to stderr when debug output is enabled (DEBUG=1, not in
#   --json mode); mirrors the layout used in lib/http.sh.
_cache_log() {
    is_debug_enabled || return 0
    local banner="$1" body="$2"
    {
        echo "── CACHE ${banner} ─────────────────────────────"
        echo "${body}"
        echo "──────────────────────────────────────────"
    } >&2
}

# _cache_remove_legacy_files
#   Deletes cache files of earlier layouts, which nothing reads or expires:
#   the old `clockodo_cli` directory and flat `*.json` files directly in the
#   cache root (before the per-account subdirectories).
_cache_remove_legacy_files() {
    rm -rf "${CLOCKODO_LEGACY_CACHE_DIR}"
    rm -f "${CLOCKODO_CACHE_ROOT}"/*.json
}

# _cache_write_atomically
#   Writes content to a file via tmp + rename, so concurrent readers never
#   see a half-written file. `mv -f` is atomic when src and dst are on the
#   same filesystem (which they are by construction: same directory).
#   args:  $1 = target file, $2 = content
_cache_write_atomically() {
    local file="$1" content="$2"
    local tmp="${file}.tmp.$$"
    printf '%s' "${content}" > "${tmp}" && mv -f "${tmp}" "${file}"
}

# _cache_write
#   Writes content to the cache file for <path>, plus the metadata file
#   `<file>.meta` ({"path": …, "ttl": …}) read by `cache list`. Creates the
#   cache dir on demand.
#   args:  $1 = endpoint path, $2 = content, $3 = TTL seconds
_cache_write() {
    local path="$1" content="$2" ttl="$3"
    _cache_remove_legacy_files
    mkdir -p "$(_cache_dir)"
    local file
    file="$(_cache_file_path "${path}")"
    _cache_write_atomically "${file}" "${content}"
    _cache_write_atomically "${file}.meta" "$(jq -nc --arg path "${path}" --argjson ttl "${ttl}" '{path:$path, ttl:$ttl}')"
}

# _cache_log_miss
#   Logs why <file> could not be used: expired or not created yet.
#   args:    $1 = endpoint path, $2 = cache file, $3 = TTL seconds
_cache_log_miss() {
    local path="$1" file="$2" ttl="$3"
    if [[ -f "${file}" ]]; then
        _cache_log MISS "${path} (expired age $(_cache_age_seconds "${file}")s, ttl ${ttl}s)"
    else
        _cache_log MISS "${path} (no cache yet, ttl ${ttl}s)"
    fi
}

# _cache_through
#   Shared read-through logic of the cached GET wrappers: serve a fresh
#   cache file, otherwise call the fetcher and cache its result.
#   args:    $1 = fetcher function (clockodo_api_get | clockodo_api_get_all),
#            $2 = endpoint path, $3 = TTL seconds
#   stdout:  response body
#   exit:    0 on success, 1 if the fetcher failed (nothing is cached)
_cache_through() {
    local fetcher="$1" path="$2" ttl="$3"

    if ! is_cache_enabled; then
        "${fetcher}" "${path}"
        return $?
    fi

    local file
    file="$(_cache_file_path "${path}")"

    if _cache_is_fresh "${file}" "${ttl}"; then
        _cache_log HIT "${path} (age $(_cache_age_seconds "${file}")s, ttl ${ttl}s)"
        cat "${file}"
        return 0
    fi

    _cache_log_miss "${path}" "${file}" "${ttl}"

    local fresh
    if ! fresh="$("${fetcher}" "${path}")"; then
        return 1
    fi
    _cache_write "${path}" "${fresh}" "${ttl}"
    printf '%s' "${fresh}"
}

# clockodo_api_get_cached
#   Single-shot cached GET. Falls back to a plain clockodo_api_get when
#   caching is disabled or the cache is stale/absent.
#   args:    $1 = endpoint path, $2 = TTL seconds.
clockodo_api_get_cached() {
    _cache_through clockodo_api_get "$1" "$2"
}

# clockodo_api_get_all_cached
#   Paginated cached GET. Same semantics as clockodo_api_get_cached but uses
#   clockodo_api_get_all under the hood.
clockodo_api_get_all_cached() {
    _cache_through clockodo_api_get_all "$1" "$2"
}

# _cache_fresh_list_variant_files
#   Lists every fresh cache file of a list endpoint — the unfiltered one and
#   all filtered variants (`<key>__<query>.json`) — newest first, one path
#   per line.
#   args:    $1 = list_path without query string (e.g. "/v3/customers")
#            $2 = TTL seconds
#   stdout:  existing fresh file paths (may be empty)
_cache_fresh_list_variant_files() {
    local list_path="$1" ttl="$2"
    local cache_dir base_file variant_pattern
    cache_dir="$(_cache_dir)"
    base_file="$(_cache_file_path "${list_path}")"
    variant_pattern="$(_cache_list_variant_pattern "${list_path}")"
    local file
    # The quoted directory is taken literally, the unquoted pattern is
    # globbed. An unmatched glob stays literal, so the -f test in
    # _cache_is_fresh skips it.
    for file in "${base_file}" "${cache_dir}"/${variant_pattern}; do
        _cache_is_fresh "${file}" "${ttl}" || continue
        printf '%s\t%s\n' "$(_cache_mtime "${file}")" "${file}"
    done | sort -rn | cut -f 2-
}

# clockodo_api_get_cached_via_list
#   Single-resource GET. Looks up <id> in the fresh cached variants of the
#   list at <list_path> (unfiltered and filtered, e.g. by --state), the
#   newest variant first; falls back to a direct detail API call otherwise.
#   NEVER writes its own cache file.
#   args:    $1 = detail_path (e.g. "/v3/customers/4682209")
#            $2 = list_path   (e.g. "/v3/customers", without query string)
#            $3 = id          (numeric)
#            $4 = ttl         (used to validate list-cache freshness)
clockodo_api_get_cached_via_list() {
    local detail_path="$1" list_path="$2" id="$3" ttl="$4"

    if ! is_cache_enabled; then
        clockodo_api_get "${detail_path}"
        return $?
    fi

    local list_files=() list_file
    while IFS= read -r list_file; do
        list_files+=("${list_file}")
    done < <(_cache_fresh_list_variant_files "${list_path}" "${ttl}")

    # One jq run over all variants in order. `first(…)` stops at the first
    # match, so duplicate IDs (e.g. from pagination drift) yield one result.
    # `-c` keeps the hit on one line: file name, tab, item.
    local hit=""
    if (( ${#list_files[@]} > 0 )); then
        hit="$(jq -nrc --argjson id "${id}" \
            'first(inputs | .data[]? | select(.id == $id) | "\(input_filename)\t\(tojson)")' \
            "${list_files[@]}" 2>/dev/null)" || hit=""
    fi

    if [[ -n "${hit}" ]]; then
        # `${hit%%$'\t'*}` = file name before the tab, `${hit#*$'\t'}` = item.
        list_file="${hit%%$'\t'*}"
        _cache_log "HIT (from list)" "id ${id} found in ${list_file##*/} (age $(_cache_age_seconds "${list_file}")s)"
        # Wrap to mirror the detail endpoint's shape: { "data": <item> }.
        jq -c '{data:.}' <<<"${hit#*$'\t'}"
        return 0
    fi

    _cache_log "MISS (from list)" "id ${id} not in any fresh ${list_path} cache → API fallback"
    clockodo_api_get "${detail_path}"
}

# _cache_size_bytes
#   Prints the size of a file in bytes. Tries GNU `stat -c` first, then BSD
#   `stat -f`.
_cache_size_bytes() {
    stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1" 2>/dev/null || echo 0
}

# _cache_entry_files
#   Lists every cache file of the configured account (without metadata
#   files), sorted by name, one path per line.
_cache_entry_files() {
    local file
    # An unmatched glob stays literal — the -f test skips it.
    for file in "$(_cache_dir)"/*.json; do
        [[ -f "${file}" ]] && printf '%s\n' "${file}"
    done
    return 0
}

# _cache_entry_statistics
#   Prints the statistics of one cache file as a JSON object (no content):
#     key (file name without .json), path (endpoint, null for files written
#     before metadata existed), items (length of the response's item array,
#     1 for a single object), size_bytes, age_seconds, ttl_seconds,
#     remaining_seconds (null without TTL; negative once expired), fresh.
#     An unreadable (non-JSON) file yields {key, invalid: true}.
#   args:  $1 = cache file
_cache_entry_statistics() {
    local file="$1"
    local name="${file##*/}"
    local metadata="null"
    if [[ -f "${file}.meta" ]]; then
        metadata="$(cat "${file}.meta")"
    fi

    # Item count: the `data` array, otherwise the first top-level array
    # (e.g. `targethours`, `entries`), otherwise 1 for a single object.
    jq -c \
        --arg key "${name%.json}" \
        --argjson metadata "${metadata}" \
        --argjson size "$(_cache_size_bytes "${file}")" \
        --argjson age "$(_cache_age_seconds "${file}")" \
        '(if (.data | type) == "array" then (.data | length)
          else ([.[]? | arrays] | if length > 0 then (.[0] | length) else 1 end)
          end) as $items
        | ($metadata.ttl // null) as $ttl
        | {
            key: $key,
            path: ($metadata.path // null),
            items: $items,
            size_bytes: $size,
            age_seconds: $age,
            ttl_seconds: $ttl,
            remaining_seconds: (if $ttl == null then null else $ttl - $age end),
            fresh: (if $ttl == null then null else $age <= $ttl end)
          }' < "${file}" 2>/dev/null \
        || jq -nc --arg key "${name%.json}" '{key:$key, invalid:true}'
}

# clockodo_cache_entries
#   Statistics of every cache entry of the configured account.
#   stdout:  JSON array of _cache_entry_statistics objects, sorted by key
clockodo_cache_entries() {
    local file
    while IFS= read -r file; do
        _cache_entry_statistics "${file}"
    done < <(_cache_entry_files) | jq -s 'sort_by(.key)'
}

# _cache_key_from_argument
#   Turns a `cache delete` argument into a cache key: an endpoint path
#   (starting with `/`, e.g. /v3/customers?filter%5Bactive%5D=true) is
#   mapped like on write; anything else must already be a key as shown by
#   `cache list`. Keys are restricted to [A-Za-z0-9_-], so an argument can
#   never point outside the cache directory.
#   args:    $1 = key or endpoint path
#   stdout:  key (file name without .json)
#   exit:    1 if the argument is not a valid key
_cache_key_from_argument() {
    local argument="$1" key
    if [[ "${argument}" == /* ]]; then
        key="$(_cache_key_for_path "${argument}")"
        key="${key%.json}"
    else
        key="${argument%.json}"
    fi
    [[ "${key}" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
    printf '%s' "${key}"
}

# clockodo_cache_delete
#   Deletes one cache entry (cache file and its metadata).
#   args:    $1 = key (see `cache list`) or endpoint path
#   stdout:  the deleted key
#   exit:    0 if deleted, 1 if the argument is invalid, 2 if no such entry
clockodo_cache_delete() {
    local key
    key="$(_cache_key_from_argument "$1")" || return 1
    local file
    file="$(_cache_dir)/${key}.json"
    [[ -f "${file}" ]] || return 2
    rm -f "${file}" "${file}.meta"
    printf '%s' "${key}"
}

# clockodo_cache_clear
#   Deletes every cache entry of the configured account (other accounts'
#   subdirectories are left alone) and files of older cache layouts.
#   stdout:  number of deleted entries
clockodo_cache_clear() {
    local count=0 file
    while IFS= read -r file; do
        rm -f "${file}" "${file}.meta"
        count=$(( count + 1 ))
    done < <(_cache_entry_files)
    # Leftovers: metadata without data file, interrupted tmp writes.
    rm -f "$(_cache_dir)"/*.meta "$(_cache_dir)"/*.tmp.*
    _cache_remove_legacy_files
    printf '%s' "${count}"
}
