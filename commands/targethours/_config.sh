#!/usr/bin/env bash
# =============================================================================
# commands/targethours/_config.sh — Per-group config.
#
# The list cache TTL (TARGETHOURS_CACHE_TTL) lives in lib/target_hours.sh,
# because `entries summary` reads target hours as well. `get` is not cached:
# /targethours/{id} wraps its item in `targethoursRow`, the list in
# `targethours`, which clockodo_api_get_cached_via_list does not support.
# =============================================================================

set -euo pipefail
