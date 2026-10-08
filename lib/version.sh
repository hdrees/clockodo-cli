#!/usr/bin/env bash
# =============================================================================
# lib/version.sh — `clockodo version`: local vs. published CLI version.
#
# Reads the published version from the entry script on the main branch of
# the GitHub repo (the `CLOCKODO_CLI_VERSION="…"` line) and compares it with
# the local CLOCKODO_CLI_VERSION. Needs no .env — nothing is sent to
# Clockodo, and no credentials are sent to GitHub.
#
# Dependencies: lib/helper.sh, lib/http.sh (http_get_public), jq.
# =============================================================================

set -euo pipefail

# Raw URL of the entry script whose version line is the published version.
CLOCKODO_CLI_VERSION_URL="https://raw.githubusercontent.com/hdrees/clockodo-cli/main/clockodo"

# print_version_help
#   Help text for `clockodo version`.
print_version_help() {
    cat <<'EOF'
clockodo version — show the local and the published CLI version

Usage:
  clockodo version [--json]

Loads the version from the main branch of the GitHub repository and
compares it with the local one. Fails with an error if the repository
cannot be reached.
EOF
}

# cmd_version
#   Prints local version, published version and the comparison result.
#   args:    $1 optional --help/-h
#   stdout:  Key/Value block, or the JSON envelope in --json mode
#            ({local, remote, status} with status up_to_date |
#            update_available | ahead)
#   stderr:  error message if the repository is unreachable (text mode)
#   exit:    0 on success, 1 if the published version cannot be determined
cmd_version() {
    if is_help_arg "${1:-}"; then
        print_version_help
        return 0
    fi

    local remote_version
    if ! remote_version="$(_fetch_published_version)"; then
        _report_version_lookup_failure
        return 1
    fi

    local comparison
    comparison="$(_compare_versions "${CLOCKODO_CLI_VERSION}" "${remote_version}")"

    if is_json_output_mode; then
        emit_json_success "$(jq -n \
            --arg local "${CLOCKODO_CLI_VERSION}" \
            --arg remote "${remote_version}" \
            --arg status "${comparison}" \
            '{local:$local, remote:$remote, status:$status}')"
        return 0
    fi

    echo "Local version:   ${CLOCKODO_CLI_VERSION}"
    echo "Remote version:  ${remote_version}"
    case "${comparison}" in
        up_to_date)       echo "Status:          up to date" ;;
        update_available) echo "Status:          update available" ;;
        ahead)            echo "Status:          local version is ahead" ;;
    esac
}

# _fetch_published_version
#   Downloads the published entry script and extracts its version.
#   stdout:  version string (MAJOR.MINOR.PATCH)
#   exit:    1 if the download failed or no version line was found; an
#            unparsable file is recorded with status `invalid` in the HTTP
#            state file so _report_version_lookup_failure can tell it apart.
_fetch_published_version() {
    local script
    script="$(http_get_public "${CLOCKODO_CLI_VERSION_URL}")" || return 1

    # Multi-line regex match: `BASH_REMATCH[1]` holds the captured version.
    local version_pattern='CLOCKODO_CLI_VERSION="([0-9]+\.[0-9]+\.[0-9]+)"'
    if [[ "${script}" =~ ${version_pattern} ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    _clockodo_record_response invalid ""
    return 1
}

# _report_version_lookup_failure
#   Reports why the published version is unknown. Text mode prints the local
#   version first so the user still sees it.
_report_version_lookup_failure() {
    local last_status message code
    last_status="$(clockodo_last_status)"

    case "${last_status}" in
        invalid)
            message="no version found in ${CLOCKODO_CLI_VERSION_URL}"
            code="invalid_response"
            ;;
        0)
            message="repository not reachable (${CLOCKODO_CLI_VERSION_URL}): $(clockodo_last_body)"
            code="repository_unreachable"
            ;;
        *)
            message="repository not reachable (${CLOCKODO_CLI_VERSION_URL}): HTTP ${last_status}"
            code="repository_unreachable"
            ;;
    esac

    if is_json_output_mode; then
        # Only an HTTP error carries a status worth forwarding.
        local http_status=""
        [[ "${last_status}" =~ ^[1-9][0-9]*$ ]] && http_status="${last_status}"
        emit_json_failure "${message}" "${code}" "${http_status}"
        return 0
    fi

    echo "Local version:   ${CLOCKODO_CLI_VERSION}"
    echo "Error: ${message}" >&2
}

# _compare_versions
#   Compares two MAJOR.MINOR.PATCH versions numerically.
#   args:    $1 = local version, $2 = remote version
#   stdout:  up_to_date | update_available | ahead
_compare_versions() {
    local local_parts remote_parts index
    # `IFS=.` splits on dots for this `read` only; `-a` fills an array.
    IFS=. read -r -a local_parts <<<"$1"
    IFS=. read -r -a remote_parts <<<"$2"

    for index in 0 1 2; do
        # `10#` forces base 10, so parts like "08" are not read as octal.
        if (( 10#${local_parts[index]} < 10#${remote_parts[index]} )); then
            echo "update_available"
            return 0
        fi
        if (( 10#${local_parts[index]} > 10#${remote_parts[index]} )); then
            echo "ahead"
            return 0
        fi
    done
    echo "up_to_date"
}
