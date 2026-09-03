# Search

Use `git grep`, not `grep -r` or `rg -uu`, for text search across a project.
`git grep` searches tracked files only, so it skips build output, vendored
dependencies, and gitignored secrets (`.env`, `*.pem`, `id_rsa*`) -- a secret
never reaches the transcript because the search never opens it.

For an untracked file, or a directory outside any git repo, fall back to a
scoped `grep`/`rg` on a specific path rather than a broad recursive one.

`grep`/`cd`/`cat` after `cd` are fine on their own -- Claude Code's built-in
read-only Bash allowlist covers both halves. Only two compound shapes force an
approval prompt regardless: `cd` then `git` (hook-execution risk in the new
directory) and `cd` then an output redirect whose target directory can't be
resolved. Prefer `git -C path grep ...` / `grep pattern path` over `cd path &&
cmd` anyway -- no `cd` means neither exception can ever apply.
