#!/usr/bin/env bash
# =============================================================================
# commands/subprojects/get.sh — Shows a single subproject by ID.
# Usage: `clockodo subprojects get <id> [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; SUBPROJECTS_CACHE_TTL is defined in
# commands/subprojects/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_subprojects_get
#   GETs /v3/subprojects/{id} (or the entry from a fresh list cache) and prints
#   the result.
#   args:   $1 numeric subproject ID (or --help / -h)
cmd_subprojects_get() {
    run_cached_get print_subprojects_help subproject /v3/subprojects "${SUBPROJECTS_CACHE_TTL}" print_json_document "$@"
}
