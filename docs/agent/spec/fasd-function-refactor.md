# Spec: split `fasd()` into per-operation functions

Status: proposed
Branch: `feat-zsh-only` (after 213c95d)
Scope: `fasd`, `AGENTS.md`, possibly `test/init.test.zsh`

## Problem

`fasd()` is a single ~610-line function with one top-level `case $1` covering
init code generation, database writes, locking, querying, backends and CLI
parsing. Consequences:

- Internal operations call back into the public entry point
  (`fasd --add`, `fasd --query`, `fasd --lock`, `fasd --backend`), so every
  internal call goes through argument dispatch again.
- `--add` and `--delete` duplicate the same guard, lock, temp file, awk and
  `mv` sequence. The "writable" guard is copied three times (`--proc`, `--add`,
  `--delete`).
- `--query` (~100 lines) mixes data loading, pattern building, filtering and
  scoring.
- The default `*` branch (~150 lines) mixes option parsing, result selection,
  interactive prompting and output.

## Goal

A pure refactor: behavior, output, exit codes and the public CLI stay
identical, and the existing test suite passes **without changes to any
assertion**.

## Design

### Function layout

All helpers are top-level functions in `fasd`, defined before the final
`fasd --init env` line, and named `_fasd_<op>`. These names are already
used by emitted init code, so don't reuse them: `_fasd_preexec`,
`_fasd_zsh_*`, `fasd_cd`.

| Function | Replaces | Notes |
|---|---|---|
| `fasd` | whole thing | Thin dispatcher: `setopt localoptions extendedglob warncreateglobal`, then a `case $1` that calls one helper per public op. Target is under 30 lines. |
| `_fasd_init` | `--init` loop | Loops over modules. Calls `_fasd_init_env` for `env`, and `_fasd_init_code <module>` for the rest. |
| `_fasd_init_env` | `env` module | rc files, defaults, zmodload, awk detection. Keeps the `nowarncreateglobal` and `>> $_FASD_SINK` wrapping. |
| `_fasd_init_code` | the heredoc modules | One `case` that prints code for a module (`auto`, `posix-alias`, `zsh-hook`, …). Heredoc text stays byte-identical. |
| `_fasd_word_complete_trigger` | `--word-complete-trigger` | |
| `_fasd_writable` | the 3 copies of the `-O` / `_FASD_RO` guard | Returns 0 when writing is allowed. |
| `_fasd_proc` | `--proc` | Calls `_fasd_add` directly. |
| `_fasd_lock` | `--lock` | Still sets the caller's `local lockfd` through dynamic scope. Document this in a comment. |
| `_fasd_db_rewrite` | shared body of add/delete | Usage: `_fasd_db_rewrite <awk-program> [awk -v args...]`. Takes the lock, optionally creates the db, `mktemp`, runs `$_FASD_AWK` with `-F"|"` over `$_FASD_DATA` into the temp file, then `mv` on success or `rm` on failure. Unlocks in an `always` block. The caller exports the path list through `_fasd_list`, which is still passed via `ENVIRON`. |
| `_fasd_add` | `--add` | Path validation plus the PWD filter, then `_fasd_db_rewrite` with the add program. |
| `_fasd_delete` | `--delete` | |
| `_fasd_query` | `--query` | Orchestrates the three helpers below. Same signature: `<typ> <fnd> <mode>`. |
| `_fasd_query_load` | backend loading in `--query` | Prints the raw `path\|rank\|time` rows. |
| `_fasd_query_patterns` | pattern building | Fills the caller's `local -a pats` (dynamic scope), like `_fasd_lock` does for `lockfd`. |
| `_fasd_query_score` | frecency awk | Reads matched lines on stdin, takes `mode`, prints `score path`. |
| `_fasd_backend` | `--backend` | Same `case` as before. |
| `_fasd_main` | the `*` branch | Option parsing, then selection and output. May split into `_fasd_parse_args` (fills caller locals) and `_fasd_select` if that stays readable. Neither may be over 80 lines. |

Internal calls must use the helpers directly: `_fasd_add` instead of
`fasd --add`, `$(_fasd_query …)` instead of `$(fasd --query …)`, and so on.
The only exception is the early `--query|--add|--delete|-A|-D` pass-through in
the CLI parser; it may call the matching helper directly.

### Public interface (must not change)

Everything below stays exactly as it is now:
- `fasd --init …`, `--proc`, `--add`/`-A`, `--delete`/`-D`, `--query`,
  `--backend`, `--word-complete-trigger`, `--complete`, `--version`, and all
  short options.
- `fasd --lock` stays callable, because a test uses it. Route it to
  `_fasd_lock`.
- Emitted init code is unchanged. It calls `fasd --proc`, `fasd --complete`,
  `fasd -l`, `fasd -e` and `fasd --word-complete-trigger`, which are public.
- Sourced vs executed handling at the bottom of the file, and the zsh version
  check at the top.

### Options and scoping rules

- Options: `fasd()` sets `localoptions extendedglob warncreateglobal`.
  Helpers inherit those options because they are only called from `fasd()`.
  Helpers must not call `setopt` themselves, except `_fasd_init_env`, which
  keeps its `nowarncreateglobal`.
- Locals: every variable in a helper is declared `local` in that helper,
  except the documented dynamic-scope outputs `lockfd` and `pats`, which the
  caller declares.
- Helpers must not print anything the old code didn't. `stderr` handling stays
  as it is (`2>> "${_FASD_SINK:-/dev/null}"` where it was before).
- When sourced, the only functions defined are `fasd` and `_fasd_*` (plus
  `is-at-least`, which is autoloaded).

### Non-goals

- No behavior changes and no bug fixes. If you find a bug, write it down in
  the report and don't fix it.
- No changes to the awk programs, the glob patterns or the heredoc text, except
  as needed to move them between functions.
- No new config variables.

## Tests

1. The existing suite must pass unchanged with `make test`,
   `_FASD_AWK=awk make test` and `_FASD_AWK=gawk make test`. Expected
   result: 134 tests, 131 passing, 3 skipped, 0 failing.
2. If `init no_global_leaks` compares functions before and after sourcing and
   fails only because the new `_fasd_*` helpers now exist, adjust that one
   comparison. Do not weaken the check on parameter leaks.
3. Add one test to `test/init.test.zsh`, in source mode: after
   `source ./fasd`, every newly defined function matches `fasd` or `_fasd_*`
   (and optionally `is-at-least`).
4. Add one test checking the refactor goal: no function in `fasd` is longer
   than 80 lines, except `_fasd_init_code`, which is mostly heredoc text.
   Measure with `functions`/`whence -f` line counts after sourcing.

## Done when

- The `fasd()` body is under 30 lines, and no helper other than
  `_fasd_init_code` is over 80 lines.
- `zsh -n fasd` passes, and all three test runs above pass.
- `git diff` of the heredoc text is empty apart from indentation, if any. Say
  so in the report.
- `AGENTS.md` § Architecture describes the new function layout and the
  dynamic-scope outputs (`lockfd`, `pats`).
