# clockodo-cli

Modular Bash CLI for the [Clockodo API](https://docs.clockodo.com/).

> **Disclaimer:** This is an unofficial community tool. It is not affiliated with, endorsed by or supported by Clockodo / Clockodo GmbH. "Clockodo" is a trademark of its respective owner.

## Why this project

### 1. Clockodo on the console

Start a favorite, stop the clock or check today's entries without leaving the terminal:

```bash
./clockodo favorites start
./clockodo entries list --me
./clockodo entries stop
```

Plain stdout/stderr and exit codes make the CLI easy to use in shell scripts, aliases, cron jobs or a status bar.

### 2. Integrating Clockodo elsewhere

`--curl` prints the exact API request for every command. That request can be reused in any tool that can send an HTTP request or run a shell command, without writing an API client. Some ideas:

- **Voice assistants** (e.g. Alexa skills on an Amazon Echo): start a favorite or stop the clock by voice.
- **AI skills** (e.g. Claude skills): ready-made skills such as dictating a working day as time entries can call the CLI or the printed curl requests.
- **Home automation, Stream Deck, launchers**: a button or shortcut that runs `./clockodo favorites start <id>`.
- **CI or chat bots**: book or report time from a pipeline or a chat command.

Keep in mind that `--curl` prints your API key in clear text. Store it as a secret in the target tool.

### 3. Faster and leaner access for AI assistants

AI assistants such as Claude can use Clockodo via an MCP server, but every tool call puts the **full API response** into the model's context — all fields, all rows, whether needed or not. That costs tokens, time and, with time entries or user data, also exposes more personal data than the question requires.

The CLI reduces the output *before* it reaches the model:

- **Compact text output.** `list` actions print only `ID` and `Name`, sorted — a fraction of the JSON payload.
  ```bash
  ./clockodo customers list
  ```
- **Project with `jq`.** `--json` returns a stable envelope (`{ "status": …, "data": … }`); pipe it through `jq` to keep only the fields that answer the question:
  ```bash
  # only ID and name of matching customers
  ./clockodo customers list --json | jq -r '.data[] | select(.name | test("acme"; "i")) | [.id, .name] | @tsv'

  # total booked time today in hours, without any per-entry data
  ./clockodo entries list --me --json | jq '[.data[].duration // 0] | add / 3600'
  ```
- **Aggregate instead of listing.** Let `jq` sum, count or group, so only the result enters the context — cheaper and better for data protection than raw entries.
- **Contracts on demand instead of schemas.** `./clockodo describe <group> <action> --json` gives the assistant arguments, options, write behavior and the shape of the result, only for the command it is about to use. No large tool definitions have to be held in context.
- **Fewer API calls.** `CACHE=1` serves repeated lookups (customers, projects, services) from disk.
- **Clear errors.** Errors go to stderr with a non-zero exit code. In `--json` mode they come as a failure envelope with a machine-readable `code`.

- **Guarded writes.** `--dry-run` shows a write request before it is sent, `CLOCKODO_READ_ONLY=1` refuses writes altogether (see [Write guards](#write-guards)).

The repo ships a ready-made skill for that (see [AI agent skill](#ai-agent-skill)): it tells the assistant to discover commands via `describe`, use `--json | jq` with a projection, and dry-run writes before asking for confirmation.

## Requirements

- `bash` (4+), `curl`, `jq`

## Setup

1. Clone the repo.
2. Create `.env` from the template:
   ```bash
   cp .env.example .env
   ```
3. Fill in your real credentials in `.env`:
   - `CLOCKODO_API_USER` — your Clockodo login email
   - `CLOCKODO_API_KEY` — from Clockodo under *Persönliche Daten → API-Key* (personal data)
4. Make the CLI executable (if necessary):
   ```bash
   chmod +x clockodo
   ```
5. Check the setup:
   ```bash
   ./clockodo doctor
   ```
   `doctor` checks bash, curl and jq, the env file, the credentials, the API URL, the cache directory (with `CACHE=1`) and whether the API accepts the credentials (one `GET /v4/users/me`; only the HTTP outcome is shown, never your user data). Exit code 1 if a check failed; `--json` returns `{healthy, checks}`.

### Call `clockodo` from anywhere

The examples in this README use `./clockodo` from the repo directory. To call `clockodo` from any directory, choose one of the following:

**Option A — symlink into a directory on your `PATH` (recommended):**

```bash
mkdir -p ~/.local/bin
ln -s "$(pwd)/clockodo" ~/.local/bin/clockodo   # run inside the repo directory
```

`~/.local/bin` is on the `PATH` of most Linux distributions. If `clockodo --help` reports `command not found`, add it to your shell profile (`~/.bashrc` or `~/.zshrc`) and open a new terminal:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Option B — add the repo directory to your `PATH`:**

```bash
echo 'export PATH="/path/to/clockodo-cli:$PATH"' >> ~/.bashrc   # or ~/.zshrc
```

Either way the CLI keeps reading its `.env` from the repo directory (symlinks are resolved), so moving or deleting the repo breaks the command — update the symlink or the `PATH` entry then. Check with:

```bash
cd /tmp && clockodo users me
```

### Configuration without `.env`

Environment variables always win over `.env`. When another tool calls the CLI, the repo `.env` is optional:

- `CLOCKODO_API_USER` and `CLOCKODO_API_KEY` from the environment are enough.
- `CLOCKODO_ENV_FILE=/path/to/file` reads that file instead of the repo `.env` (it must exist).
- `CLOCKODO_EXTERNAL_APPLICATION="<app>;<email>"` replaces the generated `X-Clockodo-External-Application` header (default: `clockodo-cli/<version>;<CLOCKODO_API_USER>`), so a calling tool can identify itself.

## Built-in help

```bash
./clockodo --help
./clockodo favorites --help
./clockodo favorites list --help
```

## Command contracts (`describe`)

`describe` prints a machine-readable contract of every command, meant for AI agents and scripts. It sends no request and needs no `.env`.

```bash
./clockodo describe                        # groups, top-level commands, global flags
./clockodo describe entries                # actions of a group
./clockodo describe entries stop --json    # full contract of one action
```

An action contract lists `usage`, `arguments`, `options`, `writes` (whether it changes data), `interactive`, the API `requests` it sends, `curl` support (`supported`, `partial`, `unsupported`, with `notes`), the shape of the `--json` `data` and its `error_codes`. `describe --json` without arguments also lists the global flags, environment variables, the envelope and all error codes.

The contracts live as JSON next to the code: `commands/<group>/contract.json` and `lib/contract.json` for the top-level commands.

## Filtering by state (`--state`)

The `list` actions of `customers`, `projects`, `subprojects`, `services` and `users` accept `--state` to filter by the resource's `active` flag:

| Value      | Result                         | API filter                |
|------------|--------------------------------|---------------------------|
| `active`   | only active entries (default)  | `filter[active]=true`     |
| `inactive` | only inactive entries          | `filter[active]=false`    |
| `all`      | active and inactive entries    | none                      |

Both `--state <value>` and `--state=<value>` work. Without `--state`, only active entries are listed. `get <id>` is not filtered — it returns an entry regardless of its state.

```bash
./clockodo customers list                   # active only
./clockodo customers list --state inactive
./clockodo customers list --state=all
```

## Caching

List endpoints (`customers`, `favorites`, `projects`, `services`, `subprojects`, `targethours`, `users`) and the own user (`users me`, also used to resolve `me`/`--me`) can be cached locally to avoid repeated API calls. Caching is **off** by default and is enabled with `CACHE=1` — ad hoc or permanently in `.env`:

```bash
CACHE=1 ./clockodo customers list
```

- Cache files live in `${XDG_CACHE_HOME:-~/.cache}/clockodo-cli/<account>/`, one file per request path including its query string (e.g. `/v3/customers` → `v3_customers.json`). `<account>` is a hash of `CLOCKODO_API_URL` and `CLOCKODO_API_USER`, so different accounts or instances never share cached data.
- An entry is valid for 300 seconds (TTL per group, defined in `commands/<group>/_config.sh`); `users me` and `targethours` for 3600 seconds, as they rarely change. After that, the next call reloads from the API and overwrites the file.
- `<group> list` reads and writes the cache. Each `--state` variant has its own file (e.g. `v3_customers__filter-active-true.json`).
- `<group> get <id>` first looks up the ID in the fresh list caches of the same group (any `--state` variant, newest first) and falls back to the API otherwise. It never writes its own cache file — so a `get` only benefits if a `list` ran before.
- Not cached: `absences`, `entries`, `targethours get`.
- A variable set on the command line wins over `.env` — `CACHE=0 ./clockodo …` bypasses a cache enabled in `.env`.
- Cache files of older CLI versions (`clockodo_cli/`, flat files directly in `clockodo-cli/`) are removed automatically on the next cache write.

Inspect and clear the cache of the configured account (works without `CACHE=1`, sends no API request):

```bash
./clockodo cache list                        # key, items, size, age, TTL, remaining TTL — no content
./clockodo cache delete v3_customers         # one entry, by key from `cache list` …
./clockodo cache delete /v3/customers        # … or by endpoint path
./clockodo cache clear                       # every entry of this account
```

Other accounts' cache directories are not touched. To remove everything: `rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/clockodo-cli"`.

## Debug output

With `DEBUG=1` the CLI writes a formatted request/response dump to stderr for every API call (method, URL, headers, HTTP status, body). When caching is active, cache HIT/MISS lines with age and TTL are printed as well. Off by default; enable ad hoc or permanently in `.env`:

```bash
DEBUG=1 ./clockodo users me
DEBUG=1 CACHE=1 ./clockodo customers list
```

- stdout is unaffected; the dump goes to stderr. In `--json` mode `DEBUG` has no effect — that mode writes nothing but the JSON envelope.
- The API key is truncated to its first 4 characters in the dump.
- Response bodies contain the full API data (e.g. names, email addresses, absences). Do not paste debug output into tickets, chats or logs without reviewing it.

## Print curl instead of sending (`--curl`)

With the global `--curl` flag the CLI sends **nothing** to the API. It prints the `curl` command it would have sent and exits. The flag works with every action and can be placed anywhere on the command line.

```bash
./clockodo customers list --state inactive --curl
```

Output (credentials are your real values from `.env`):
```bash
curl --silent \
  --header 'X-ClockodoApiUser: you@example.com' \
  --header 'X-ClockodoApiKey: <your API key>' \
  --header 'X-Clockodo-External-Application: clockodo-cli/0.1.0;you@example.com' \
  --header 'Accept: application/json' \
  'https://my.clockodo.com/api/v3/customers?filter%5Bactive%5D=false&page=1&items_per_page=1000' \
  | jq .
```

- **The output contains your API key in clear text.** Do not paste it into tickets, chats or logs.
- Paginated lists print the request for page 1 only. Fetch more pages by changing `page=N`.
- The cache is bypassed (`CACHE=1` has no effect), so you always see the real request.
- `--curl` wins over `--json`: the output is always the plain curl command.
- Not supported: `absences list me` and `targethours list me` (they need a lookup request first). Pass a numeric user ID instead. `favorites start` needs an explicit ID. `entries list --me` is not supported either (use `--user <id>`), `entries summary` is not supported at all, and `entries stop` needs an explicit ID.

## Write guards

Two commands write: `favorites start` and `entries stop`. Two mechanisms keep them from firing by accident, e.g. when an AI agent drives the CLI.

### Dry run (`--dry-run`)

With the global `--dry-run` flag the CLI reports a write request instead of sending it and exits 0. Read requests still run, so lookups (e.g. the running entry for `entries stop` without an ID) behave as in a real run. The output contains no credentials.

```bash
./clockodo entries stop --dry-run
```
```text
Dry run, nothing was sent:
  DELETE https://my.clockodo.com/api/v2/clock/12345
```

In `--json` mode the result is `{"dry_run": true, "request": {"method", "url", "body"}}`. `--curl` wins over `--dry-run`.

### Read-only mode (`CLOCKODO_READ_ONLY=1`)

With `CLOCKODO_READ_ONLY=1` (ad hoc or in `.env`) every write request is refused before it is sent: error on stderr, exit code 1, in `--json` mode the code `read_only`. `--curl` is refused for writes too, since it would hand out a runnable write command; `--dry-run` still works.

```bash
CLOCKODO_READ_ONLY=1 ./clockodo favorites start 12345   # Error: read-only mode …
```

The guard is enforced centrally in `lib/http.sh`, for every method except `GET`. It protects against accidents, it is no security boundary: whoever can run the CLI can also unset the variable (`CLOCKODO_READ_ONLY=0 ./clockodo …` wins over `.env`) or edit `.env`. For a real restriction, use a Clockodo account whose permissions only allow reading.

## AI agent skill

[`skills/clockodo-cli/SKILL.md`](skills/clockodo-cli/SKILL.md) teaches an AI agent (e.g. Claude Code) to use the CLI: discover commands via `describe`, call with `--json`, project with `jq` before data enters the context, dry-run writes and ask for confirmation, run `doctor` on configuration errors. Install it as a personal skill via a symlink, so it follows `upgrade`:

```bash
mkdir -p ~/.claude/skills
ln -s "$(pwd)/skills/clockodo-cli" ~/.claude/skills/clockodo-cli   # run inside the repo directory
```

The skill expects `clockodo` on the `PATH` (see [Call `clockodo` from anywhere](#call-clockodo-from-anywhere)). For an agent that should only read, also set `CLOCKODO_READ_ONLY=1`.

## Commands

Run `./clockodo --help` for all groups and `./clockodo <group> --help` for their actions. Append `--curl` to any command to see the underlying API request.

### List favorites

```bash
./clockodo favorites list
```

### Start a favorite

**Interactive selection:**
```bash
./clockodo favorites start
```

**Directly by ID:**
```bash
./clockodo favorites start 12345
```

### Time entries

```bash
./clockodo entries list --me                                   # today, own entries
./clockodo entries list --me --since 2026-09-01 --until 2026-09-30
./clockodo entries list --running                              # running clock entry
./clockodo entries list --user 12345                           # today, entries of user 12345
./clockodo entries summary                                     # today: total, start, target, delta
./clockodo entries stop                                        # stop the running entry
```

- `entries summary [--me|--user <id>] [--date YYYY-MM-DD]` sums the day incl. the running entry and compares it with the valid weekly target-hours rule (`target_seconds`, `delta_seconds`, `percent`; `null` for monthly rules or without a rule). All values are in seconds in `--json` mode. With `CACHE=1` and `--user <id>` a refresh costs a single API request (`/v2/entries`), which makes it suitable for status bars and dashboards.

- `--since` / `--until` accept a local calendar day (`YYYY-MM-DD`, `--until` includes the whole day) or a UTC timestamp (`YYYY-MM-DDTHH:MM:SSZ`). Default: today.
- `entries list` uses the enhanced list of the API (customer and project names). That variant has a stricter rate limit (300 requests per 15 minutes).

### Version

```bash
./clockodo version
```

Shows the local version and loads the published one from the `main` branch of the GitHub repository (no `.env` needed, no credentials are sent). Fails with an error if the repository cannot be reached.

### Upgrade

```bash
./clockodo upgrade --dry-run    # fetch only, report whether an update is available
./clockodo upgrade              # fast-forward to the latest main
```

Fetches `origin/main` and fast-forwards the checkout. It refuses when the checkout is not on `main`, has uncommitted changes to tracked files, or has local commits that are not on `origin/main`; nothing is merged or discarded. Untracked files such as `.env` are not touched. No `.env` needed, nothing is sent to Clockodo.
