#!/usr/bin/env bash
# =============================================================================
# commands/entries/_config.sh — Per-group config.
#
# Intentionally without a cache TTL: time entries change constantly (the
# running clock grows every second, entries are added and edited all day),
# so any cached range would be stale right away.
# =============================================================================

set -euo pipefail
