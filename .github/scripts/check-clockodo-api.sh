#!/usr/bin/env bash
# Compares the published Clockodo OpenAPI spec with the snapshot checked into
# this repo (.github/clockodo-api-snapshot.json): the spec version
# (`info.version`) and the list of operations ("METHOD /path").
#
# Used by .github/workflows/clockodo-api-check.yml (nightly) and by hand to
# accept a new API state after the CLI was checked against it.
#
# Usage:
#   check-clockodo-api.sh            compare; exit 0 = unchanged, 2 = changed
#                                    (Markdown report on stdout), 1 = error
#   check-clockodo-api.sh --update   rewrite the snapshot from the live spec
#
# Dependencies: curl, jq, yq (mikefarah v4, preinstalled on GitHub runners).

# -e: abort on errors, -u: unset variables are errors, -o pipefail: a pipe
# fails if any part of it fails (not only the last command).
set -euo pipefail

readonly SPEC_URL="${CLOCKODO_OPENAPI_URL:-https://docs.clockodo.com/openapi.yaml}"
# ${BASH_SOURCE[0]%/*} strips the file name -> directory of this script.
readonly SNAPSHOT_FILE="${BASH_SOURCE[0]%/*}/../clockodo-api-snapshot.json"
readonly EXIT_CHANGED=2

# Downloads the spec and prints the current snapshot JSON
# ({"version": "...", "operations": ["GET /v2/clock", …]}, operations sorted).
# Exit code ≠ 0 if the download or the parsing fails.
build_current_snapshot() {
    local spec_file
    spec_file="$(mktemp)"
    # Single quotes: expand ${spec_file} now, not when the trap fires.
    trap 'rm -f "'"${spec_file}"'"' RETURN

    curl --disable --silent --show-error --fail --location \
        --max-time 60 --output "${spec_file}" "${SPEC_URL}"

    yq --output-format=json '{
        "version": .info.version,
        "operations": [
            .paths | to_entries[] | .key as $path
            | .value | keys[] | select(test("^(get|put|post|patch|delete)$"))
            | upcase + " " + $path
        ]
    }' "${spec_file}" \
        | jq '.operations |= (unique | sort) | .version |= tostring'
}

# Prints a Markdown report of the differences between two snapshots.
# Arguments: <known-snapshot-json> <current-snapshot-json>
print_change_report() {
    local known_snapshot="$1"
    local current_snapshot="$2"

    jq --null-input --raw-output \
        --argjson known "${known_snapshot}" \
        --argjson current "${current_snapshot}" '
        ($current.operations - $known.operations) as $added
        | ($known.operations - $current.operations) as $removed
        | def listing($items): if ($items | length) == 0 then "_none_"
                               else $items | map("- `\(.)`") | join("\n") end;
        "The published Clockodo OpenAPI spec differs from the snapshot in `.github/clockodo-api-snapshot.json`.\n\n"
        + "| | Version |\n|---|---|\n"
        + "| Known | `\($known.version)` |\n| Published | `\($current.version)` |\n\n"
        + "### Added operations (\($added | length))\n\n\(listing($added))\n\n"
        + "### Removed operations (\($removed | length))\n\n\(listing($removed))\n\n"
        + "The operation lists do not cover schema changes (fields, parameters, responses) — check the endpoints the CLI uses.\n\n"
        + "When the CLI is verified against the new spec, accept it with `.github/scripts/check-clockodo-api.sh --update`, commit the snapshot and close this issue."
    '
}

main() {
    local current_snapshot
    current_snapshot="$(build_current_snapshot)"

    if [[ "${1:-}" == "--update" ]]; then
        echo "${current_snapshot}" > "${SNAPSHOT_FILE}"
        echo "Snapshot updated: version $(jq --raw-output '.version' <<< "${current_snapshot}")" >&2
        return 0
    fi

    local known_snapshot
    known_snapshot="$(jq '.' "${SNAPSHOT_FILE}")"

    if [[ "$(jq --compact-output '.' <<< "${known_snapshot}")" == "$(jq --compact-output '.' <<< "${current_snapshot}")" ]]; then
        echo "Clockodo API unchanged: version $(jq --raw-output '.version' <<< "${current_snapshot}")" >&2
        return 0
    fi

    print_change_report "${known_snapshot}" "${current_snapshot}"
    return "${EXIT_CHANGED}"
}

main "$@"
