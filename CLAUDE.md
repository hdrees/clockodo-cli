# clockodo-cli — Project conventions

Modular Bash CLI for the Clockodo API.

## Version

Current version: **0.1.0** (maintained in [clockodo](clockodo) as `CLOCKODO_CLI_VERSION`).

- Semver: MAJOR.MINOR.PATCH.
- Bump the version on larger changes (new command group, breaking change to the CLI interface, new API endpoints).
- **ALWAYS ask the user** whether and to which version to bump — never autonomously.
- When bumping, also update this line and the version in the `--curl` sample output in [README.md](README.md).

## Stack
- Bash + `curl` + `jq` (no Python, no Node).
- Interactive picking uses the bash builtin `select` — no external picker (e.g. no `fzf`).

## Structure
- `clockodo` — entry point, dispatches `<group> <action>` to `commands/<group>/<action>.sh`.
- `lib/` — reusable building blocks:
  - `env.sh` — loads `.env`, validates mandatory variables.
  - `http.sh` — the only place that uses `curl`. Wrappers: `clockodo_api_get`, `clockodo_api_post`, `clockodo_api_delete`.
    Headers come from one list (`_clockodo_request_headers`) that feeds the real request, the `--curl` output and the DEBUG dump — add headers only there.
    curl always runs with `--disable` first (ignores `~/.curlrc`) and reads the headers via `--header @-` from stdin (API key not in the process list).
    State file and curl stderr live in a private `mktemp -d` directory, removed on exit.
    `http_get_public <url>` is for non-Clockodo URLs (e.g. GitHub) and never sends auth headers.
  - `pagination.sh` — walks paginated list endpoints (`clockodo_api_get_all`).
  - `cache.sh` — optional on-disk caching (`clockodo_api_get_cached`, `clockodo_api_get_all_cached`, `clockodo_api_get_cached_via_list`).
  - `active_state.sh` — `--state active|inactive|all` option for list actions (`parse_active_state_option`, `path_with_active_state`).
  - `resource_actions.sh` — shared `list`/`get` flow for cached resources with an `active` flag (`run_state_filtered_list`, `run_cached_get`); the group's action files only pass help function, endpoint, TTL and renderer.
  - `user_argument.sh` — resolves a `me|<user-id>` argument (`resolve_user_argument`, result in `RESOLVED_USER_ID`); rejects `me` with `--curl`.
  - `ui.sh` — renderers shared by several groups (`print_id_name_table`, `print_json_document`).
  - `usage.sh` — root help + dispatcher (`print_root_help`, `print_group_help`).
  - `helper.sh` — shared helpers (`has_help_arg`, `validate_numeric_id`, `is_debug_enabled`, the `emit_*` output helpers).
  - `version.sh` — `clockodo version`: local vs. published version (read from the `CLOCKODO_CLI_VERSION` line of `clockodo` on `main` of github.com/hdrees/clockodo-cli).
  - `describe.sh`, `doctor.sh`, `upgrade.sh`, `version.sh` — top-level commands without action
    (`cmd_<command>`), dispatched in the entry script before `.env` is loaded.
  - `contract.json` — root contract for `clockodo describe`: global flags, env vars, envelope, error codes, top-level commands.
- `commands/<group>/<action>.sh` — one function `cmd_<group>_<action>` per action.
- `commands/<group>/help.sh` — defines `print_<group>_help` for that group.
- `commands/<group>/ui.sh` — group-specific renderers and interactive pickers (e.g. `print_favorites_table`, `select_favorite`). Optional — groups that only need `print_id_name_table` have none.
- `commands/<group>/contract.json` — machine-readable contract of every action of the group (`clockodo describe`).
- `skills/clockodo-cli/SKILL.md` — agent skill; refers to `describe` instead of repeating command details.

The entry script sources every `.sh` file inside `commands/<group>/` before
the action file runs, so any additional group-local file (helpers, prompts,
shared parsers) is automatically available to all actions of that group.

## Rules
- Subcommands never call `curl` directly. Always go through `lib/http.sh`.
- Help is checked with `has_help_arg "$@"` (any position), not only on `$1`.
- Numeric ID arguments are validated with `validate_numeric_id <label> <value>`; argument errors are reported with `emit_argument_error` — never inline `if is_json_output_mode … echo … >&2`.
- Arithmetic on user input (e.g. `select`'s `$REPLY`) forces base 10 (`10#…`); leading zeros would otherwise be read as octal.
- Auth headers are set centrally in `lib/http.sh`.
- Parse JSON exclusively with `jq`.
- Every action accepts `--help` / `-h` and prints the group help.
- Every action honors the global `--json` flag (see "JSON output mode") and the global `--curl` flag (see "curl output mode").
- User-facing output in English, code identifiers in English. Docs (README, `.env.example`, help texts) are English too.
- Error messages go to stderr, exit code ≠ 0.
- Text output (tables, lists, help texts) is sorted alphabetically when no domain order applies: groups in `print_root_help`, table rows in `print_*_table` by name (case-insensitive via `ascii_downcase`). Exceptions: `--json` mode passes the API response through unchanged, and lists with a meaningful domain order (e.g. favorites — user-defined order in Clockodo) stay as the API returns them.
- List actions (`*_list`) show only `ID` and `Name` in text mode. Detail actions (`*_get`, `*_me`) show the full field set. `--json` mode is unaffected — it always returns the full API payload.
- List actions for resources with an `active` flag accept `--state active|inactive|all` (default `active`) via `lib/active_state.sh`. `get` is never filtered by state.
- Every action has an entry in its group's `contract.json`; keep it in sync with arguments, options, requests and `--json` data.

## Comment style

- code in this repo is commented.
- Every function: short description (purpose, arguments, stdout/stderr contract, exit code).
- Non-trivial bash constructs (parameter expansion, `set -euo pipefail`, heredocs, IFS tricks) get an explanatory comment.
- File header: purpose of the file + dependencies (which `lib/*.sh` must be sourced first).
- Comments in English.

## Adding a new endpoint
1. Create `commands/<group>/<action>.sh` with a function `cmd_<group>_<action>`.
2. Reuse existing helpers (`clockodo_api_get`, `_post`, `select_*`, `print_*_table`, `print_id_name_table`) — no own `curl` calls. Cached list/get actions of resources with an `active` flag use `run_state_filtered_list` / `run_cached_get` (`lib/resource_actions.sh`); `me|<user-id>` arguments use `resolve_user_argument`.
3. For a new group: also create `commands/<group>/help.sh` defining `print_<group>_help`. Optionally add `commands/<group>/ui.sh` for group-specific renderers. For an existing group: update the help text and reuse/extend the group's `ui.sh` as needed.
4. Add the group name to the "Groups" list in `print_root_help` (`lib/usage.sh`).
5. For list endpoints that paginate: use `clockodo_api_get_all` from `lib/pagination.sh`.
6. For list endpoints: define `<GROUP>_CACHE_TTL` in `commands/<group>/_config.sh` and use the `*_cached` wrappers from `lib/cache.sh`; `get.sh` uses `clockodo_api_get_cached_via_list` against the same constant.
7. README: add a shell example only if the command is user-facing enough to warrant one; no per-command curl examples (`--curl` prints them).
8. Mirror any new env variables in `.env.example`.
9. Add the action to `commands/<group>/contract.json` (new group: create it with `summary` and `actions`).

## Write guards (`--dry-run`, `CLOCKODO_READ_ONLY`)
- Enforced once in `_clockodo_request` (`lib/http.sh`) for every method except GET — never per action.
- `--dry-run`: reports the write request on fd 3 (`_print_dry_run_and_stop`) and exits 0; GET lookups still run. `--curl` wins and drops it.
- `CLOCKODO_READ_ONLY=1`: refuses the write (state file status `read_only`, `emit_api_failure` → code `read_only`). Dry-run is allowed, `--curl` for writes is refused.

## .env
- Lives in the repo root, loaded by `lib/env.sh`.
- Mandatory: `CLOCKODO_API_USER`, `CLOCKODO_API_KEY`.
- Optional: `CLOCKODO_API_URL` (default `https://my.clockodo.com/api`).
- Optional: `CACHE` (`1` = on, default off) — see "Caching".
- Optional: `DEBUG` (`1` = on, default off) — see "Debug mode".
- Optional: `CLOCKODO_READ_ONLY` (`1` = refuse writes, default off) — see "Write guards".
- Values from the command line win over `.env` (`.env` provides defaults only).
- `CLOCKODO_EXTERNAL_APP` is generated automatically in `lib/env.sh` as
  `clockodo-cli/<CLOCKODO_CLI_VERSION>;<CLOCKODO_API_USER>` — do not store it in `.env`.
- `.env` is never committed (see `.gitignore`).

## Debug mode (`DEBUG`)

- `DEBUG=1` enables a formatted request/response dump on stderr in [lib/http.sh](lib/http.sh), plus cache HIT/MISS banners from [lib/cache.sh](lib/cache.sh).
- Check it via `is_debug_enabled` (`lib/helper.sh`), never via `$DEBUG` directly: it is always off in `--json` mode, which must not write to stderr.
- Enable ad-hoc via `DEBUG=1 ./clockodo …` or optionally via `.env`.
- Documented for users in the README ("Debug output"), in `.env.example` and in `print_root_help` — keep them in sync.
- The API key is masked to its first 4 characters in the dump; this masking must not be removed.

## JSON output mode (`--json`)

- Every action accepts a global `--json` flag that switches output to a single JSON envelope on stdout. Strict, non-interactive, scriptable. The flag's position is irrelevant; it is stripped from `$@` before dispatch.
- Envelope:
  - success: `{ "status": "success", "data": <result> }`
  - failure: `{ "status": "failure", "data": null, "error": { "message": "...", "code": "...", "http_status": <int>, "body": <json> } }` — `http_status` and `body` are present only for API errors (HTTP ≥ 400).
  - Failure codes of API requests: `http_<status>` (HTTP ≥ 400), `network_error` (no HTTP response; the curl error is the message), `invalid_response` (success status but non-JSON body).
- In `--json` mode no human-readable text is written to stdout or stderr (DEBUG included).
- Interactive UI (bash-select pickers) is disabled in `--json` mode. Actions that would require user input return a failure envelope with code `missing_argument`.
- `--help` / `-h` always prints text help, even when combined with `--json`.
- Helpers in `lib/helper.sh`:
  - `is_json_output_mode`
  - `emit_json_data <api-response>` — for responses wrapped in a top-level `data` field (the Clockodo norm). Unwraps `.data` so our envelope does not double-nest.
  - `emit_json_success <data-json>` — for responses without a `.data` wrapper (e.g. `/v2/favorites/{id}/start` which returns `{"running":…}` directly).
  - `emit_api_failure` — after a failed `clockodo_api_*` call: failure envelope from the HTTP state file in `--json` mode, nothing in text mode (`lib/http.sh` already reported the error).
  - `emit_argument_error <message> [code]` — invalid/missing CLI argument: envelope in `--json` mode, `Error: …` on stderr otherwise (default code `invalid_argument`).
  - `emit_json_failure <message> [code] [http_status] [body-json]` — low level; only for failures that are neither API nor argument errors.
- New actions MUST honor `--json` via these helpers; never assemble JSON by hand. Default to `emit_json_data`; use `emit_json_success` only when the API response has no `.data` wrapper. API failures go through `emit_api_failure`, argument errors through `emit_argument_error`.
- Responses wrapped in another key (e.g. `entry`, `entries`) are unwrapped via
  `emit_json_success "$(echo "${json}" | jq '.<key>')"`.

## curl output mode (`--curl`)

- The global `--curl` flag prints the curl command for the request instead of sending it, then exits 0. Stripped from `$@` like `--json`; helper: `is_curl_output_mode` (`lib/helper.sh`).
- Implemented once in `_print_curl_command_and_stop` (`lib/http.sh`), called from `_clockodo_request` before the real call. It prints the *first* request an action makes and stops the CLI — paginated lists therefore show page 1 only.
- Mechanism: requests run inside `$(…)`, so the entry script keeps the terminal stdout as fd 3 (`exec 3>&1`) and traps `USR1` (`exit 0`) — both only in `--curl` mode. The printer writes to fd 3 and signals the main shell via `kill -USR1 "$$"`. Do not close fd 3 or reuse `USR1`.
- The printed command is rendered from the same header list as the real request (see `lib/http.sh` above), so it cannot drift.
- Credentials are printed with their real values (copy & paste runnable); the README warns about it.
- `--curl` wins over `--json` (errors are plain text). The cache is always bypassed (`is_cache_enabled` returns false).
- Actions that need a prior lookup request before the actual one (e.g. `list me`) or an interactive picker MUST reject `--curl` via `emit_argument_error` instead of printing the lookup.

## Pagination

Many Clockodo list endpoints paginate (uniform scheme: `page` and
`items_per_page` query params; `paging.count_pages` in the response). Use
`clockodo_api_get_all <path>` from [lib/pagination.sh](lib/pagination.sh)
instead of `clockodo_api_get` to fetch the full list — it walks the pages
and returns a single `{ "data": [...] }` envelope indistinguishable from a
non-paginated response.

- Default page size: 1000 (override via `CLOCKODO_ITEMS_PER_PAGE`, max 5000).
- HTTP errors propagate via the same state file as `clockodo_api_get`
  (`clockodo_last_status` / `clockodo_last_body`); actions report them with `emit_api_failure`.
- New paginated commands MUST use `clockodo_api_get_all`; never roll a
  per-action loop.
- Endpoints that wrap their items in another key than `data` (e.g. `/v2/entries`
  → `entries`) pass it as second argument: `clockodo_api_get_all <path> entries`.
  The merged envelope keeps that key.

## Caching

List endpoints can be cached on disk. Caching is opt-in via the `CACHE=1`
env variable (default: off), set ad-hoc (`CACHE=1 ./clockodo …`) or in
`.env`. It is documented for users in the README ("Caching") and in
`.env.example` — keep both in sync when the cache behavior changes.
Cache files live in
`${XDG_CACHE_HOME:-$HOME/.cache}/clockodo-cli/<account>/`, where `<account>`
is a hash of `CLOCKODO_API_URL` + `CLOCKODO_API_USER` (never mix data of two
accounts or instances), keyed by the endpoint path including its query
string (`/v3/customers` → `v3_customers.json`,
`/v3/customers?filter%5Bactive%5D=true` → `v3_customers__filter-active-true.json`).
The cache directory is resolved lazily (`_cache_dir`), because `load_env`
runs after `lib/cache.sh` is sourced. Files of older layouts (`clockodo_cli/`,
flat files in the root) are removed on the next cache write.

Use the cached wrappers from [lib/cache.sh](lib/cache.sh) instead of the
raw HTTP helpers:

- `clockodo_api_get_cached <path> <ttl>` — single-shot GET, cached.
- `clockodo_api_get_all_cached <path> <ttl>` — paginated GET, cached.
- `clockodo_api_get_cached_via_list <detail_path> <list_path> <id> <ttl>`
  — single-resource GET that prefers the matching entry from a fresh
  list cache; it searches every fresh variant of the list (unfiltered and
  filtered), newest first, and takes the first match. Single-resource calls
  **never** write their own cache file.

Each group defines its TTL as a constant in `commands/<group>/_config.sh`
(e.g. `CUSTOMERS_CACHE_TTL=300`). The leading underscore makes that file
sort first in the entry script's group source loop, so both `list.sh` and
`get.sh` see the constant regardless of which action is being dispatched.

When debug output is enabled (`is_debug_enabled`), cache hits and misses are
logged to stderr in the same banner style as the request/response dump in
`lib/http.sh`.

Groups without a cache TTL (`absences`, `entries`, `targethours`) say why in
their `_config.sh` — the reason is the data's volatility, not the cache key.

## API reference
- Spec: https://docs.clockodo.com/openapi.yaml
- Mandatory auth headers:
  - `X-ClockodoApiUser`
  - `X-ClockodoApiKey`
  - `X-Clockodo-External-Application` (format: `appname;email`)
