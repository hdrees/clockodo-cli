#!/usr/bin/env bash
# =============================================================================
# lib/doctor.sh — `clockodo doctor`: checks tools, configuration and API
# access, and reports every problem instead of stopping at the first one.
#
# A top-level command, dispatched by the entry script before .env is
# loaded: it reads the configuration itself (read_env_file_defaults), so a
# missing or broken .env becomes a reported check, not an abort.
#
# The API check sends one GET /v4/users/me. Its response contains personal
# data (name, email), so only the HTTP outcome is reported, never the body.
#
# Dependencies: lib/helper.sh, lib/http.sh, lib/env.sh, lib/cache.sh, jq.
# =============================================================================

set -euo pipefail

# Lowest curl version that supports `--header @-` (headers from stdin, see
# _clockodo_request in lib/http.sh).
DOCTOR_MINIMUM_CURL_VERSION="7.55.0"

# Results of the checks so far, one compact JSON object per element:
# {name, status, message} with status ok | warn | fail | skip.
DOCTOR_CHECK_RESULTS=()

# print_doctor_help
#   Help text for `clockodo doctor`.
print_doctor_help() {
    cat <<'EOF'
clockodo doctor — check tools, configuration and API access

Usage:
  clockodo doctor [--json]

Checks bash, curl and jq, the env file, the mandatory credentials, the API
URL and the cache directory (with CACHE=1), and whether the API accepts the
credentials (one GET /v4/users/me; only the HTTP outcome is shown, never
the user data). Also shows whether read-only mode is on.

Every check is run and reported; the exit code is 1 if any check failed.
In --json mode the envelope is a success with data {healthy, checks}, the
exit code is 1 if healthy is false. Not supported with --curl.
EOF
}

# cmd_doctor
#   Runs every check and renders the results.
#   args:    $1 optional --help/-h
#   stdout:  one line per check, or the JSON envelope in --json mode
#   exit:    0 if no check failed, 1 otherwise (or on --curl)
cmd_doctor() {
    if has_help_arg "$@"; then
        print_doctor_help
        return 0
    fi
    if is_curl_output_mode; then
        emit_argument_error "doctor runs several checks; --curl is not supported"
        return 1
    fi

    _doctor_check_bash
    _doctor_check_curl
    _doctor_check_jq
    _doctor_check_configuration
    _doctor_check_cache
    _doctor_check_read_only_mode

    _doctor_render_results
    ! _doctor_has_failures
}

# _doctor_record
#   Appends one check result.
#   args:  $1 = check name, $2 = ok | warn | fail | skip, $3 = message
_doctor_record() {
    DOCTOR_CHECK_RESULTS+=("$(jq -cn --arg name "$1" --arg status "$2" --arg message "$3" \
        '{name:$name, status:$status, message:$message}')")
}

# _doctor_check_bash
#   bash 4+ is required (associative arrays, `${var,,}`, mapfile).
_doctor_check_bash() {
    # BASH_VERSINFO[0] is the major version of the running bash.
    if (( BASH_VERSINFO[0] >= 4 )); then
        _doctor_record bash ok "bash ${BASH_VERSION}"
    else
        _doctor_record bash fail "bash ${BASH_VERSION} is too old, bash 4+ is required"
    fi
}

# _doctor_check_curl
#   curl is guaranteed by the entry script; its version must support
#   `--header @-`.
_doctor_check_curl() {
    local version
    # First line of `curl --version` is "curl 7.81.0 (x86_64-…) …".
    version="$(curl --disable --version | head -n 1 | cut -d ' ' -f 2)"
    if _doctor_version_at_least "${version}" "${DOCTOR_MINIMUM_CURL_VERSION}"; then
        _doctor_record curl ok "curl ${version}"
    else
        _doctor_record curl fail "curl ${version} is too old, ${DOCTOR_MINIMUM_CURL_VERSION}+ is required"
    fi
}

# _doctor_check_jq
#   jq is guaranteed by the entry script; only its version is reported.
_doctor_check_jq() {
    _doctor_record jq ok "$(jq --version)"
}

# _doctor_check_configuration
#   Env file, mandatory credentials, API URL and API access, in this order:
#   every later check needs the earlier ones to pass and is skipped if not.
_doctor_check_configuration() {
    if ! read_env_file_defaults; then
        _doctor_record env_file fail "CLOCKODO_ENV_FILE not found: ${CLOCKODO_ENV_FILE}"
        _doctor_skip_credential_checks "env file missing"
        return 0
    fi

    local env_file
    env_file="$(resolve_env_file)"
    if [[ -n "${env_file}" ]]; then
        _doctor_record env_file ok "${env_file}"
    else
        _doctor_record env_file warn "no env file, configuration from the environment only (create one with: cp .env.example .env)"
    fi

    if ! has_api_credentials; then
        _doctor_record credentials fail "CLOCKODO_API_USER and CLOCKODO_API_KEY must be set"
        _doctor_skip_credential_checks "credentials missing"
        return 0
    fi
    _doctor_record credentials ok "CLOCKODO_API_USER and CLOCKODO_API_KEY are set"

    export_derived_configuration
    _doctor_record api_url ok "${CLOCKODO_API_URL}"
    _doctor_check_api_access
}

# _doctor_skip_credential_checks
#   Records the checks that need credentials as skipped.
#   args:  $1 = reason
_doctor_skip_credential_checks() {
    _doctor_record credentials skip "$1"
    _doctor_record api_access skip "$1"
}

# _doctor_check_api_access
#   One GET /v4/users/me, uncached. The response body is discarded on
#   purpose (personal data); lib/http.sh's own error output is suppressed,
#   as the check reports the outcome itself.
_doctor_check_api_access() {
    # `|| true`: a failed request is an expected outcome here, not an abort.
    clockodo_api_get /v4/users/me >/dev/null 2>&1 || true

    local status
    status="$(clockodo_last_status)"
    case "${status}" in
        0)
            _doctor_record api_access fail "API not reachable: $(clockodo_last_body)"
            ;;
        401|403)
            _doctor_record api_access fail "credentials rejected (HTTP ${status}), check CLOCKODO_API_USER and CLOCKODO_API_KEY"
            ;;
        *)
            if [[ "${status}" =~ ^[0-9]+$ ]] && (( status < 400 )) && jq empty <<<"$(clockodo_last_body)" 2>/dev/null; then
                _doctor_record api_access ok "credentials accepted (HTTP ${status})"
            else
                _doctor_record api_access fail "unexpected API response (HTTP ${status:-unknown}), check CLOCKODO_API_URL"
            fi
            ;;
    esac
}

# _doctor_check_cache
#   With CACHE=1: the cache directory of this account must be writable (it
#   is created on the first write, so an existing parent is enough).
_doctor_check_cache() {
    if ! is_cache_enabled; then
        _doctor_record cache skip "disabled (enable with CACHE=1)"
        return 0
    fi
    if ! has_api_credentials; then
        _doctor_record cache skip "credentials missing (the cache directory depends on the account)"
        return 0
    fi

    local cache_directory writable_directory
    cache_directory="$(_cache_dir)"
    writable_directory="$(_doctor_nearest_existing_directory "${cache_directory}")"
    if [[ -w "${writable_directory}" ]]; then
        _doctor_record cache ok "enabled, ${cache_directory}"
    else
        _doctor_record cache fail "enabled, but ${writable_directory} is not writable"
    fi
}

# _doctor_nearest_existing_directory
#   Walks up from a path to the first directory that exists.
#   args:    $1 = path
#   stdout:  existing directory
_doctor_nearest_existing_directory() {
    local directory="$1"
    while [[ ! -d "${directory}" && "${directory}" != "/" ]]; do
        directory="$(dirname "${directory}")"
    done
    printf '%s' "${directory}"
}

# _doctor_check_read_only_mode
#   Informational: whether write requests are refused.
_doctor_check_read_only_mode() {
    if is_read_only_mode; then
        _doctor_record read_only ok "on, write requests are refused"
    else
        _doctor_record read_only ok "off (enable with CLOCKODO_READ_ONLY=1)"
    fi
}

# _doctor_has_failures
#   exit:  0 if at least one check failed, 1 otherwise
_doctor_has_failures() {
    printf '%s\n' "${DOCTOR_CHECK_RESULTS[@]}" | jq -se 'any(.status == "fail")' >/dev/null
}

# _doctor_render_results
#   stdout:  "<status>  <name>  <message>" lines (in check order, the order
#            of dependencies), or the JSON envelope {healthy, checks}
_doctor_render_results() {
    # `-s` slurps the one-object-per-line results into an array.
    local checks
    checks="$(printf '%s\n' "${DOCTOR_CHECK_RESULTS[@]}" | jq -s '.')"

    if is_json_output_mode; then
        emit_json_success "$(jq '{healthy:(any(.status == "fail") | not), checks:.}' <<<"${checks}")"
        return 0
    fi

    # `%-5s` / `%-12s` pad status and name to fixed-width columns.
    jq -r '.[] | [.status, .name, .message] | @tsv' <<<"${checks}" \
        | while IFS=$'\t' read -r status name message; do
            printf '%-5s %-12s %s\n' "${status}" "${name}" "${message}"
        done
}

# _doctor_version_at_least
#   Compares two dotted versions numerically (missing parts count as 0).
#   args:  $1 = actual version, $2 = required version
#   exit:  0 if actual >= required, 1 otherwise (also for unparsable input)
_doctor_version_at_least() {
    local actual_parts required_parts index
    # `IFS=.` splits on dots for this `read` only; `-a` fills an array.
    IFS=. read -r -a actual_parts <<<"$1"
    IFS=. read -r -a required_parts <<<"$2"

    for index in 0 1 2; do
        local actual="${actual_parts[index]:-0}" required="${required_parts[index]:-0}"
        [[ "${actual}" =~ ^[0-9]+$ ]] || return 1
        # `10#` forces base 10, so parts like "08" are not read as octal.
        (( 10#${actual} > 10#${required} )) && return 0
        (( 10#${actual} < 10#${required} )) && return 1
    done
    return 0
}
