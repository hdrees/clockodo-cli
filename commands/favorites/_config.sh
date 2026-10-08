#!/usr/bin/env bash
# =============================================================================
# commands/favorites/_config.sh — Per-group config constants.
#
# The leading underscore in the filename guarantees this file sorts first
# in the entry-script's group source loop, so the constants defined here
# are visible to all sibling action scripts regardless of their name.
# =============================================================================

set -euo pipefail

# Cache TTL (seconds) for /v2/favorites. Consumed by list.sh and start.sh.
FAVORITES_CACHE_TTL=300
