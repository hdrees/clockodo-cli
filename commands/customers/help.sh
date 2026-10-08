#!/usr/bin/env bash
# =============================================================================
# commands/customers/help.sh — Help text for the `customers` command group.
# =============================================================================

set -euo pipefail

print_customers_help() {
    cat <<'EOF'
clockodo customers — manage customers

Usage:
  clockodo customers list [--state active|inactive|all] [--json]
  clockodo customers get <id> [--json]

Actions:
  list           List customers (paginated, fetches all pages). Only active
                 ones by default.
  get <id>       Show a single customer by ID.

Options:
  --state <s>    Filter list by state: active (default), inactive, all.

Examples:
  clockodo customers list
  clockodo customers list --json
  clockodo customers list --state inactive
  clockodo customers list --state=all
  clockodo customers get 12345
EOF
}
