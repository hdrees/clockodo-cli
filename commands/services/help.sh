#!/usr/bin/env bash
# =============================================================================
# commands/services/help.sh — Help text for the `services` group.
# =============================================================================

set -euo pipefail

print_services_help() {
    cat <<'EOF'
clockodo services — manage services

Usage:
  clockodo services list [--state active|inactive|all] [--json]
  clockodo services get <id> [--json]

Actions:
  list           List services (paginated, fetches all pages). Only active
                 ones by default.
  get <id>       Show a single service by ID.

Options:
  --state <s>    Filter list by state: active (default), inactive, all.

Examples:
  clockodo services list
  clockodo services list --json
  clockodo services list --state inactive
  clockodo services list --state=all
  clockodo services get 12345
EOF
}
