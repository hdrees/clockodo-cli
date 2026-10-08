#!/usr/bin/env bash
# =============================================================================
# commands/services/list.sh — Lists all services (paginated).
# Usage: `clockodo services list [--state active|inactive|all] [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; SERVICES_CACHE_TTL is defined in
# commands/services/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_services_list
#   Fetches every page of /v4/services filtered by `--state`
#   (default: active) and renders the result as a table (text mode) or
#   success envelope (--json).
#   args:   [--state active|inactive|all] (or --help / -h)
cmd_services_list() {
    run_state_filtered_list print_services_help /v4/services "${SERVICES_CACHE_TTL}" print_id_name_table "$@"
}
