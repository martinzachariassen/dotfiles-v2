# `bin/`

One file, `bin/dot`. Engine budget.

## Three verbs, hardcoded `case`

`apply`, `config`, `doctor`. Hard limit. Anything wanting to be a fourth goes
elsewhere: a user-facing command into a module's `home/.local/bin/`, removal
into `uninstall.sh` at the root.

## What belongs here

- **Once-per-run work.** Nothing inside `modules_enabled` can memoise (it is
  read in a subshell), so warnings and validation happen at the call site here.
- **`__DOT_EXIT_WARN=0`.** This is the top level, not a hook: a warning must
  not change the exit status, or `dot doctor && ...` breaks on an orphaned link.
- **The bash-5 re-exec** into `/opt/homebrew/bin/bash`, for shells that never
  sourced Homebrew's shellenv.
- **The transcript redirect.** `apply` tees to `$DOT_STATE/logs/$DOT_RUN_ID.log`
  and prunes to 20. **`apply` only** -- `dot config` must print nothing but the
  editor's output (`tests/cli.bats`) and no doctor hook may write inside `$HOME`
  (`tests/contract.bats`), so a redirect at the top of the file fails both.
  Never under `--dry-run`: the log is the one file an apply writes that is not
  a symlink. `uninstall.sh` removes the logs and must keep agreeing that
  `logs/` is ours, or it starts leaving `$DOT_STATE` behind.

## Rules

- Match every option exactly; anything unknown is fatal. `dot apply --dry` must
  not silently apply for real.
- Phase 1 first. Turn `brew_bundle` failure into a `die` here, so the error
  names the Brewfile and not `lib/brew.sh`.
- `apply` validates up front and refuses on an unknown module
  (`modules_require_known`) or an unparseable config (`cfg_parse_problems`).
  `doctor` reports both without dying.
- The wizard never runs under `--dry-run` -- `config_generate` will not write,
  so it would ask five questions and discard the answers.
- Config is generated once and read silently after. Print overridable paths in
  `usage` rather than baking them into the heredoc.
