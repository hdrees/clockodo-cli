#!/usr/bin/env bash
# =============================================================================
# commands/users/get.sh — Shows a single user by ID.
# Usage: `clockodo users get <id> [--json|--help|-h]`
#
# Dependencies: lib/resource_actions.sh; USERS_CACHE_TTL is defined in
# commands/users/_config.sh.
# =============================================================================

set -euo pipefail

# cmd_users_get
#   GETs /v3/users/{id} (or the entry from a fresh list cache) and prints
#   the result.
#   args:   $1 numeric user ID (or --help / -h)
cmd_users_get() {
    run_cached_get print_users_help user /v3/users "${USERS_CACHE_TTL}" print_user_detail "$@"
}
