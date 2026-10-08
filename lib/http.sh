#!/usr/bin/env bash
# =============================================================================
# lib/http.sh — Central curl wrappers for the Clockodo API.
#
# The only place where curl is invoked. Automatically sets the three
# mandatory headers (User, ApiKey, External-Application), checks the HTTP
# status, and writes the raw response body to stdout.
#
# Public API:
#   clockodo_api_get  <path>            -> response body on stdout
#   clockodo_api_post <path> [body]     -> response body on stdout
#   clockodo_api_delete <path>          -> response body on stdout
#   http_get_public <url>               -> body of a non-Clockodo URL, no auth
#
# Enable debug output by setting DEBUG=1 (see README.md, "Debug output").
# With the global --curl flag, requests are printed as curl commands instead
# of being sent (see `_print_curl_command_and_stop`). With --dry-run, write
# requests are reported instead of being sent (`_print_dry_run_and_stop`);
# with CLOCKODO_READ_ONLY=1 they are refused (`_reject_write_in_read_only_mode`).
#
# Prerequisites: lib/helper.sh is sourced; load_env has been called before
# the first request (CLOCKODO_API_USER, _API_KEY, _API_URL, _EXTERNAL_APP must
# be exported).
# =============================================================================

set -euo pipefail

# Private per-process directory (mode 0700, created by mktemp -d) for the
# state file and curl's error output. Created once in the main shell so
# every `$(…)` subshell shares it.
if ! CLOCKODO_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clockodo-cli.XXXXXX" 2>/dev/null)"; then
    if is_json_output_mode; then
        emit_json_failure "cannot create a temporary directory in ${TMPDIR:-/tmp}" "internal_error"
    else
        echo "Error: cannot create a temporary directory in ${TMPDIR:-/tmp} (check TMPDIR)" >&2
    fi
    exit 1
fi

# State file written by _clockodo_request after every call. We cannot use
# shell variables here because action scripts typically invoke the wrappers
# inside `$(…)` — that runs in a subshell, and any global set there is lost
# when the subshell exits. A file persists across the subshell boundary.
#
# Layout: first line = HTTP status (0 = no HTTP response, `dry_run` = --curl
# or --dry-run printed the request instead of sending it, `read_only` = write
# refused by CLOCKODO_READ_ONLY); everything from the second line onwards =
# response body (curl's error text for 0, "<method> <path>" for read_only).
# Consumers should use `clockodo_last_status` / `clockodo_last_body` rather
# than parsing the file directly.
CLOCKODO_HTTP_STATE_FILE="${CLOCKODO_RUNTIME_DIR}/http-state"

# curl's stderr of the most recent request (overwritten by every request).
CLOCKODO_CURL_ERROR_FILE="${CLOCKODO_RUNTIME_DIR}/curl-error"

# Request body of the most recent request. Passed to curl as a file, so the
# body (which may contain personal data) does not show up in the process
# list (`ps`, /proc/<pid>/cmdline).
CLOCKODO_REQUEST_BODY_FILE="${CLOCKODO_RUNTIME_DIR}/request-body"

# Cleanup on every exit. Bash runs no EXIT trap when killed by INT/TERM, so
# those are turned into regular exits (128 + signal number) first.
trap 'rm -rf "${CLOCKODO_RUNTIME_DIR}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# clockodo_last_status
#   Prints the HTTP status of the most recent API call, or empty if no call
#   was made yet in this process.
clockodo_last_status() {
    [[ -f "${CLOCKODO_HTTP_STATE_FILE}" ]] || return 0
    head -n 1 "${CLOCKODO_HTTP_STATE_FILE}"
}

# clockodo_last_body
#   Prints the raw response body of the most recent API call.
clockodo_last_body() {
    [[ -f "${CLOCKODO_HTTP_STATE_FILE}" ]] || return 0
    tail -n +2 "${CLOCKODO_HTTP_STATE_FILE}"
}

# _clockodo_record_response
#   Persists status + body to the state file so callers can read them even
#   when the request ran inside a `$(…)` subshell.
#   args:  $1 = HTTP status (0 = no HTTP response), $2 = body
_clockodo_record_response() {
    {
        printf '%s\n' "$1"
        printf '%s' "$2"
    } > "${CLOCKODO_HTTP_STATE_FILE}"
}

# _clockodo_request_headers
#   Prints the request headers, one per line — the single source for the
#   real request, the --curl output and the DEBUG dump.
#   args:    $1 = request body (a Content-Type header is added when non-empty)
#   stdout:  "Name: value" lines
_clockodo_request_headers() {
    local body="${1:-}"
    printf '%s\n' \
        "X-ClockodoApiUser: ${CLOCKODO_API_USER}" \
        "X-ClockodoApiKey: ${CLOCKODO_API_KEY}" \
        "X-Clockodo-External-Application: ${CLOCKODO_EXTERNAL_APP}" \
        "Accept: application/json"
    if [[ -n "${body}" ]]; then
        printf '%s\n' "Content-Type: application/json"
    fi
}

# _shell_quote
#   Wraps a value in single quotes for safe copy & paste into a shell.
#   Embedded single quotes become `'\''` (close quote, escaped quote, reopen).
#   args:    $1 = raw value
#   stdout:  quoted value
_shell_quote() {
    local value="$1"
    local escaped_quote="'\\''"
    printf "'%s'" "${value//\'/${escaped_quote}}"
}

# _stop_without_sending
#   --curl / --dry-run mode: ends the whole CLI with exit 0 after the request
#   was printed instead of sent. Must run in the function that printed it,
#   often inside `$(…)`:
#     - records the stop in the state file (status `dry_run`), so
#       emit_api_failure stays silent should it run before the trap;
#     - signals the main shell via USR1 — `$$` is the main shell's PID even
#       inside `$(…)`; its trap (entry script) exits 0;
#     - exits this subshell with 1, so every caller in between takes its
#       failure path (no further pages, no cache write, no rendering of an
#       empty "success") instead of running on until the trap fires.
#   exit:    does not return
_stop_without_sending() {
    _clockodo_record_response dry_run ""
    kill -USR1 "$$"
    exit 1
}

# _print_curl_command_and_stop
#   --curl mode: prints the curl command equivalent to the request that
#   _clockodo_request would send, then ends the whole CLI with exit 0
#   without sending anything (see _stop_without_sending). Uses the real
#   credentials (copy & paste runnable — the output contains the API key in
#   clear text).
#
#   Writes to fd 3 (the terminal's stdout, opened by the entry script),
#   because this usually runs inside a `$(…)` subshell whose stdout is
#   captured (see the entry script).
#
#   args:    $1 = method, $2 = full URL, $3 = headers (one per line),
#            $4 = optional JSON body
#   stdout:  nothing (output goes to fd 3)
#   exit:    does not return
_print_curl_command_and_stop() {
    local method="$1" url="$2" headers="$3" body="${4:-}"

    local lines=("curl --silent")
    [[ "${method}" != "GET" ]] && lines+=("--request ${method}")
    local header
    while IFS= read -r header; do
        lines+=("--header $(_shell_quote "${header}")")
    done <<<"${headers}"
    [[ -n "${body}" ]] && lines+=("--data $(_shell_quote "${body}")")
    lines+=("$(_shell_quote "${url}")")

    # First line flush left, continuation lines indented; every line ends
    # with ` \`, the result is piped into `jq .` like the README.
    local index
    {
        for index in "${!lines[@]}"; do
            (( index > 0 )) && printf '  '
            printf '%s \\\n' "${lines[${index}]}"
        done
        printf '  | jq .\n'
    } >&3

    _stop_without_sending
}

# _print_dry_run_and_stop
#   --dry-run mode: reports the write request that _clockodo_request would
#   send, then ends the whole CLI with exit 0 without sending anything (see
#   _stop_without_sending). Unlike --curl it shows no headers, so the output
#   holds no credentials.
#
#   Writes to fd 3 like _print_curl_command_and_stop (see there).
#
#   args:    $1 = method, $2 = full URL, $3 = optional JSON body
#   stdout:  nothing (output goes to fd 3): a text block, or in --json mode
#            the envelope {dry_run:true, request:{method, url, body}}; a
#            non-JSON body is passed as string, a missing one as null
#   exit:    does not return
_print_dry_run_and_stop() {
    local method="$1" url="$2" body="${3:-}"

    if is_json_output_mode; then
        # `try fromjson catch .` embeds a JSON body as JSON and anything else
        # as string; `-R` reads the body raw, `-s` as one string.
        local request
        request="$(printf '%s' "${body}" | jq -Rs --arg method "${method}" --arg url "${url}" \
            '{method:$method, url:$url, body:(if . == "" then null else (try fromjson catch .) end)}')"
        emit_json_success "$(jq '{dry_run:true, request:.}' <<<"${request}")" >&3
    else
        {
            echo "Dry run, nothing was sent:"
            echo "  ${method} ${url}"
            if [[ -n "${body}" ]]; then
                echo "  Body: ${body}"
            fi
        } >&3
    fi

    _stop_without_sending
}

# _reject_write_in_read_only_mode
#   CLOCKODO_READ_ONLY=1: records the refused write request in the state
#   file (status `read_only`, body "<method> <path>"; see emit_api_failure)
#   and writes a human-readable error to stderr in text mode.
#   args:    $1 = method, $2 = path
#   stdout:  nothing
_reject_write_in_read_only_mode() {
    local method="$1" path="$2"

    _clockodo_record_response read_only "${method} ${path}"

    if ! is_json_output_mode; then
        echo "Error: read-only mode (CLOCKODO_READ_ONLY=1): refused ${method} ${path}" >&2
    fi
}

# _print_debug_request
#   DEBUG=1: request dump on stderr. The API key is masked to its first
#   4 characters so screenshots/logs cannot accidentally leak it
#   (see CLAUDE.md — masking must not be removed).
#   args:  $1 = method, $2 = full URL, $3 = headers (one per line), $4 = body
_print_debug_request() {
    local method="$1" url="$2" headers="$3" body="${4:-}"
    local header
    # Block redirect: all output inside the {…} group goes to stderr.
    {
        echo "── REQUEST ──────────────────────────────"
        echo "${method} ${url}"
        while IFS= read -r header; do
            if [[ "${header}" == "X-ClockodoApiKey: "* ]]; then
                # ${VAR:0:4} = substring, offset 0, length 4.
                header="X-ClockodoApiKey: ${CLOCKODO_API_KEY:0:4}***"
            fi
            echo "${header}"
        done <<<"${headers}"
        if [[ -n "${body}" ]]; then
            echo "Body:"
            # jq pretty-prints; fall back to the raw body if it is not JSON.
            echo "${body}" | jq . 2>/dev/null || echo "${body}"
        fi
    } >&2
}

# _print_debug_response
#   DEBUG=1: response dump on stderr.
#   args:  $1 = HTTP status, $2 = body
_print_debug_response() {
    local status="$1" response="$2"
    {
        echo "── RESPONSE ─────────────────────────────"
        echo "HTTP ${status}"
        if [[ -n "${response}" ]]; then
            echo "${response}" | jq . 2>/dev/null || echo "${response}"
        fi
        echo "─────────────────────────────────────────"
    } >&2
}

# _clockodo_handle_transport_failure
#   Internal: records a request that got no HTTP response (curl failed) in
#   the state file — status 0, body = curl's error text — and writes a
#   human-readable error to stderr in text mode.
#   args:    $1 = method, $2 = path, $3 = curl exit code, $4 = curl error text
#   stdout:  nothing
_clockodo_handle_transport_failure() {
    local method="$1" path="$2" curl_exit="$3" curl_error="$4"
    local message="${curl_error:-curl exit code ${curl_exit}}"

    _clockodo_record_response 0 "${message}"

    if ! is_json_output_mode; then
        echo "Error: request failed on ${method} ${path}: ${message}" >&2
    fi
}

# _clockodo_request
#   Internal helper. Performs the curl call, handles status + debug output.
#
#   Args:
#     $1 method  — HTTP method (GET, POST, ...)
#     $2 path    — path relative to CLOCKODO_API_URL, e.g. "/v2/favorites"
#     $3 body    — optional JSON body (only relevant for POST/PUT/PATCH)
#
#   stdout: response body (raw, without status suffix)
#   stderr: request/response dump if DEBUG=1; error message on failure
#           (text mode only)
#   exit:   0 on HTTP < 400 with a JSON (or empty) body, otherwise 1
_clockodo_request() {
    local method="$1"
    local path="$2"
    # `${3:-}` → empty string when $3 is missing; required because of set -u.
    local body="${3:-}"

    local url="${CLOCKODO_API_URL}${path}"
    local headers
    headers="$(_clockodo_request_headers "${body}")"

    # Write guards apply to every method except GET. --dry-run comes first:
    # it sends nothing, so it is allowed in read-only mode too. --curl, in
    # contrast, hands out a runnable write command and is refused there.
    # (--curl and --dry-run never coincide; the entry script drops the
    # latter.)
    if [[ "${method}" != "GET" ]]; then
        if is_dry_run_mode; then
            _print_dry_run_and_stop "${method}" "${url}" "${body}"
        fi
        if is_read_only_mode; then
            _reject_write_in_read_only_mode "${method}" "${path}"
            return 1
        fi
    fi

    if is_curl_output_mode; then
        _print_curl_command_and_stop "${method}" "${url}" "${headers}" "${body}"
    fi

    if is_debug_enabled; then
        _print_debug_request "${method}" "${url}" "${headers}" "${body}"
    fi

    # curl arguments as an array so that values containing whitespace stay
    # properly quoted.
    #   --disable    must come first: ignore ~/.curlrc (e.g. `--fail` there
    #                would turn every HTTP error into a transport failure).
    #   --header @-  reads the headers from stdin, so the API key does not
    #                show up in the process list (`ps`, /proc/<pid>/cmdline).
    #   --write-out '\n%{http_code}' appends a newline plus the HTTP status
    #                after the body; we split them apart below.
    #   --data-binary @file  sends the body from the private runtime dir,
    #                byte for byte (plain `--data @file` would strip newlines).
    local curl_args=(
        --disable
        --silent
        --show-error
        --write-out '\n%{http_code}'
        --request "${method}"
        --header @-
    )
    if [[ -n "${body}" ]]; then
        printf '%s' "${body}" > "${CLOCKODO_REQUEST_BODY_FILE}"
        curl_args+=(--data-binary "@${CLOCKODO_REQUEST_BODY_FILE}")
    fi

    # curl's own error message (e.g. "Failed to connect") is captured
    # instead of printed, so --json mode keeps stderr silent. `|| curl_exit=$?`
    # records a failing exit code without triggering `set -e`.
    local response curl_exit=0
    response="$(curl "${curl_args[@]}" "${url}" <<<"${headers}" 2>"${CLOCKODO_CURL_ERROR_FILE}")" || curl_exit=$?

    # --- Transport failure (no HTTP response at all) -----------------------
    # Connection refused, DNS failure, timeout, … — curl still writes
    # `%{http_code}` as "000", which must not pass as success.
    if (( curl_exit != 0 )); then
        _clockodo_handle_transport_failure "${method}" "${path}" "${curl_exit}" "$(cat "${CLOCKODO_CURL_ERROR_FILE}")"
        return 1
    fi

    local status
    # `${var##*$'\n'}` = strip everything up to the last newline → status remains.
    status="${response##*$'\n'}"
    # `${var%$'\n'*}`  = strip from the last newline onwards → body remains.
    response="${response%$'\n'*}"

    if is_debug_enabled; then
        _print_debug_response "${status}" "${response}"
    fi

    _clockodo_record_response "${status}" "${response}"

    # --- HTTP status check -------------------------------------------------
    # 4xx/5xx → return 1. In text mode we also write a human-readable error
    # to stderr; in --json mode the caller assembles the failure envelope
    # via emit_api_failure, so stderr stays silent.
    if (( status >= 400 )); then
        if ! is_json_output_mode; then
            echo "Error: HTTP ${status} on ${method} ${path}" >&2
            if [[ -n "${response}" ]]; then
                echo "${response}" | jq . >&2 2>/dev/null || echo "${response}" >&2
            fi
        fi
        return 1
    fi

    # --- Response format check ---------------------------------------------
    # A success status with a non-JSON body (e.g. a proxy's HTML page) would
    # otherwise break every later jq call with cryptic errors. `jq empty`
    # validates without printing; an empty body (e.g. 204) is fine.
    if [[ -n "${response}" ]] && ! jq empty <<<"${response}" 2>/dev/null; then
        if ! is_json_output_mode; then
            echo "Error: unexpected non-JSON response (HTTP ${status}) on ${method} ${path}" >&2
        fi
        return 1
    fi

    # Success: print body raw. `echo` would append a newline; `printf '%s'`
    # leaves the body untouched.
    printf '%s' "${response}"
}

# GET convenience wrapper.
clockodo_api_get() {
    _clockodo_request GET "$1"
}

# POST convenience wrapper. Body optional (some Clockodo endpoints such as
# /v2/favorites/{id}/start accept an empty body).
clockodo_api_post() {
    _clockodo_request POST "$1" "${2:-}"
}

# DELETE convenience wrapper. The path may carry a query string (e.g.
# /v2/clock/{id}?users_id=…); DELETE requests are sent without a body.
clockodo_api_delete() {
    _clockodo_request DELETE "$1"
}

# http_get_public
#   Plain GET against a non-Clockodo URL (e.g. GitHub). Sends NO auth
#   headers — Clockodo credentials must never leave for third parties.
#   In --curl mode prints the equivalent curl command and stops the CLI.
#   args:    $1 = absolute URL
#   stdout:  response body on HTTP < 400
#   stderr:  nothing (callers word their own error message)
#   exit:    0 on success, 1 on transport failure or HTTP ≥ 400; status
#            (0 = no response) and body/curl error land in the state file
#            (see clockodo_last_status / clockodo_last_body).
http_get_public() {
    local url="$1"

    if is_curl_output_mode; then
        printf 'curl --silent --location %s\n' "$(_shell_quote "${url}")" >&3
        _stop_without_sending
    fi

    #   --disable    ignore ~/.curlrc (see _clockodo_request).
    #   --location   follow redirects (e.g. renamed repositories).
    #   --max-time   keeps an unreachable host from blocking the CLI.
    local response curl_exit=0
    response="$(curl --disable --silent --show-error --location --max-time 10 \
        --write-out '\n%{http_code}' "${url}" 2>"${CLOCKODO_CURL_ERROR_FILE}")" || curl_exit=$?

    if (( curl_exit != 0 )); then
        local curl_error
        curl_error="$(cat "${CLOCKODO_CURL_ERROR_FILE}")"
        _clockodo_record_response 0 "${curl_error:-curl exit code ${curl_exit}}"
        return 1
    fi

    # Same split as in _clockodo_request: status after the last newline.
    local status="${response##*$'\n'}"
    response="${response%$'\n'*}"
    _clockodo_record_response "${status}" "${response}"

    (( status < 400 )) || return 1
    printf '%s' "${response}"
}
