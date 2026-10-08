#!/usr/bin/env bash
# =============================================================================
# commands/targethours/help.sh — Help text for the `targethours` command group.
# =============================================================================

set -euo pipefail

print_targethours_help() {
    cat <<'EOF'
clockodo targethours — manage target hours

Usage:
  clockodo targethours list [me|<user-id>] [--json]
  clockodo targethours get <id> [--json]

Actions:
  list              List target hours. Without argument: all users. With `me`:
                    the currently authenticated user (resolved via /v4/users/me).
                    With a numeric user ID: only that user's entries.
  get <id>          Show a single target hours entry by its ID.

Examples:
  clockodo targethours list
  clockodo targethours list me
  clockodo targethours list 178431
  clockodo targethours get 12345
EOF
}
