# Contributing

Thanks for your interest! Bug reports and pull requests are welcome.

## Before you start

- Open an issue first for larger changes (new command group, breaking CLI change).
- Read [CLAUDE.md](CLAUDE.md): it documents the project structure and conventions (modular Bash, `curl` only in `lib/http.sh`, `--json` / `--curl` support for every action, `contract.json` kept in sync).

## Development

- Requirements: Bash, `curl`, `jq`. No other runtime.
- Copy `.env.example` to `.env` and fill in your Clockodo API credentials. Never commit `.env`.
- Syntax check: `bash -n clockodo lib/*.sh commands/*/*.sh`
- Use `--dry-run` or `CLOCKODO_READ_ONLY=1` while testing write actions against a real account.

## Pull requests

- Keep them focused: one change per PR.
- Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:` …).
- Update help texts, `contract.json` and the README when behavior changes.
- Do not include API keys, `--curl` output or `DEBUG` dumps in issues or PRs: they contain your credentials.

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
