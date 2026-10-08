#!/usr/bin/env bash
# =============================================================================
# commands/subprojects/_config.sh — Per-group config constants.
# Sorts first in the entry-script's source loop; constants here are visible
# to all sibling action scripts.
# =============================================================================

set -euo pipefail

# Cache TTL (seconds) for /v3/subprojects. Consumed by list.sh and get.sh.
SUBPROJECTS_CACHE_TTL=300
