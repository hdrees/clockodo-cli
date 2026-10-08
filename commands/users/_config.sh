#!/usr/bin/env bash
# =============================================================================
# commands/users/_config.sh — Per-group config constants.
# Sorts first in the entry-script's source loop; constants here are visible
# to all sibling action scripts.
# =============================================================================

set -euo pipefail

# Cache TTL (seconds) for /v3/users. Consumed by list.sh and get.sh.
# /v4/users/me uses USERS_ME_CACHE_TTL from lib/user_argument.sh, because
# other groups (absences, entries, targethours) resolve `me` as well.
USERS_CACHE_TTL=300
