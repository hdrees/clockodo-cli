#!/usr/bin/env bash
# =============================================================================
# commands/customers/get.sh — Shows a single customer by ID.
# Usage: `clockodo customers get <id> [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; CUSTOMERS_CACHE_TTL is defined in
# commands/customers/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_customers_get
#   GETs /v3/customers/{id} (or the entry from a fresh list cache) and prints
#   the result.
#   args:   $1 numeric customer ID (or --help / -h)
cmd_customers_get() {
    run_cached_get print_customers_help customer /v3/customers "${CUSTOMERS_CACHE_TTL}" print_json_document "$@"
}
