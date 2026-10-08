---
name: clockodo-cli
description: Read and act on Clockodo data (time entries, clock, favorites, absences, target hours, customers, projects, services, users) through the `clockodo` CLI. Use when a question or task needs Clockodo data, or when starting/stopping the clock.
---

# clockodo CLI

`clockodo` is a Bash CLI for the Clockodo API. If it is not on `PATH`, call it by its path in the clockodo-cli repo (`./clockodo`).

## Discover

`clockodo describe` is the source of truth for every command: arguments, options, whether it **writes**, the API requests it sends, `--curl` support, the shape of the `--json` data and its error codes. Look up a command before the first call:

```bash
clockodo describe --json                    # groups, global flags, error codes
clockodo describe entries summary --json    # one action
```

## Call

1. Append `--json` to every call. The result is one envelope on stdout: `{"status":"success","data":…}` or `{"status":"failure","data":null,"error":{"message","code",…}}`. Branch on `.status` and `.error.code`, not on text.
2. Project with `jq` before the result enters your context: keep only the fields that answer the question, and aggregate (sum, count, group) instead of listing rows. Entries, absences and users carry personal data; pull the minimum.
   ```bash
   clockodo entries list --me --since 2026-10-01 --until 2026-10-31 --json \
     | jq '[.data[].duration // 0] | add / 3600'
   ```
3. Pass explicit IDs. Without an ID, `favorites start` would open an interactive picker; with `--json` it fails with `missing_argument` instead.

## Write

Commands whose contract says `"writes": true` (`favorites start`, `entries stop`) change the user's time tracking.

1. Run the command with `--dry-run --json` first. It runs lookups, sends no write and returns `data.request` (method, URL, body).
2. Show the user what will happen and get their confirmation.
3. Run it without `--dry-run`.

Error code `read_only` means the user has set `CLOCKODO_READ_ONLY=1`. Respect it: report that writing is disabled and leave the setting alone.

## Errors

- `configuration_error`, `network_error` or `http_401`: run `clockodo doctor --json` and report the failed checks (`.data.checks[] | select(.status == "fail")`).
- `invalid_argument` / `missing_argument`: re-read `clockodo describe <group> <action>` and fix the call.

`--curl` prints the API key in clear text. Use it only when the user asks for the raw request.
