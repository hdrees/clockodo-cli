#!/usr/bin/env bash
# =============================================================================
# lib/helper.sh — Shared helpers used across command scripts.
#
# Sourced by the entry script (clockodo) before any command file, so every
# action can rely on these helpers being in scope.
# =============================================================================

set -euo pipefail

# Global flag set by parse_global_flags when --json is passed on the CLI.
# Defaults to 0 (text mode). Exported so child processes (sourced files,
# subshells in command substitutions) inherit the value.
export CLOCKODO_JSON_OUTPUT="${CLOCKODO_JSON_OUTPUT:-0}"

# is_help_arg
#   Returns 0 if the given argument is a help flag (`--help` or `-h`).
#   args:  $1 = the value to test (pass empty string when no arg was given)
#   exit:  0 if it is a help flag, 1 otherwise
is_help_arg() {
    [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]
}

# has_help_arg
#   Returns 0 if any of the given arguments is a help flag, regardless of its
#   position (e.g. `customers list --state all --help`).
#   args:  $@ = the action's arguments
#   exit:  0 if a help flag is present, 1 otherwise
has_help_arg() {
    local argument
    for argument in "$@"; do
        is_help_arg "${argument}" && return 0
    done
    return 1
}

# is_json_output_mode
#   Returns 0 when the global --json flag was passed.
is_json_output_mode() {
    [[ "${CLOCKODO_JSON_OUTPUT}" == "1" ]]
}

# Global flag set by the entry script when --curl is passed on the CLI:
# requests are printed as curl commands instead of being sent.
export CLOCKODO_CURL_OUTPUT="${CLOCKODO_CURL_OUTPUT:-0}"

# is_curl_output_mode
#   Returns 0 when the global --curl flag was passed.
is_curl_output_mode() {
    [[ "${CLOCKODO_CURL_OUTPUT}" == "1" ]]
}

# Global flag set by the entry script when --dry-run is passed on the CLI:
# write requests (POST, DELETE, …) are reported instead of being sent,
# read requests (lookups) still run.
export CLOCKODO_DRY_RUN="${CLOCKODO_DRY_RUN:-0}"

# is_dry_run_mode
#   Returns 0 when the global --dry-run flag was passed.
is_dry_run_mode() {
    [[ "${CLOCKODO_DRY_RUN}" == "1" ]]
}

# is_read_only_mode
#   Returns 0 when CLOCKODO_READ_ONLY=1 (environment or .env): lib/http.sh
#   then refuses every write request. Read lazily, because .env is loaded
#   after this file is sourced.
is_read_only_mode() {
    [[ "${CLOCKODO_READ_ONLY:-0}" == "1" ]]
}

# is_debug_enabled
#   Returns 0 when the DEBUG=1 dump (lib/http.sh, lib/cache.sh) is active.
#   Always off in --json mode, which must not write anything to stderr.
is_debug_enabled() {
    [[ "${DEBUG:-0}" == "1" ]] && ! is_json_output_mode
}

# emit_argument_error
#   Reports an invalid or missing CLI argument: a failure envelope in --json
#   mode, otherwise "Error: <message>" on stderr.
#   args:  $1 = message, $2 = code (optional, default "invalid_argument")
emit_argument_error() {
    local message="$1"
    local code="${2:-invalid_argument}"
    if is_json_output_mode; then
        emit_json_failure "${message}" "${code}"
    else
        echo "Error: ${message}" >&2
    fi
}

# validate_numeric_id
#   Checks a required numeric ID argument and reports a missing or invalid
#   value via emit_argument_error.
#   args:  $1 = label used in the message (e.g. "customer"), $2 = the value
#   exit:  0 if the value is a non-empty number, 1 (error reported) otherwise
validate_numeric_id() {
    local label="$1" value="${2:-}"
    if [[ -z "${value}" ]]; then
        emit_argument_error "${label} ID is required" "missing_argument"
        return 1
    fi
    if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
        emit_argument_error "${label} ID must be numeric (got: ${value})"
        return 1
    fi
}

# emit_api_failure
#   Reports the most recent failed API request (see clockodo_last_status /
#   clockodo_last_body in lib/http.sh). In text mode it does nothing, because
#   lib/http.sh has already written the error to stderr. In --json mode it
#   prints the failure envelope:
#     status >= 400 → code `http_<status>` with `http_status` and `body`;
#     status 0      → code `network_error` (no HTTP response at all), the
#                     curl error text becomes the message;
#     `read_only`   → code `read_only` (write refused by CLOCKODO_READ_ONLY,
#                     the body holds "<method> <path>");
#     otherwise     → code `invalid_response` (e.g. a non-JSON 200 reply).
#   `http_status` and `body` are only part of real API errors.
emit_api_failure() {
    is_json_output_mode || return 0

    local last_status last_body
    last_status="$(clockodo_last_status)"
    last_body="$(clockodo_last_body)"

    # A --curl or --dry-run stop is no failure; the CLI is about to exit 0.
    [[ "${last_status}" == "dry_run" ]] && return 0

    if [[ "${last_status}" =~ ^[0-9]+$ ]] && (( last_status >= 400 )); then
        emit_json_failure "API request failed" "http_${last_status}" "${last_status}" "${last_body}"
    elif [[ "${last_status}" == "0" ]]; then
        emit_json_failure "request failed: ${last_body:-no response}" "network_error"
    elif [[ "${last_status}" == "read_only" ]]; then
        emit_json_failure "read-only mode (CLOCKODO_READ_ONLY=1): refused ${last_body}" "read_only"
    else
        emit_json_failure "unexpected API response (HTTP ${last_status:-unknown})" "invalid_response"
    fi
}

# emit_json_success
#   Prints a success envelope: {"status":"success","data":<data>}.
#   args:    $1 = JSON string for the `data` field
#   stdout:  envelope
#
#   The data is fed to jq via stdin, not via `--argjson`: command-line
#   arguments are limited in size (~128 KiB per argument on Linux), which
#   large lists exceed ("Argument list too long").
emit_json_success() {
    local data="${1:-null}"
    jq '{status:"success", data:.}' <<<"${data}"
}

# emit_json_data
#   Convenience wrapper around emit_json_success for the common case where
#   the Clockodo API wraps its payload in a top-level `data` field. Unwraps
#   that field so our envelope does not double-nest:
#
#       API response:  { "data": [...]   }    → envelope: { ..., "data": [...] }
#       API response:  { "data": {...id} }    → envelope: { ..., "data": {...id} }
#
#   args:    $1 = raw API response (a JSON string with a top-level .data)
emit_json_data() {
    local response="${1:-null}"
    emit_json_success "$(echo "${response}" | jq '.data')"
}

# emit_json_failure
#   Prints a failure envelope on stdout.
#   args:
#     $1 message     — human-readable error message (required)
#     $2 code        — short machine code (optional, e.g. "invalid_argument")
#     $3 http_status — HTTP status code (optional, only for API errors)
#     $4 body        — raw API response as JSON string (optional)
#
#   Optional fields are omitted from the envelope when not provided.
emit_json_failure() {
    local message="${1:-Unknown error}"
    local code="${2:-}"
    local http_status="${3:-}"
    local body="${4:-}"

    # Build the error object incrementally with jq so missing fields are
    # cleanly omitted rather than set to null.
    local error_json
    error_json="$(jq -n --arg message "${message}" '{message:$message}')"

    if [[ -n "${code}" ]]; then
        error_json="$(echo "${error_json}" | jq --arg code "${code}" '. + {code:$code}')"
    fi
    # Only forward http_status when it is a positive integer — `jq --argjson`
    # would otherwise fail on empty strings or non-numeric values, and 0 is
    # not an HTTP status.
    if [[ "${http_status}" =~ ^[1-9][0-9]*$ ]]; then
        error_json="$(echo "${error_json}" | jq --argjson http_status "${http_status}" '. + {http_status:$http_status}')"
    fi
    # The body may be large, so it goes through stdin (see emit_json_success);
    # the small error object is passed as argument. JSON bodies are embedded
    # as JSON, anything else as string (`-R` raw input, `-s` as one string).
    if [[ -n "${body}" ]]; then
        if jq empty <<<"${body}" 2>/dev/null; then
            error_json="$(jq --argjson error "${error_json}" '$error + {body:.}' <<<"${body}")"
        else
            error_json="$(printf '%s' "${body}" | jq -Rs --argjson error "${error_json}" '$error + {body:.}')"
        fi
    fi

    jq -n --argjson error "${error_json}" '{status:"failure", data:null, error:$error}'
}
