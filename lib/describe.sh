#!/usr/bin/env bash
# =============================================================================
# lib/describe.sh — `clockodo describe [<group> [<action>]]`: machine-readable
# contracts of the commands, for agents and scripts.
#
# The contracts are static JSON files next to the code they describe:
#   lib/contract.json               root contract: global flags, environment,
#                                   envelope, error codes, top-level commands
#   commands/<group>/contract.json  {summary, actions: {<action>: {...}}}
#
# An action contract has: summary, usage, arguments [{name, type, required,
# description}], options [{name, value?, default?, description}], writes,
# interactive, requests, curl (supported | partial | unsupported), notes?,
# data (shape of the --json data), error_codes.
#
# A top-level command, dispatched by the entry script before .env is loaded;
# it sends no requests.
#
# Dependencies: lib/helper.sh, jq. Requires REPO_ROOT.
# =============================================================================

set -euo pipefail

# print_describe_help
#   Help text for `clockodo describe`.
print_describe_help() {
    cat <<'EOF'
clockodo describe — machine-readable command contracts

Usage:
  clockodo describe [--json]
  clockodo describe <group> [--json]
  clockodo describe <group> <action> [--json]
  clockodo describe <command> [--json]

Without arguments: groups, top-level commands, global flags and error
codes. With a group: its actions. With an action or a top-level command
(describe, doctor, upgrade, version): arguments, options, whether it
writes, the API requests it sends, --curl support, the shape of the --json
data and its error codes.

Text mode prints a readable summary; --json returns the full contract.
Sends no requests, so --curl is not supported.

Examples:
  clockodo describe
  clockodo describe entries
  clockodo describe entries stop --json
EOF
}

# cmd_describe
#   Resolves the requested contract and renders it.
#   args:    $1 = optional group or top-level command, $2 = optional action
#   stdout:  readable summary, or the JSON envelope in --json mode
#   exit:    0 on success, 1 on unknown group/action or invalid arguments
cmd_describe() {
    if has_help_arg "$@"; then
        print_describe_help
        return 0
    fi
    if is_curl_output_mode; then
        emit_argument_error "describe sends no API requests; --curl is not supported"
        return 1
    fi
    if (( $# > 2 )); then
        emit_argument_error "too many arguments: $*"
        return 1
    fi

    local group="${1:-}" action="${2:-}"

    if [[ -z "${group}" ]]; then
        _describe_render root "$(_describe_root_contract)"
        return 0
    fi

    if _describe_is_top_level_command "${group}"; then
        if [[ -n "${action}" ]]; then
            emit_argument_error "'${group}' has no actions" "unknown_command"
            return 1
        fi
        _describe_render action "$(_describe_top_level_command_contract "${group}")"
        return 0
    fi

    local group_contract_file="${REPO_ROOT}/commands/${group}/contract.json"
    if [[ ! -f "${group_contract_file}" ]]; then
        emit_argument_error "unknown group: ${group}" "unknown_command"
        return 1
    fi

    if [[ -z "${action}" ]]; then
        _describe_render group "$(jq --arg group "${group}" '{group:$group} + .' "${group_contract_file}")"
        return 0
    fi

    if ! jq -e --arg action "${action}" '.actions | has($action)' "${group_contract_file}" >/dev/null; then
        emit_argument_error "unknown command: ${group} ${action}" "unknown_command"
        return 1
    fi
    _describe_render action "$(jq --arg group "${group}" --arg action "${action}" \
        '{command:"clockodo \($group) \($action)", group:$group, action:$action} + .actions[$action]' \
        "${group_contract_file}")"
}

# _describe_root_contract
#   The root contract plus a `groups` list built from every group contract,
#   sorted by group name.
#   stdout:  JSON object
_describe_root_contract() {
    local contract_file groups_json="[]"
    # The glob expands in alphabetical order, so the groups come out sorted.
    for contract_file in "${REPO_ROOT}"/commands/*/contract.json; do
        [[ -f "${contract_file}" ]] || continue
        groups_json="$(jq --arg name "$(basename "$(dirname "${contract_file}")")" \
            --argjson groups "${groups_json}" \
            '$groups + [{name:$name, summary:.summary, actions:(.actions | keys)}]' "${contract_file}")"
    done
    jq --argjson groups "${groups_json}" '. + {groups:$groups}' "${REPO_ROOT}/lib/contract.json"
}

# _describe_is_top_level_command
#   args:  $1 = name
#   exit:  0 if the name is a top-level command of the root contract
_describe_is_top_level_command() {
    jq -e --arg name "$1" '.commands | has($name)' "${REPO_ROOT}/lib/contract.json" >/dev/null
}

# _describe_top_level_command_contract
#   args:    $1 = top-level command name
#   stdout:  its contract as JSON object, with `command` prepended
_describe_top_level_command_contract() {
    jq --arg name "$1" '{command:"clockodo \($name)"} + .commands[$name]' "${REPO_ROOT}/lib/contract.json"
}

# _describe_render
#   Prints a contract: as envelope in --json mode, otherwise as readable
#   summary of the given kind.
#   args:  $1 = root | group | action, $2 = contract JSON
_describe_render() {
    local kind="$1" contract="$2"

    if is_json_output_mode; then
        emit_json_success "${contract}"
        return 0
    fi

    case "${kind}" in
        root)   jq -r "$(_describe_root_text_filter)" <<<"${contract}" ;;
        group)  jq -r "$(_describe_group_text_filter)" <<<"${contract}" ;;
        action) jq -r "$(_describe_action_text_filter)" <<<"${contract}" ;;
    esac
}

# _describe_root_text_filter
#   stdout:  jq filter rendering the root contract as text. `pad` fills a
#            value with spaces to a column width (at least one space).
_describe_root_text_filter() {
    cat <<'JQ'
def pad($width): . + (" " * ([$width - length, 1] | max));
"\(.cli) — \(.summary)",
"",
"Groups:",
(.groups[] | "  \(.name | pad(13))\(.actions | join(", ") | pad(30))\(.summary)"),
"",
"Commands:",
(.commands | to_entries[] | "  \(.key | pad(13))\(.value.summary)"),
"",
"Global flags:",
(.global_flags[] | "  \(.name | pad(13))\(.description)"),
"",
"Run `clockodo describe <group> [<action>]` for details; add --json for the full contract."
JQ
}

# _describe_group_text_filter
#   stdout:  jq filter rendering a group contract as text.
_describe_group_text_filter() {
    cat <<'JQ'
"\(.group) — \(.summary)",
"",
(.actions | to_entries[] | "  \(.value.usage)\(if .value.writes then "   [writes]" else "" end)\n      \(.value.summary)")
JQ
}

# _describe_action_text_filter
#   stdout:  jq filter rendering an action (or top-level command) contract
#            as text. Empty sections are left out.
_describe_action_text_filter() {
    cat <<'JQ'
def yes_no: if . then "yes" else "no" end;
.usage,
"  \(.summary)",
"",
(if (.arguments | length) > 0 then
    "Arguments:",
    (.arguments[] | "  \(.name) (\(.type), \(if .required then "required" else "optional" end))  \(.description)"),
    ""
 else empty end),
(if (.options | length) > 0 then
    "Options:",
    (.options[] | "  \(.name)\(if .value then " <\(.value)>" else "" end)\(if .default then " (default: \(.default))" else "" end)  \(.description)"),
    ""
 else empty end),
"Writes:       \(.writes | yes_no)",
"Interactive:  \(.interactive | yes_no)",
"Requests:     \(.requests)",
"--curl:       \(.curl)",
(.notes // [] | .[] | "Note:         \(.)"),
"JSON data:    \(.data)",
(if (.error_codes | length) > 0 then "Error codes:  \(.error_codes | join(", "))" else empty end)
JQ
}
