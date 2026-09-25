# Spec: zsh rewrite fixes and test suite

Status: implemented
Branch: `main`
Scope: `fasd`, `Makefile`, new `test/`, docs

## Background

`fasd` on this branch is a zsh-only rewrite of the POSIX script. No automated
tests exist, and the rewrite has already regressed behavior relative to the
README. This spec lists defects found by running the script (each with a
reproduction), proposes fixes, and defines a test suite that pins the fixes and
the documented behavior.

**Supported shell: zsh 5.5 or newer.** Fixes may use any feature available in
5.5, such as `zsystem flock`, `${(b)...}` and `(#cN,M)` globbing. Do not add
fallbacks for older zsh or for other shells.

All reproductions assume:

```sh
export _FASD_DATA=$(mktemp -u) _FASD_SINK=/dev/stderr
```

## 1. Defects

Priority: P0 = data loss / feature broken, P1 = wrong results or errors,
P2 = hygiene.

### P0-1: Database is never created on first run

`--add` runs awk against `$_FASD_DATA`. If the file does not exist, awk exits
non-zero, the temp file is discarded, and nothing is written. A new user's
database stays empty forever. `--query` also returns early when the file is
missing, even if non-native backends are configured.

```sh
rm -f "$_FASD_DATA"; ./fasd -A /tmp; cat "$_FASD_DATA"
# gawk: fatal: cannot open file ... No such file or directory
```

Fix: `[[ -e $_FASD_DATA ]] || : >| "$_FASD_DATA"` before the awk call in
`--add`. In `--query`, only require the file for the `native` backend.

### P0-2: Paths containing `|` or `\` corrupt the database

Paths are joined with `|` and passed via `awk -v list=...`. `-v` processes
backslash escapes, and `|` is also the field separator of the data file.

```sh
mkdir -p '/tmp/we|rd' '/tmp/back\slash'
./fasd -A '/tmp/we|rd' '/tmp/back\slash'; cat "$_FASD_DATA"
# rd|1|...           <- bogus entry
# /tmp/we|1|...      <- truncated path
# /tmp/backslash|1|  <- backslash lost
```

Fix:
- Pass the paths on stdin or through `ENVIRON`, both of which skip escape
  processing. Use NUL or newline as the separator, not `|`.
- Reject paths containing `|` or newline in `--add`, because the on-disk
  format cannot represent them. Changing the format is out of scope.

### P1-1: Glob metacharacters in queries error or over-match

Query words are inserted unescaped into a pattern that is then applied with
`$~pat`.

```sh
./fasd -l 'alp('   # fasd:339: bad pattern: *alp(*
./fasd -l '[b'     # fasd:339: bad pattern: *[b*
./fasd -l 'a*a'    # '*' acts as a wildcard
```

Fix: quote each word with `${(b)w}` before joining. In the fuzzy pass, quote
each character (`${(b)w[i]}`).

### P1-2: "Last query matches last path segment" rule not implemented

README § Matching says the last query term must match the last path segment,
and that a trailing `/` or `$` changes this. The rewrite only checks that terms
appear in order.

```sh
./fasd -A /tmp/beta/gamma
./fasd -dl beta     # returns /tmp/beta/gamma; README says it should not match
```

Fix: build the pattern as `*w1*w2*...*wN[^/]#` (the last word is followed only
by non-`/` characters). Handle the `$` suffix by removing the trailing `*`. A
trailing `/` query (an empty last word) turns the rule off. Apply the same
change in all three matching passes.

### P1-3: `_FASD_FUZZY` level is ignored

README: `_FASD_FUZZY` is "the number of characters that can be skipped". The
rewrite treats it as on/off, and `c[^/]#` allows unlimited skips.

Fix: use `c[^/](#c0,N)` with `N=$_FASD_FUZZY` (requires `extendedglob`, which
is already set).

### P1-4: State leaks into the user's shell when sourced

`_fasd_i` (set by `-[0-9]`) is not declared `local`, so when fasd is sourced
the value persists and changes later calls:

```sh
zsh -f -c 'source ./fasd; fasd -d -2 t >/dev/null; echo $_fasd_i'   # 2
```

Loop variables `l` (in `--query`) and `i` (in the interactive branch) are
likewise undeclared. `--backend current` declares `local path`, which shadows
zsh's special `$path` array (tied to `$PATH`).

Fix: add `_fasd_i` and `l` to the `local` declarations, rename `path` to
`entry`. Consider `setopt localoptions warncreateglobal` in `fasd()` so that
future leaks produce warnings.

### P1-5: `-B name` (separate argument) replaces backends instead of adding

`-Bname` appends to `_FASD_BACKENDS`. `-B name` overwrites it.

Fix: `_FASD_BACKENDS="$_FASD_BACKENDS ${2:?...}"`.

### P1-6: No minimum zsh version check

On zsh older than 5.5, the script fails partway through with confusing errors.

Fix: at the top of `fasd`, run `autoload -Uz is-at-least` and then
`is-at-least 5.5 || { print -u2 "fasd: zsh >= 5.5 required"; return 1 2>/dev/null || exit 1; }`.
The check must work both when the file is sourced and when it is executed.
Document the requirement in README, INSTALL and the man page.

### P2-1: Dead code and header

- `--sanitize` is defined but never called. The `zsh-hook` passes `${(z)2}`
  straight to `--proc`. Either wire it in or delete it.
- Line 1–2: the shebang line appears twice.
- `--version` hardcodes `1.0.1 (zsh-optimized)`. Put the version in one
  variable at the top of the file.

### P2-2: Lost updates under concurrent writes

`--add` does read → temp file → `mv`. Two shells running commands at the same
time can each read the old file, and the last `mv` wins. Temp-file + rename
keeps the file intact but drops increments.

Fix: take a lock around the read-modify-write with the `zsh/system` module:
`zsystem flock -t 1 "$_FASD_DATA.lock"`. If the lock cannot be acquired, skip
the update (the hook must never block the prompt).

### P2-3: Documentation describes the removed POSIX version

`README.md`, `INSTALL.md` and `fasd.1.md` document bash/tcsh/posix init modules
and `$_FASD_SHELL`, none of which exist on this branch. Update README and
INSTALL. Drop the man page (`fasd.1`, `fasd.1.md`, pandoc rule): README is the
only user documentation.

## 2. Testability changes to the script

These are needed so tests can be deterministic:

| Change | Reason |
|---|---|
| Honor `_FASD_NOW` (epoch seconds) in place of `$EPOCHSECONDS` when set | Frecency buckets (<1h/<1d/<1w) and aging depend on the current time; `EPOCHSECONDS` is read-only once `zsh/datetime` is loaded |
| Only load `~/.fasdrc` / `/etc/fasdrc` when `_FASD_NORC` is unset | Keep a developer's rc from affecting test runs |

No other hooks are required: `_FASD_DATA`, `_FASD_SINK`, `_FASD_TRACK_PWD`,
`_FASD_AWK` and `HOME` already allow isolation.

## 3. Test suite

### Framework

A plain zsh runner at `test/run.zsh` with no dependencies. Alternatives
considered:

- **zunit**: zsh-native but lightly maintained, and adds an install step.
- **bats**: bash-based. It cannot source `fasd` into the test process, which is
  exactly where P1-4 bugs appear.

The runner will:
- source each `test/*.test.zsh` file in a subshell,
- provide `setup` (fresh `HOME`, `_FASD_DATA`, `_FASD_NORC=1`,
  `_FASD_TRACK_PWD=0`, `_FASD_SINK=$tmp/sink`, and a fixture directory tree),
- provide `assert_eq`, `assert_match`, `assert_file_eq`, `assert_status`,
- print TAP output, and exit non-zero on failure.

Every behavior test runs twice: once executing `./fasd` as a script, and once
with `fasd` sourced as a function. The two modes have different scoping and
different `$ZSH_EVAL_CONTEXT` handling.

`make test` runs `zsh -n fasd`, then `zsh test/run.zsh`. `make test T=matching`
runs a single file.

### Test files and cases

`test/db.test.zsh`: database I/O
- add to a missing db file creates it (P0-1)
- add to an existing path: rank becomes `r + 1/r`, and the timestamp updates
- add a new path: rank is 1
- total rank > `_FASD_MAX` → all ranks multiplied by 0.9; next read drops
  entries with rank < 1
- nonexistent paths are ignored; relative paths are stored absolute
- quoted args (`"'foo bar'"`) are unquoted before the existence check
- paths with space, `\`, and unicode round-trip exactly (P0-2)
- a path containing `|` is rejected and the db is unchanged (P0-2)
- `-D` removes only the given paths
- `_FASD_RO=1` → add and delete are no-ops
- db owned by another user → no-op (skip unless running as root)
- awk failure leaves the original db intact and no `*.XXXXXX` temp files remain

`test/proc.test.zsh`: hook command processing
- `_FASD_BLACKLIST` token anywhere → nothing added
- `sudo busybox vim f` → `f` added (shift)
- `ls f` / `echo f` → nothing added (ignore)
- `_FASD_TRACK_PWD=1` adds `$PWD` unless `$PWD == $HOME`

`test/matching.test.zsh`: query semantics
- terms matched in order; out-of-order terms don't match
- last term must match last segment (P1-2); trailing `/` disables it;
  trailing `$` anchors to the end
- case-sensitive pass wins over the case-insensitive pass
- case-insensitive pass only runs when the case-sensitive pass finds nothing
- fuzzy only when both earlier passes are empty; respects the `_FASD_FUZZY` skip
  count (P1-3); `_FASD_FUZZY=0` disables it
- fuzzy never crosses `/`
- `(`, `[`, `*`, `?`, `#`, `~` in the query are literal and produce no error
  (P1-1)
- `-d`, `-f` and `-a` filter by type; entries for deleted paths are skipped

`test/scoring.test.zsh`: with `_FASD_NOW` fixed
- frecency weights 6/4/2/1 at the bucket boundaries (3599/3600, 86399/86400,
  604799/604800 seconds)
- `-r` ranks by rank only; `-t` by recency only
- duplicate paths from several backends: ranks summed, max timestamp kept
- `-s` output sorted ascending, `-R` reverses

`test/cli.test.zsh`: option parsing and selection
- `-l`, `-s`, `-e cmd`, `-ecmd`, `-[0-9]` selection
- `-b name` / `-bname` replace backends; `-B name` / `-Bname` append (P1-5)
- when stdout is not a TTY, a query prints the single best match and adds it
  back to the db
- a last argument that is an absolute existing path (from tab completion)
  bypasses the query when `-e` is given
- `-e` with a path containing `$(...)` or `` ` `` does not execute it
  (regression test for 6b9f524)
- `-h` prints help to stderr; `--version` prints the version
- interactive `-i`: feed the choice on stdin; invalid input returns 1

`test/backends.test.zsh`
- `viminfo`, `recently-used` using fixture files in `test/fixtures/`
- `current` lists `$PWD` entries and leaves `$path` / `$PATH` unchanged
  (P1-4)
- a custom backend string is evaluated
- `spotlight`: skip unless `mdfind` exists

`test/init.test.zsh`
- a stubbed `ZSH_VERSION=5.4` → fasd exits non-zero with the version error
  (P1-6)
- every `--init` module prints code that passes `zsh -n`
- `eval "$(fasd --init auto)"` in `zsh -f` registers `_fasd_preexec` in
  `preexec_functions`, and defines aliases `z`, `f`, `d`, `a`, `s`, `sd`, `sf`,
  `zz`
- `--word-complete-trigger` mapping: `,q` / `f,q` / `d,q` / `q,,` / `q,,f` /
  `q,,d`
- after sourcing and calling `fasd`, no new global parameters exist besides
  the `_FASD_*` config (compare `typeset +` before and after) (P1-4)

`test/concurrency.test.zsh`
- 20 background `fasd -A` on the same path → db stays parseable and the rank
  matches the expected value after P2-2 (before the fix, only parseability is
  asserted)

### CI

GitHub Actions workflow `.github/workflows/test.yml`:
- matrix: `ubuntu-latest`, `macos-latest`; awk: `gawk`, `mawk`, system `awk`
  (set via `_FASD_AWK`)
- zsh version floor: one ubuntu job runs the suite on zsh 5.5.1 built from
  source (cached), and the other jobs use the latest distro zsh. This catches
  features that need a zsh newer than 5.5.
- steps: install zsh (ubuntu), `make test`

## 4. Implementation order

1. Test runner and `_FASD_NOW` / `_FASD_NORC` hooks. Add tests for current
   correct behavior, and mark tests for known defects as `todo` in the TAP
   output.
2. P0-1, P0-2. Flip their tests from `todo` to passing.
3. P1-1 … P1-6.
4. P2 items, docs, and CI.

Each step should be its own commit, with its tests passing.

## Out of scope

- Changing the data file format.
- Restoring bash/tcsh support, or supporting zsh < 5.5.
- Performance work. A 2000-entry db queries in about 50 ms on macOS, so no
  bottleneck was observed.
