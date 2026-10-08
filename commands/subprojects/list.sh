#!/usr/bin/env bash
# =============================================================================
# commands/subprojects/list.sh — Lists all subprojects (paginated).
# Usage: `clockodo subprojects list [--state active|inactive|all] [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; SUBPROJECTS_CACHE_TTL is defined in
# commands/subprojects/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_subprojects_list
#   Fetches every page of /v3/subprojects filtered by `--state`
#   (default: active) and renders the result as a table (text mode) or
#   success envelope (--json).
#   args:   [--state active|inactive|all] (or --help / -h)
cmd_subprojects_list() {
    run_state_filtered_list print_subprojects_help /v3/subprojects "${SUBPROJECTS_CACHE_TTL}" print_id_name_table "$@"
}
