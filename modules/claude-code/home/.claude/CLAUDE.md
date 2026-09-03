# Search

Use `git grep`, not `grep -r` or `rg -uu`, for text search across a project.
`git grep` searches tracked files only, so it skips build output, vendored
dependencies, and gitignored secrets (`.env`, `*.pem`, `id_rsa*`) -- a secret
never reaches the transcript because the search never opens it.

For an untracked file, or a directory outside any git repo, fall back to a
scoped `grep`/`rg` on a specific path rather than a broad recursive one.
