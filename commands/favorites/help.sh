#!/usr/bin/env bash

set -euo pipefail

print_favorites_help() {
    cat <<'EOF'
clockodo favorites — manage favorites

Usage:
  clockodo favorites list [--json]
  clockodo favorites start [<id>] [--json]

Actions:
  list           List all favorites as a table (ID, name).
  start [<id>]   Start a favorite. Without an ID the picker is shown
                 (numbered list via bash select).
                 In --json mode an ID is required (no interactive picker).

Examples:
  clockodo favorites list
  clockodo favorites list --json
  clockodo favorites start
  clockodo favorites start 12345
  clockodo favorites start 12345 --json
EOF
}
