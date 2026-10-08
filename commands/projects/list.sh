#!/usr/bin/env bash
# =============================================================================
# commands/projects/list.sh — Lists all projects (paginated).
# Usage: `clockodo projects list [--state active|inactive|all] [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; PROJECTS_CACHE_TTL is defined in
# commands/projects/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_projects_list
#   Fetches every page of /v4/projects filtered by `--state`
#   (default: active) and renders the result as a table (text mode) or
#   success envelope (--json).
#   args:   [--state active|inactive|all] (or --help / -h)
cmd_projects_list() {
    run_state_filtered_list print_projects_help /v4/projects "${PROJECTS_CACHE_TTL}" print_id_name_table "$@"
}
