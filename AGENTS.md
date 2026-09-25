# AGENTS.md

This file provides guidance to coding agents working with code in this repository.

## Project

Fasd: command-line productivity booster that tracks files/directories used in shell commands and ranks them by "frecency" (frequency + recency) for quick access (`z`, `f`, `d`, `a`, `s` aliases). The whole program is one script: `fasd`.

The repo is also a zsh plugin (`zinit load sthaha/fasd`): `fasd.plugin.zsh` sources `fasd` from the clone and caches the output of `fasd --init <modules>` in `$ZSH_CACHE_DIR/fasd-init-cache`. The cache is regenerated when `fasd` is newer. If you change the emitted init code, the plugin picks it up through that mtime check. Tests: `test/plugin.test.zsh`.

This fork rewrites `fasd` as a **zsh-only** script (`#!/usr/bin/env zsh`). The upstream version was portable POSIX sh supporting bash/tcsh/dash/ksh. `README.md` and `INSTALL.md` describe the zsh version; when docs and code disagree, code is the source of truth.

**Target: zsh 5.5 or newer only.** Any zsh feature available in 5.5 is fine to use. Do not add compatibility code for older zsh or for other shells.

Design history lives in `docs/agent/spec/`: `zsh-rewrite-improvements.md` (bug fixes + test suite) and `fasd-function-refactor.md` (split into `_fasd_*` helpers). Both are implemented.

## Commands

No build step.

```sh
make test                     # zsh -n fasd, then the whole test suite (TAP)
make test T=matching          # run test/matching.test.zsh only
_FASD_AWK=gawk make test      # run the suite with a specific awk
make install                  # install fasd to /usr/local
PREFIX=$HOME make install     # install to $HOME
```

There are no man pages; README.md is the user documentation.

Tests live in `test/`: `run.zsh` is the runner (plain zsh, no deps), `*.test.zsh` define `test_*` functions, `fixtures/` holds backend input files. Every test runs twice: executing `./fasd` (`MODE=exec`) and with `fasd` sourced (`MODE=source`). Each test gets a fresh temp `HOME`, `_FASD_DATA`, `_FASD_SINK` and a small tree in `$T/tree` (cwd). Use `export` for `_FASD_*` settings so exec mode sees them, and `_FASD_NOW` for a fixed clock.

Manual testing against an isolated database (avoid touching `~/.fasd`):

```sh
export _FASD_DATA=$(mktemp) _FASD_SINK=/dev/stderr
./fasd -A /tmp /usr/local/bin    # add entries
./fasd -s                        # list with scores
./fasd -d loc                    # query directories
./fasd --init auto               # print generated shell init code
zsh -n fasd                      # syntax check
```

`_FASD_SINK` defaults to `/dev/null`, so errors are silently swallowed; point it at stderr or a file when debugging.

## Architecture

`fasd()` is a thin dispatcher (under 30 lines): `setopt localoptions extendedglob warncreateglobal`, then a top-level `case $1` that calls one `_fasd_<op>` helper per public op. All helpers are top-level functions defined before `fasd()`, inherit `fasd()`'s `setopt` (they must not `setopt` themselves, except `_fasd_init_env`), and declare every variable `local`. At the bottom, the script runs `fasd --init env`, then either returns (when sourced, detected via `$ZSH_EVAL_CONTEXT`) or calls `fasd "$@"` (when executed). Internal operations call the `_fasd_*` helpers directly instead of recursing through `fasd --<op>`.

Two helpers pass a value back to their caller through zsh's dynamic scoping instead of `stdout`/return code, so the caller must declare the variable `local` itself before calling:
- `_fasd_lock` sets the caller's `$lockfd` (from `zsystem flock`).
- `_fasd_query_patterns` fills the caller's `local -a pats` with the match patterns.
- `_fasd_parse_args` / `_fasd_parse_opt` (used only by `_fasd_main`) fill a larger set of the caller's locals the same way: `fnd`, `last`, `_FASD_BACKENDS`, `comp`, `exec`, `show`, `lst`, `interactive`, `mode`, `typ`, `r`, `_fasd_i`, `i`, plus the internal control-flow locals `_fasd_rc` and `_fasd_shift2`.

Helper functions:

- `_fasd_init <modules...>`: loops over `--init` modules, calling `_fasd_init_env` for `env` and `_fasd_init_code <module>` for the rest.
- `_fasd_init_env`: sets `_FASD_*` defaults (sourcing `/etc/fasdrc` and `~/.fasdrc` first) and picks an awk. Keeps the `nowarncreateglobal` wrapping since it intentionally sets globals.
- `_fasd_init_code <module>`: one `case` that **prints** the shell code for a module (`auto`, `posix-alias`, `zsh-hook`, `zsh-ccomp[-install]`, `zsh-wcomp[-install]`) via unexpanded heredocs, for the user to `eval` in `.zshrc`; it does not run the code itself. The longest function in the file (mostly heredoc text), and exempt from the 80-line limit the other helpers follow.
- `_fasd_writable`: returns 0 when writing to `$_FASD_DATA` is allowed (replaces 3 copies of the same guard).
- `_fasd_proc`: invoked from the `preexec` hook with the tokenized command line. Applies `_FASD_BLACKLIST` / `_FASD_SHIFT` (e.g. strip `sudo`) / `_FASD_IGNORE`, then calls `_fasd_add` with the remaining arguments.
- `_fasd_lock`: `zsystem flock` on `$_FASD_DATA.lock`, gives up after 1 s.
- `_fasd_db_rewrite <awk-program> [awk -v args...]`: shared body of add/delete. Takes the lock, creates the data file if missing, `mktemp`s a temp file, runs `$_FASD_AWK -F"|"` over `$_FASD_DATA` into it, then `mv`s it over `$_FASD_DATA` on success or `rm`s it on failure, unlocking in an `always` block. The caller exports its path list through `_fasd_list`, passed via `ENVIRON`.
- `_fasd_add` / `_fasd_delete`: path validation (and the PWD filter, for add) plus the add/delete awk program, dispatched through `_fasd_db_rewrite`. `--add` rejects paths containing `|` or newline.
- `_fasd_query <typ> <fnd> <mode>`: orchestrates `_fasd_query_load` (raw `path|rank|time` rows from the backends), `_fasd_query_patterns` (builds the 3 match passes: exact glob, then case-insensitive `(#i)`, then fuzzy if `_FASD_FUZZY > 0`, allowing up to `_FASD_FUZZY` non-`/` chars between query chars; query words are quoted with `${(b)...}`, pattern `*w1*...*wN[^/]#`, last word in last segment, a trailing `$` drops the `[^/]#`), and `_fasd_query_score` (frecency awk: `rank`, `recent`, or the default `rank * frecent(last_access)` with weights 6/4/2/1 for <1h/<1d/<1w/older; reads matched lines on stdin, prints `score path` lines).
- `_fasd_backend <name>`: emits `path|rank|time` rows from `native` (the data file), `viminfo`, `recently-used`, `current`, `spotlight` (macOS `mdfind`), or `eval`s any other name as a custom command.
- `_fasd_word_complete_trigger`: tab-completion plumbing for the `,query` / `f,query` / `query,,d` word-completion syntax (`--word-complete-trigger`). `--complete` is handled inline in `_fasd_parse_args`.
- `_fasd_main`: the old default `*` branch. Declares the locals `_fasd_parse_args`/`_fasd_select` fill dynamically, calls `_fasd_parse_args "$@"` (user-facing option parsing: `-s -l -i -e -b -B -a -d -f -r -t -R -[0-9]`, plus the `--query`/`--add`/`--delete`/`--version`/`--complete` pass-throughs; delegates single-token parsing to `_fasd_parse_opt`, and help text to `_fasd_usage`), then `_fasd_select` (sort/select results, `_fasd_add` the chosen path back to reinforce it, print or `eval "$exec"` on it).

Data file format (`$_FASD_DATA`, default `~/.fasd`): one entry per line, `path|rank|last_access_epoch`. On add, an existing rank grows by `1/rank`. When total rank exceeds `_FASD_MAX` (2000), all ranks are multiplied by 0.9 (aging).

## Gotchas

- The function sets `setopt localoptions extendedglob warncreateglobal`; declare every variable `local` (the `env` init module turns the warning off because it sets the global `_FASD_*` defaults); matching relies on zsh glob qualifiers (`#`, `(#i)`, `(#b)`) and parameter flags (`${(s: :)...}`, `${(f)...}`, `${(Q)...}`, `${p:a}`).
- awk scripts inside `--query` are double-quoted so `$prior` interpolates; `$` for awk fields must be escaped as `\$1`. Other awk blocks are single-quoted.
- Heredocs in `--init` use `<<'EOS'` (no expansion); the emitted code runs in the user's shell, not in `fasd`.
- `$exec` and custom backends are `eval`'d. Paths passed to `eval` are quoted as `\"\$res\"` to avoid code injection (see commit 6b9f524).
- `_FASD_NOW` (fixed clock) and `_FASD_NORC` (skip rc files) exist for tests.
- The top of the script checks `is-at-least 5.5` before defining anything.
