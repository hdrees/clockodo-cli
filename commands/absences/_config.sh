#!/usr/bin/env bash
# =============================================================================
# commands/absences/_config.sh — Per-group config.
#
# Intentionally without a cache TTL: absences change through approval
# workflows, and the per-user filtered lists are cheap. /v4/absences is not
# paginated either — `clockodo_api_get` covers it directly.
# =============================================================================

set -euo pipefail
