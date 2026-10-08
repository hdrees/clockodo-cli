#!/usr/bin/env bash
# =============================================================================
# commands/absences/help.sh — Help text for the `absences` command group.
# =============================================================================

set -euo pipefail

print_absences_help() {
    cat <<'EOF'
clockodo absences — manage absences

Usage:
  clockodo absences list [me|<user-id>] [--json]
  clockodo absences get <id> [--json]

Actions:
  list              List absences. Without argument: all users. With `me`:
                    the currently authenticated user (resolved via /v4/users/me).
                    With a numeric user ID: only that user's entries.
  get <id>          Show a single absence by its ID.

Examples:
  clockodo absences list
  clockodo absences list me
  clockodo absences list 178431
  clockodo absences get 12345
EOF
}
