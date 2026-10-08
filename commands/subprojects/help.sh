#!/usr/bin/env bash
# =============================================================================
# commands/subprojects/help.sh — Help text for the `subprojects` group.
# =============================================================================

set -euo pipefail

print_subprojects_help() {
    cat <<'EOF'
clockodo subprojects — manage subprojects

Usage:
  clockodo subprojects list [--state active|inactive|all] [--json]
  clockodo subprojects get <id> [--json]

Actions:
  list           List subprojects (paginated, fetches all pages). Only active
                 ones by default.
  get <id>       Show a single subproject by ID.

Options:
  --state <s>    Filter list by state: active (default), inactive, all.

Examples:
  clockodo subprojects list
  clockodo subprojects list --json
  clockodo subprojects list --state inactive
  clockodo subprojects list --state=all
  clockodo subprojects get 12345
EOF
}
