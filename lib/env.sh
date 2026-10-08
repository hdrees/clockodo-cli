#!/usr/bin/env bash
# =============================================================================
# lib/env.sh — Loads the configuration and validates mandatory vars.
#
# Sources, highest priority first:
#   1. Environment variables (also set on the command line).
#   2. The env file: CLOCKODO_ENV_FILE if set, otherwise `.env` in the repo
#      root. The repo `.env` is optional when the mandatory variables come
#      from the environment (e.g. when another tool calls this CLI).
#
# Exports after load_env:
#   CLOCKODO_API_USER      (mandatory)
#   CLOCKODO_API_KEY       (mandatory)
#   CLOCKODO_API_URL       (default: https://my.clockodo.com/api)
#   CLOCKODO_EXTERNAL_APP  (header value; CLOCKODO_EXTERNAL_APPLICATION
#                           overrides the generated default)
#
# Prerequisites: lib/helper.sh is sourced; CLOCKODO_CLI_VERSION must be
# exported by the entry script.
# =============================================================================

set -euo pipefail

# _fail_configuration
#   Reports a configuration error (envelope in --json mode, stderr
#   otherwise) and ends the CLI.
#   args:  $1 = message
#   exit:  always 1
_fail_configuration() {
    emit_argument_error "$1" "configuration_error"
    exit 1
}

# resolve_env_file
#   Prints the env file to read, or nothing when there is none:
#   CLOCKODO_ENV_FILE if set (existence is checked by load_env, because this
#   runs inside `$(…)`), otherwise the repo `.env` if it exists.
resolve_env_file() {
    if [[ -n "${CLOCKODO_ENV_FILE:-}" ]]; then
        printf '%s' "${CLOCKODO_ENV_FILE}"
        return 0
    fi
    # Resolve the repo root relative to THIS file (lib/ → ..).
    # Works regardless of the directory from which the entry script was run.
    local repo_env_file
    repo_env_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"
    [[ -f "${repo_env_file}" ]] && printf '%s' "${repo_env_file}"
    return 0
}

# _read_env_file
#   Exports every KEY=value line of the file whose variable is not set yet.
#   Parsed manually so environment variables win over the file. Using
#   `set -a; source .env` would unconditionally clobber `DEBUG=1 ./clockodo …`
#   whenever .env contains `DEBUG=0` (and similar for `CACHE`, etc.). We
#   treat the file as defaults, not as overrides.
#   args:  $1 = env file
_read_env_file() {
    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Skip comment lines and blank lines.
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Split on the first `=` — values may contain further `=` chars.
        key="${line%%=*}"
        value="${line#*=}"
        # Trim surrounding whitespace from the key.
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        # Strip optional surrounding quotes around the value.
        [[ "${value}" == \"*\" ]] && value="${value:1:${#value}-2}"
        [[ "${value}" == \'*\' ]] && value="${value:1:${#value}-2}"
        # Only set when the variable is not already set in the environment.
        # `${!key:-}` expands to the named variable's current value (or empty).
        if [[ -z "${!key:-}" ]]; then
            export "${key}=${value}"
        fi
    done < "$1"
}

# read_env_file_defaults
#   Reads the env file (see resolve_env_file) as defaults for variables not
#   yet set. Does not validate anything else, so `clockodo doctor` can
#   inspect an incomplete configuration.
#   exit:  0 on success, 1 if CLOCKODO_ENV_FILE points to a missing file
read_env_file_defaults() {
    if [[ -n "${CLOCKODO_ENV_FILE:-}" && ! -f "${CLOCKODO_ENV_FILE}" ]]; then
        return 1
    fi

    local env_file
    env_file="$(resolve_env_file)"
    if [[ -n "${env_file}" ]]; then
        _read_env_file "${env_file}"
    fi
}

# has_api_credentials
#   Returns 0 when both mandatory variables are set.
has_api_credentials() {
    [[ -n "${CLOCKODO_API_USER:-}" && -n "${CLOCKODO_API_KEY:-}" ]]
}

# load_env
#   Source of truth for configuration. Called by the entry script after all
#   libraries have been sourced.
#   stdout: failure envelope in --json mode
#   stderr: error message if mandatory variables are missing (text mode)
#   exit:   ends the CLI with 1 on a configuration error
load_env() {
    : "${CLOCKODO_CLI_VERSION:?Error: CLOCKODO_CLI_VERSION not set (must be exported by the entry script)}"

    if ! read_env_file_defaults; then
        _fail_configuration "CLOCKODO_ENV_FILE not found: ${CLOCKODO_ENV_FILE}"
    fi

    if ! has_api_credentials; then
        _fail_configuration "CLOCKODO_API_USER and CLOCKODO_API_KEY must be set (environment or .env; create one with: cp .env.example .env)"
    fi

    export_derived_configuration
}

# export_derived_configuration
#   Exports the values derived from the mandatory variables: the API URL
#   default and the X-Clockodo-External-Application header value.
export_derived_configuration() {
    # Default API URL unless overridden.
    # `${VAR:-default}` returns default when VAR is empty/unset.
    export CLOCKODO_API_URL="${CLOCKODO_API_URL:-https://my.clockodo.com/api}"

    # Mandatory "external application" header. Format per Clockodo spec:
    # "<appname>;<email>". By default generated with the CLI version in the
    # appname so Clockodo can identify our calls in their logs; a calling
    # tool can pass its own value via CLOCKODO_EXTERNAL_APPLICATION.
    export CLOCKODO_EXTERNAL_APP="${CLOCKODO_EXTERNAL_APPLICATION:-clockodo-cli/${CLOCKODO_CLI_VERSION};${CLOCKODO_API_USER}}"
}
