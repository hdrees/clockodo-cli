#!/usr/bin/env bash
# =============================================================================
# commands/customers/list.sh — Lists all customers (paginated).
# Usage: `clockodo customers list [--state active|inactive|all] [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; CUSTOMERS_CACHE_TTL is defined in
# commands/customers/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_customers_list
#   Fetches every page of /v3/customers filtered by `--state`
#   (default: active) and renders the result as a table (text mode) or
#   success envelope (--json).
#   args:   [--state active|inactive|all] (or --help / -h)
cmd_customers_list() {
    run_state_filtered_list print_customers_help /v3/customers "${CUSTOMERS_CACHE_TTL}" print_id_name_table "$@"
}
