#!/usr/bin/env bash
# =============================================================================
# commands/entries/help.sh — Help text for the `entries` command group.
# =============================================================================

set -euo pipefail

print_entries_help() {
    cat <<'HELP'
clockodo entries — list, show, summarize and stop time entries

Usage:
  clockodo entries list [--me|--user <id>] [--since <date>] [--until <date>] [--json]
  clockodo entries list --running
  clockodo entries summary
  CACHE=1 clockodo entries summary --user 12345 --json [--json]
  clockodo entries summary [--me|--user <id>] [--date <YYYY-MM-DD>] [--json]
  clockodo entries get <id> [--json]
  clockodo entries stop [<id>] [--json]

Actions:
  list              List time entries of a time range (default: today).
                    Without --me/--user: all entries the API key may see.
  summary           Day summary of one user (default: --me, today): total
                    time incl. the running entry, start of day, target
                    hours, delta and percent. One /v2/entries request;
                    /v4/users/me and /targethours are cached with CACHE=1.
                    Not supported with --curl.
  get <id>          Show a single time entry by its ID.
  stop [<id>]       Stop the running clock entry. Without an ID the running
                    entry of the authenticated user is looked up first.

Options for list:
  --me              Only entries of the authenticated user
                    (resolved via /v4/users/me).
  --user <id>       Only entries of the user with this ID (no lookup).
  --running         Show the running clock entry of the authenticated user
                    instead of a list. Cannot be combined with --since/--until
                    or --me/--user.
  --since <date>    Start of the range, inclusive. YYYY-MM-DD (local day)
                    or a UTC timestamp YYYY-MM-DDTHH:MM:SSZ. Default: today.
  --until <date>    End of the range. YYYY-MM-DD includes the whole day;
                    a UTC timestamp is used as is. Default: same as --since.

Options for summary:
  --me | --user <id>  Whose day (default: --me).
  --date <date>     Local calendar day YYYY-MM-DD. Default: today.

Examples:
  clockodo entries list
  clockodo entries list --me
  clockodo entries list --me --since 2026-09-01 --until 2026-09-30
  clockodo entries list --running
  clockodo entries get 12345
  clockodo entries stop
HELP
}
