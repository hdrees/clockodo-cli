#!/usr/bin/env bash
# =============================================================================
# commands/projects/get.sh — Shows a single project by ID.
# Usage: `clockodo projects get <id> [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; PROJECTS_CACHE_TTL is defined in
# commands/projects/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_projects_get
#   GETs /v4/projects/{id} (or the entry from a fresh list cache) and prints
#   the result.
#   args:   $1 numeric project ID (or --help / -h)
cmd_projects_get() {
    run_cached_get print_projects_help project /v4/projects "${PROJECTS_CACHE_TTL}" print_json_document "$@"
}
