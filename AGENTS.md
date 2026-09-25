# AGENTS.md

This file provides guidance to coding agents working with code in this repository.

## Project

Fasd: command-line productivity booster that tracks files/directories used in shell commands and ranks them by "frecency" (frequency + recency) for quick access (`z`, `f`, `d`, `a`, `s` aliases). The whole program is one script: `fasd`.

The `feat-zsh-only` branch rewrites `fasd` as a **zsh-only** script (`#!/usr/bin/env zsh`). The upstream version was portable POSIX sh supporting bash/tcsh/dash/ksh. `README.md` and `INSTALL.md` describe the zsh version; when docs and code disagree, code is the source of truth.

**Target: zsh 5.5 or newer only.** Any zsh feature available in 5.5 is fine to use. Do not add compatibility code for older zsh or for other shells.

Planned fixes and the test suite design are in `docs/agent/spec/zsh-rewrite-improvements.md`.

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

Everything lives in a single `fasd()` function dispatched by a top-level `case $1`. At the bottom, the script runs `fasd --init env`, then either returns (when sourced, detected via `$ZSH_EVAL_CONTEXT`) or calls `fasd "$@"` (when executed). Internal operations recurse by calling `fasd --<op>`.

Internal subcommands:

- `--init <modules...>`: `env` sets `_FASD_*` defaults (sourcing `/etc/fasdrc` and `~/.fasdrc` first) and picks an awk. Other modules (`auto`, `posix-alias`, `zsh-hook`, `zsh-ccomp[-install]`, `zsh-wcomp[-install]`) **print** shell code for the user to `eval` in `.zshrc`; they do not run it.
- `--proc`: invoked from the `preexec` hook with the tokenized command line. Applies `_FASD_BLACKLIST` / `_FASD_SHIFT` (e.g. strip `sudo`) / `_FASD_IGNORE`, then `--add`s the arguments.
- `--add` / `--delete`: under a lock (`--lock`, `zsystem flock` on `$_FASD_DATA.lock`, gives up after 1 s), rewrite the database through awk into a `mktemp` file, then `mv` it over `$_FASD_DATA` (atomic replace). Paths reach awk via `ENVIRON`, newline separated; `--add` rejects paths containing `|` or newline. Both no-op if `_FASD_RO` is set or the data file is owned by someone else.
- `--query <typ> <fnd> <mode>`: loads data from backends, filters by type (`e`/`f`/`d`), matches in 3 passes (exact glob, then case-insensitive `(#i)`, then fuzzy if `_FASD_FUZZY > 0`, allowing up to `_FASD_FUZZY` non-`/` chars between query chars). Query words are quoted with `${(b)...}`; the pattern is `*w1*...*wN[^/]#` (last word in last segment; a trailing `$` drops the `[^/]#`). Scores in awk: `rank`, `recent`, or the default frecency (`rank * frecent(last_access)` with weights 6/4/2/1 for <1h/<1d/<1w/older). Output is `score path` lines.
- `--backend <name>`: emits `path|rank|time` rows from `native` (the data file), `viminfo`, `recently-used`, `current`, `spotlight` (macOS `mdfind`), or `eval`s any other name as a custom command.
- `--word-complete-trigger`, `--complete`: tab-completion plumbing for the `,query` / `f,query` / `query,,d` word-completion syntax.
- Default branch (`*`): user-facing option parsing (`-s -l -i -e -b -B -a -d -f -r -t -R -[0-9]`), then sort/select results, `--add` the chosen path back (reinforcing it), and print or `eval "$exec"` on it.

Data file format (`$_FASD_DATA`, default `~/.fasd`): one entry per line, `path|rank|last_access_epoch`. On add, an existing rank grows by `1/rank`. When total rank exceeds `_FASD_MAX` (2000), all ranks are multiplied by 0.9 (aging).

## Gotchas

- The function sets `setopt localoptions extendedglob warncreateglobal`; declare every variable `local` (the `env` init module turns the warning off because it sets the global `_FASD_*` defaults); matching relies on zsh glob qualifiers (`#`, `(#i)`, `(#b)`) and parameter flags (`${(s: :)...}`, `${(f)...}`, `${(Q)...}`, `${p:a}`).
- awk scripts inside `--query` are double-quoted so `$prior` interpolates; `$` for awk fields must be escaped as `\$1`. Other awk blocks are single-quoted.
- Heredocs in `--init` use `<<'EOS'` (no expansion); the emitted code runs in the user's shell, not in `fasd`.
- `$exec` and custom backends are `eval`'d. Paths passed to `eval` are quoted as `\"\$res\"` to avoid code injection (see commit 6b9f524).
- `_FASD_NOW` (fixed clock) and `_FASD_NORC` (skip rc files) exist for tests.
- The top of the script checks `is-at-least 5.5` before defining anything.
