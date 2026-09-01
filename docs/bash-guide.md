# The bash in this repo, explained

Every bash idiom this repo actually uses, in one place. It is not a bash
tutorial -- it only covers what you will meet reading `lib/`, `bin/dot` and the
module hooks, so you can read any file here without guessing.

Read it top to bottom once, or jump to whatever line is confusing you.

- [The header every script starts with](#the-header-every-script-starts-with)
- [Variables and quoting](#variables-and-quoting)
- [Trimming strings](#trimming-strings)
- [Tests for strings, tests for numbers](#tests-for-strings-tests-for-numbers)
- [Exit status: 0 means success](#exit-status-0-means-success)
- [Reading things line by line](#reading-things-line-by-line)
- [Process substitution: the strangest thing here](#process-substitution-the-strangest-thing-here)
- [Arrays](#arrays)
- [Associative arrays (hash maps)](#associative-arrays-hash-maps)
- [Functions, local, and arguments](#functions-local-and-arguments)
- [Traps](#traps)
- [Why printf and not echo](#why-printf-and-not-echo)
- [Two landmines this repo has actually stepped on](#two-landmines-this-repo-has-actually-stepped-on)

---

## The header every script starts with

```bash
#!/usr/bin/env bash
set -euo pipefail
```

`#!/usr/bin/env bash` -- run this file with whichever `bash` is first on `PATH`
(rather than a hardcoded path, which differs between machines).

`set -euo pipefail` is four separate safety settings, and it is why scripts here
are much shorter than they would otherwise be:

| Flag | Meaning | Without it |
|---|---|---|
| `-e` | exit as soon as any command fails | the script carries on with broken state |
| `-u` | using an unset variable is an error | `rm -rf "$prefix/"` with an empty `prefix` |
| `-o pipefail` | a pipeline fails if **any** stage fails | `false \| sort` would count as success |

`-e` is the big one. It means you almost never have to write `if ! thing; then
exit 1; fi` -- a failing command already stops the script.

The escape hatch, for when a command is *allowed* to fail:

```bash
grep -q pattern file || true      # never mind if there is no match
```

### Defaults with `${x:-default}`

`-u` makes an unset variable fatal, so anywhere a variable is genuinely
optional you write the default inline:

```bash
DOT_DRY_RUN=${DOT_DRY_RUN:-0}     # keep the caller's value, else 0
local default=${3:-}              # third argument, or empty if not given
```

Read `${x:-y}` as "x, or y if x is unset or empty".

## Variables and quoting

**Always put double quotes round a variable.** Unquoted, bash splits the value
on spaces and expands `*` as a filename pattern:

```bash
file="My Notes.txt"
rm $file      # tries to delete "My" and "Notes.txt"
rm "$file"    # correct
```

This repo lives in `$HOME`, where paths with spaces are normal, so the rule is
absolute. The one place quotes are optional is inside `[[ ... ]]`, which does
not word-split -- you will see both there.

## Trimming strings

Bash can cut a prefix or a suffix off a string without calling out to `sed`:

| Form | Does | Example |
|---|---|---|
| `${v#pre}` | remove `pre` from the **start** | `${path#"$HOME"/}` → `.config/git/config` |
| `${v%suf}` | remove `suf` from the **end** | `${name%.sh}` → `apply` |
| `${v/a/b}` | replace the first `a` with `b` | `${p/#$HOME/\~}` → `~/.zshrc` |
| `${v//a/b}` | replace **every** `a` with `b` | `${s//\\"/\"}` |
| `${v:1:3}` | 3 characters starting at index 1 | used to strip quote marks |
| `${#v}` | the length of `v` | |

The `#` and `%` characters are meant to be visual: `#` is on the left of a US
keyboard's number row and cuts the left, `%` is on the right and cuts the right.

You will see these all over `lib/fs.sh`, mostly to turn an absolute path into a
short one for display.

## Tests for strings, tests for numbers

Two kinds of test, and this repo keeps them apart on purpose:

```bash
[[ -f $file ]]            # strings, files, patterns
(( count > 0 ))           # numbers
```

`[[ ... ]]` -- strings and files:

```bash
[[ -f $path ]]      # exists and is a regular file
[[ -d $path ]]      # exists and is a directory
[[ -e $path ]]      # exists, whatever it is
[[ -L $path ]]      # is a symlink
[[ -x $path ]]      # is executable
[[ -z $s ]]         # the string is empty
[[ -n $s ]]         # the string is not empty
[[ $a == "$b" ]]    # equal
[[ $a == pre* ]]    # matches the pattern (unquoted right side!)
[[ $a =~ ^[0-9]+$ ]]  # matches the regular expression
```

Note the difference in those last two: quoting the right-hand side turns a
pattern into a literal string. `[[ $a == "pre*" ]]` is true only for the exact
text `pre*`.

`(( ... ))` -- arithmetic. Inside it, variables need no `$`, and the result is
"true" when the number is non-zero, as in C:

```bash
(( count > 0 ))
(( DOT_N_LINKED ))          # true if the tally is not 0
count=$(( count + 1 ))      # $(( )) with a $ produces a value
```

## Exit status: 0 means success

Every command returns a number: **0 means success**, anything else is a
failure. That is backwards from most languages and is the single most important
thing to internalise.

```bash
cmd_a && cmd_b      # run cmd_b only if cmd_a succeeded
cmd_a || cmd_b      # run cmd_b only if cmd_a FAILED
cmd || true         # ignore the failure entirely
```

`$?` is the status of the command that just finished. It is fragile -- *any*
command overwrites it -- so where it matters this repo captures it on the very
first line of a function:

```bash
__dot_on_exit() {
  local status=$?          # must be first; the `if` below would clobber it
  ...
}
```

An `if` runs its body when the command **succeeds**, so a function that returns
a status reads naturally:

```bash
if module_exists "$name"; then ...     # not: if [[ $(module_exists ...) ]]
```

## Reading things line by line

The standard shape, and you will see it dozens of times here:

```bash
while IFS= read -r line; do
  echo "got: $line"
done < <(some_command)
```

Three parts, each of which is there for a reason:

- **`IFS=`** -- empty the field separator for this one command, so leading and
  trailing spaces in the line are kept instead of trimmed.
- **`-r`** -- do not treat backslashes as escapes. A path like `C:\new` should
  stay as written.
- **`read` returns non-zero at end of input**, which is what ends the loop.

`IFS=` can also *split* each line, which is how tab-separated pairs are read:

```bash
while IFS=$'\t' read -r src dst; do    # split each line on a tab
```

And for filenames, `find -print0` plus `read -d ''` separates entries with a
zero byte instead of a newline -- the one character a filename cannot contain:

```bash
while IFS= read -r -d '' path; do
  ...
done < <(find "$dir" -type f -print0)
```

## Process substitution: the strangest thing here

Two separate pieces of syntax that happen to sit next to each other.

`<(cmd)` is **process substitution**: run `cmd` and hand back something that
behaves like a filename holding its output. `< file` is ordinary input
redirection. Put together, `< <(cmd)` means "feed this loop the output of
`cmd`".

Why not the obvious `cmd | while read ...`? Because **each side of a pipe runs
in a subshell** -- a separate process -- so anything the loop assigns is thrown
away when the pipe ends:

```bash
count=0
printf 'a\nb\n' | while read -r x; do count=$((count + 1)); done
echo "$count"      # prints 0

count=0
while read -r x; do count=$((count + 1)); done < <(printf 'a\nb\n')
echo "$count"      # prints 2
```

That is the whole reason for the notation. The command inside `<(...)` is still
a subshell -- so `modules_enabled` cannot cache anything, because every caller
reads it this way and each subshell's variables die with it. Where a value must
be computed once per run, it is computed in `bin/dot` instead.

## Arrays

```bash
local -a names          # declare an array
names+=("git")          # append
"${names[@]}"           # every element, each one separately quoted
"${#names[@]}"          # how many elements
"${names[0]}"           # the first
```

Use `"${names[@]}"` with the quotes and the `@`. The variant with `*` joins
everything into one string, which is almost never what you want.

`mapfile` reads lines straight into an array, which beats appending in a loop:

```bash
mapfile -t names < <(modules_enabled)     # -t strips the trailing newlines
```

## Associative arrays (hash maps)

```bash
local -A claimed=()             # declare
claimed["$path"]=1              # set
[[ -n ${claimed[$path]:-} ]]    # "is this key present?"  (:- for -u safety)
"${!claimed[@]}"                # every KEY (the ! means keys, not values)
"${#claimed[@]}"                # how many entries
```

`lib/fs.sh:fs_orphans` uses one to answer "does any module claim this link?" in
a single lookup. Keys come out in no particular order, which is why that
function sorts them before printing.

These need bash 4 or newer -- one of the reasons this repo installs bash 5
rather than using the 3.2 that macOS ships.

## Functions, local, and arguments

```bash
greet() {
  local name=$1 greeting=${2:-Hello}    # arguments are $1, $2, ...
  printf '%s, %s!\n' "$greeting" "$name"
}
greet "Ada"
```

**Always `local`.** Without it every variable is global, and a loop counter
named `i` in one function will quietly corrupt another's.

`"$@"` is all the arguments, each one still separately quoted -- the correct way
to pass your arguments on to something else:

```bash
exec /opt/homebrew/bin/bash "$0" "$@"
```

(`"$*"` joins them into one string. Almost always a bug.)

`return` exits a function with a status; `exit` exits the whole script. A
function that answers a yes/no question returns 0 or 1 and prints nothing:

```bash
cfg_exists() { [[ -f $DOT_CONFIG ]]; }    # the test's own status is returned
```

## Traps

`trap` registers a function to run when something happens.

```bash
trap __dot_on_err ERR      # run this whenever a command fails
trap __dot_on_exit EXIT    # run this when the script ends, however it ends
```

`lib/dot.sh` uses both, and they are the reason a crash in a module hook prints
something useful:

- The **ERR** trap prints the file, line, command and status of whatever
  failed. `set -o errtrace` makes it apply inside functions too, which it does
  not by default.
- The **EXIT** trap turns the `DOT_FAILURES` tally into an exit code. That is
  what lets `fail` record a problem without stopping, so `dot doctor` reports
  every problem in one pass instead of only the first.

Inside an ERR trap, three arrays describe the call stack. `BASH_LINENO[0]` is
the line that failed and `BASH_SOURCE[1]` is the file it is in -- index 1
because index 0 is the trap handler itself.

## Why printf and not echo

`echo` differs between shells and versions: whether it interprets `\n`, what it
does with a leading `-e`, whether it adds a newline. `printf` is specified.

```bash
printf '%s\n' "$value"            # exactly the value, then one newline
printf '%s: %s\n' "$key" "$value"
```

Note that the format string is always a literal. `printf "$value"` is a bug --
a `%` in the data would be interpreted as a placeholder.

## Two landmines this repo has actually stepped on

Both cost real debugging time, and both are pinned by tests.

### 1. `cmd && printf` as the last statement in a loop

```bash
while read -r name; do
  module_exists "$name" && printf '%s\n' "$name"    # WRONG
done
```

A loop's exit status is the status of its **last** statement. If the final
iteration's test is false, the `&&` list returns 1, so the whole loop returns 1
-- and under `set -e` that kills the assignment it was feeding. One unknown
module name sorting last was enough to trigger it.

```bash
while read -r name; do
  if module_exists "$name"; then printf '%s\n' "$name"; fi    # right
done
```

### 2. `[[ ... ]] && x; exit $?`

```bash
[[ $DOT_FAILURES -gt 0 ]] && exit 1
exit $?        # WRONG: when the test is FALSE, $? is 1
```

The `&&` list itself returns 1 when its test fails, so this exited 1 on every
successful run. Capture the status first, then branch:

```bash
local status=$?
if [[ ${DOT_FAILURES:-0} -gt 0 ]]; then exit 1; fi
exit "$status"
```

---

## If you want to go further

- `shellcheck` catches most of the above automatically. `make lint` runs it.
- `bash -x script.sh` prints every command as it executes -- the fastest way to
  see what a hook actually did.
- The bash manual's own reference: `man bash`, and
  [mywiki.wooledge.org/BashPitfalls](https://mywiki.wooledge.org/BashPitfalls)
  for the long version of the landmines section.
