#!/usr/bin/env bash
# =============================================================================
# commands/customers/_config.sh — Per-group config constants.
# Sorts first in the entry-script's source loop; constants here are visible
# to all sibling action scripts.
# =============================================================================

set -euo pipefail

# Cache TTL (seconds) for /v3/customers. Consumed by list.sh and get.sh.
CUSTOMERS_CACHE_TTL=300
