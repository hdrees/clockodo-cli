#!/usr/bin/env bash
# =============================================================================
# commands/projects/help.sh — Help text for the `projects` command group.
# =============================================================================

set -euo pipefail

print_projects_help() {
    cat <<'EOF'
clockodo projects — manage projects

Usage:
  clockodo projects list [--state active|inactive|all] [--json]
  clockodo projects get <id> [--json]

Actions:
  list           List projects (paginated, fetches all pages). Only active
                 ones by default.
  get <id>       Show a single project by ID.

Options:
  --state <s>    Filter list by state: active (default), inactive, all.

Examples:
  clockodo projects list
  clockodo projects list --json
  clockodo projects list --state inactive
  clockodo projects list --state=all
  clockodo projects get 12345
EOF
}
