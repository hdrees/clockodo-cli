#!/usr/bin/env bash
# =============================================================================
# lib/usage.sh — Root help and group-help dispatcher.
#
# The per-group help texts live next to their commands:
#   commands/<group>/help.sh   defines   print_<group>_help
#
# Sourced by the entry script (clockodo). Requires REPO_ROOT to be set
# by the caller.
#
# Heredocs use 'EOF' in single quotes so bash performs NO variable expansion
# — we want the text printed verbatim.
# =============================================================================

set -euo pipefail

# print_root_help
#   Overview of all available command groups + examples.
print_root_help() {
    cat <<'EOF'
clockodo — CLI for the Clockodo API

Usage:
  clockodo <group> <action> [args...]
  clockodo --help | -h
  clockodo <group> --help

Groups:
  absences     List and get absences
  cache        List, delete, and clear local cache entries
  customers    List and get customers
  describe     Machine-readable contracts of all commands (for agents)
  doctor       Check tools, configuration and API access
  entries      List, get, summarize, and stop time entries
  favorites    List and start favorites
  projects     List and get projects
  services     List and get services
  subprojects  List and get subprojects
  targethours  List and get target hours
  upgrade      Update the CLI to the latest main branch (git fast-forward)
  users        List, get, and resolve the current user (me)
  version      Show the local and the published CLI version

Global flags:
  --curl     Print the equivalent curl command instead of sending the request
  --dry-run  Report write requests (start, stop) instead of sending them
  --json     Emit a machine-readable JSON envelope instead of text output

Environment:
  CACHE=1               Cache list endpoints on disk for 300s (default: off)
  CLOCKODO_READ_ONLY=1  Refuse every write request (default: off)
  DEBUG=1               Dump HTTP requests/responses and cache hits to stderr
                        (ignored with --json)

Examples:
  clockodo favorites list
  clockodo favorites list --json
  clockodo favorites start 12345

More docs: see README.md
EOF
}

# print_group_help
#   Loads the group's help file (commands/<group>/help.sh) and invokes its
#   print_<group>_help function.
#   args:   $1 = group name
#   exit:   0 for known groups, 1 for unknown (root help is shown too).
print_group_help() {
    local group="${1:-}"
    local help_file="${REPO_ROOT}/commands/${group}/help.sh"

    if [[ -z "${group}" || ! -f "${help_file}" ]]; then
        echo "Unknown group: ${group}" >&2
        print_root_help
        return 1
    fi

    # shellcheck source=/dev/null
    source "${help_file}"

    local fn="print_${group}_help"
    if ! declare -F "${fn}" >/dev/null; then
        echo "Internal error: function ${fn} not defined in ${help_file}" >&2
        return 1
    fi

    "${fn}"
}
