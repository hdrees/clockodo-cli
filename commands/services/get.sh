#!/usr/bin/env bash
# =============================================================================
# commands/services/get.sh — Shows a single service by ID.
# Usage: `clockodo services get <id> [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; SERVICES_CACHE_TTL is defined in
# commands/services/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_services_get
#   GETs /v4/services/{id} (or the entry from a fresh list cache) and prints
#   the result.
#   args:   $1 numeric service ID (or --help / -h)
cmd_services_get() {
    run_cached_get print_services_help service /v4/services "${SERVICES_CACHE_TTL}" print_json_document "$@"
}
