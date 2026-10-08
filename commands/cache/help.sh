#!/usr/bin/env bash
# =============================================================================
# commands/cache/help.sh — Help text for the `cache` command group.
# =============================================================================

set -euo pipefail

# print_cache_help
#   Prints the help of the cache group.
print_cache_help() {
    cat <<'HELP'
clockodo cache — inspect and clear the local cache

Usage:
  clockodo cache list [--json]
  clockodo cache delete <key|path> [--json]
  clockodo cache clear [--json]

Actions:
  list              Statistics of every cache entry of the configured
                    account: key, items, size, age, TTL, remaining TTL.
                    No cached content is shown.
  delete <key|path> Delete one entry. Pass the key shown by `cache list`
                    (e.g. v3_customers__filter-active-true) or the endpoint
                    path (e.g. /v3/customers).
  clear             Delete every cache entry of the configured account.

The commands work regardless of CACHE=1 and send no API requests, so
--curl is not supported. Entries written before TTLs were recorded show
no TTL.

Examples:
  clockodo cache list
  clockodo cache delete v4_users_me
  clockodo cache delete /v3/customers
  clockodo cache clear
HELP
}
