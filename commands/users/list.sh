#!/usr/bin/env bash
# =============================================================================
# commands/users/list.sh — Lists all users (paginated).
# Usage: `clockodo users list [--state active|inactive|all] [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; USERS_CACHE_TTL is defined in
# commands/users/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_users_list
#   Fetches every page of /v3/users filtered by `--state`
#   (default: active) and renders the result as a table (text mode) or
#   success envelope (--json).
#   args:   [--state active|inactive|all] (or --help / -h)
cmd_users_list() {
    run_state_filtered_list print_users_help /v3/users "${USERS_CACHE_TTL}" print_id_name_table "$@"
}
