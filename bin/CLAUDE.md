# `bin/`

One file, `bin/dot`. Engine budget. **Three verbs, hardcoded `case`:** `apply`,
`config`, `doctor`. A fourth goes elsewhere: a user command into a module's
`home/.local/bin/`, removal into `uninstall.sh`.

## Rules

- **Once-per-run work lives here.** Nothing inside `modules_enabled` can
  memoise, so validation (`cfg_parse_problems`, then `modules_require_known`)
  runs here, once, before anything is touched. `doctor` reports both instead.
- **`__DOT_EXIT_WARN=0`.** Top level, not a hook: `dot doctor && ...` must
  survive an orphaned link.
- **Bash-5 re-exec** into `/opt/homebrew/bin/bash` stays at the top.
- **The transcript redirect belongs to `apply` only.** `dot config` must print
  nothing but the editor's output; no doctor hook may write inside `$HOME`.
  Never under `--dry-run`. `uninstall.sh` removes `logs/` and must keep
  agreeing it is ours.
- Match every option exactly; anything unknown is fatal. `dot apply --dry`
  must not apply for real.
- Phase 1 first. `brew_bundle` failure becomes a `die` here so the error names
  the Brewfile.
- The wizard never runs under `--dry-run`.
- Overridable paths are printed in `usage`, never baked into the heredoc.
