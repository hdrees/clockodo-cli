#!/usr/bin/env bash
# =============================================================================
# commands/projects/_config.sh — Per-group config constants.
# Sorts first in the entry-script's source loop; constants here are visible
# to all sibling action scripts.
# =============================================================================

set -euo pipefail

# Cache TTL (seconds) for /v4/projects. Consumed by list.sh and get.sh.
PROJECTS_CACHE_TTL=300
