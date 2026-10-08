#!/usr/bin/env bash
# =============================================================================
# commands/users/help.sh — Help text for the `users` command group.
# =============================================================================

set -euo pipefail

print_users_help() {
    cat <<'EOF'
clockodo users — manage users

Usage:
  clockodo users list [--state active|inactive|all] [--json]
  clockodo users get <id> [--json]
  clockodo users me [--json]

Actions:
  list           List users (paginated, fetches all pages). Only active
                 ones by default.
  get <id>       Show a single user by ID.
  me             Show the currently authenticated user (resolved from the API key).

Options:
  --state <s>    Filter list by state: active (default), inactive, all.

Examples:
  clockodo users list
  clockodo users list --json
  clockodo users list --state inactive
  clockodo users list --state=all
  clockodo users get 12345
  clockodo users me
EOF
}
