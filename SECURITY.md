# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's private reporting instead:
<https://github.com/hdrees/clockodo-cli/security/advisories/new>

Include what you found, how to reproduce it and the affected version (`./clockodo version`). You can expect a first reply within a few days.

## Handling credentials

- `--curl` and `DEBUG=1` output contain your Clockodo API key (`DEBUG` masks it to 4 characters, `--curl` does not). Do not paste either into issues, chats or logs.
- If a key was exposed, rotate it in your Clockodo account.
- `.env` must never be committed.
