# Search

Use `git grep`, not `grep -r` or `rg -uu`, for text search across a project.
`git grep` only touches git-tracked files, so it never opens a gitignored
secret (`.env`, `*.pem`, `id_rsa*`) and never trips the `Read(...)` deny
rules in `settings.json` -- unlike a raw filesystem walk, which looks like it
*could* read anything under the target directory and stops to ask every time.

For an untracked file, or a directory outside any git repo, fall back to a
scoped `grep`/`rg` on a specific path rather than a broad recursive one.
