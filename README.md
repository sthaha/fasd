# Fasd

Fasd (pronounced similar to "fast") is a command-line productivity booster.
Fasd offers quick access to files and directories in zsh. It is
inspired by tools like [autojump](https://github.com/joelthelion/autojump),
[z](http://github.com/rupa/z) and [v](https://github.com/rupa/v). Fasd keeps
track of files and directories you have accessed, so that you can quickly
reference them in the command line.

The name fasd comes from the default suggested aliases `f`(files),
`a`(files/directories), `s`(show/search/select), `d`(directories).

Fasd ranks files and directories by "frecency," that is, by both "frequency" and
"recency." The term "frecency" was first coined by Mozilla and used in Firefox
([link](https://developer.mozilla.org/en/The_Places_frecency_algorithm)).

# Credits

Fasd was created by **Wei Dai** ([clvv/fasd](https://github.com/clvv/fasd)),
who wrote nearly all of the original tool. It started from code in
[z](https://github.com/rupa/z) by **rupa deadwyler**, whose
[v](https://github.com/rupa/v) also inspired it. Thanks also to the upstream
contributors Daniel Hahler, Benoit Cote-Jodoin, Ben O'Hara and Patrick.

This repository ([sthaha/fasd](https://github.com/sthaha/fasd)) is a fork that
rewrites fasd for zsh 5.5+ only, with a test suite and a zsh plugin. The design,
the command-line interface and the frecency algorithm are Wei Dai's work.

# Introduction

If you use your shell to navigate and launch applications, fasd can help you do
it more efficiently. With fasd, you can open files regardless of which
directory you are in. Just with a few key strings, fasd can find a "frecent"
file or directory and open it with command you specify. Below are some
hypothetical situations, where you can type in the command on the left and fasd
will "expand" your command into the right side. Pretty magic, huh?

```
  v def conf       =>     vim /some/awkward/path/to/type/default.conf
  j abc            =>     cd /hell/of/a/awkward/path/to/get/to/abcdef
  m movie          =>     mplayer /whatever/whatever/whatever/awesome_movie.mp4
  o eng paper      =>     xdg-open /you/dont/remember/where/english_paper.pdf
  vim `f rc lo`    =>     vim /etc/rc.local
  vim `f rc conf`  =>     vim /etc/rc.conf
```

Fasd comes with some useful aliases by default:

```sh
alias a='fasd -a'        # any
alias s='fasd -si'       # show / search / select
alias d='fasd -d'        # directory
alias f='fasd -f'        # file
alias sd='fasd -sid'     # interactive directory selection
alias sf='fasd -sif'     # interactive file selection
alias z='fasd_cd -d'     # cd, same functionality as j in autojump
alias zz='fasd_cd -d -i' # cd with interactive selection
```

Fasd will smartly detect when to display a list of files or just the best
match. For instance, when you call fasd in a subshell with some search
parameters, fasd will only return the best match. This enables you to do:

```sh
mv update.html `d www`
cp `f mov` .
```

# Install

Fasd is available in various package managers. Please check
[the wiki page](https://github.com/clvv/fasd/wiki/Installing-via-Package-Managers)
for an up-to-date list.

You can also manually obtain a copy of fasd.

Download fasd 1.0.1 from GitHub:
[zip](https://github.com/clvv/fasd/zipball/1.0.1),
[tar.gz](https://github.com/clvv/fasd/tarball/1.0.1).

Fasd is a self-contained zsh script that can be either sourced or executed.
It requires zsh 5.5 or newer. A Makefile is provided to install `fasd` to
desired places.

With [zinit](https://github.com/zdharma-continuum/zinit) (or any plugin
manager that supports the Zsh Plugin Standard), no install step is needed:

    zinit load sthaha/fasd

`fasd.plugin.zsh` sources `fasd` from the clone, so fasd runs as a shell
function and the command hook does not start a process for every command.
The expanded init code is cached in `$ZSH_CACHE_DIR/fasd-init-cache` and
regenerated when `fasd` changes. The plugin also defines the aliases
`v` (open file in `$EDITOR`), `o` (open with `open`/`xdg-open`) and
`j` (same as `z`).

System-wide install:

    make install

Install to $HOME:

    PREFIX=$HOME make install

Or alternatively you can just copy `fasd` to anywhere you like (preferably
under some directory in `$PATH`).

To get fasd working in a shell, some initialization code must be run. Put the
line below in your shell rc.

```sh
eval "$(fasd --init auto)"
```

This will setup a command hook (zsh `preexec`) that executes on every command
and tab completion.

If you want more control over what gets into your shell environment, you can
pass customized set of arguments to `fasd --init`.

```
zsh-hook             # define _fasd_preexec and add it to zsh preexec array
zsh-ccomp            # zsh command mode completion definitions
zsh-ccomp-install    # setup command mode completion for zsh
zsh-wcomp            # zsh word mode completion definitions
zsh-wcomp-install    # setup word mode completion for zsh
posix-alias          # define the default aliases and the fasd_cd function
```

Example for a minimal zsh setup (no tab completion):

```sh
eval "$(fasd --init posix-alias zsh-hook)"
```

Note that this method will slightly increase your shell start-up time, since
calling binaries has overhead. You can cache fasd init code if you want minimal
overhead. Example code (to be put into .zshrc):

```sh
fasd_cache="$HOME/.fasd-init-zsh"
if [[ "$(command -v fasd)" -nt "$fasd_cache" || ! -s "$fasd_cache" ]]; then
  fasd --init posix-alias zsh-hook zsh-ccomp zsh-ccomp-install \
    zsh-wcomp zsh-wcomp-install >| "$fasd_cache"
fi
source "$fasd_cache"
unset fasd_cache
```

Optionally, you can also source `fasd` if you want `fasd` to be a shell
function instead of an executable.

You can tweak initialization code. For instance, if you want to use "c"
instead of "z" to do directory jumping, you can use the alias below:

```sh
alias c='fasd_cd -d' # function fasd_cd is defined in posix-alias
```

After you first installed fasd, open some files (with any program) or `cd`
around in your shell. Then try some examples below.

# Examples

```sh
f foo           # list frecent files matching foo
a foo bar       # list frecent files and directories matching foo and bar
f js$           # list frecent files that ends in js
f -e vim foo    # run vim on the most frecent file matching foo
mplayer `f bar` # run mplayer on the most frecent file matching bar
z foo           # cd into the most frecent directory matching foo
open `sf pdf`   # interactively select a file matching pdf and launch `open`
```

You should add your own aliases to fully utilize the power of fasd. Here are
some examples to get you started:

```sh
alias v='f -e vim' # quick opening files with vim
alias m='f -e mplayer' # quick opening files with mplayer
alias o='a -e xdg-open' # quick opening files with xdg-open
```

You could select an entry in the list of matching files.

# Matching

Fasd has three matching modes: default, case-insensitive, and fuzzy.

For a given set of queries (the set of command-line arguments passed to fasd),
a path is a match if and only if:

1. Queries match the path *in order*.
2. The last query matches the *last segment* of the path.

If no match is found, fasd will try the same process ignoring case. If still no
match is found, fasd will allow extra characters to be placed between query
characters for fuzzy matching.

Tips:

* If you want your last query not to match the last segment of the path, append
  `/` as the last query.
* If you want your last query to match the end of the filename, append `$` to
  the last query.
* Query characters are matched literally: `*`, `?`, `[`, `(` and other glob
  characters have no special meaning.
* `$_FASD_FUZZY` limits how many characters fuzzy matching may skip between two
  query characters. Fuzzy matching never crosses a `/`.

# How It Works

When you run fasd init code or source `fasd`, fasd adds a hook which will be
executed whenever you execute a command. The hook will scan your commands'
arguments and determine if any of them refer to existing files or directories.
If yes, fasd will add them to the database.

The database (`$_FASD_DATA`) has one `path|rank|last_access` line per entry.
Paths that contain `|` or a newline cannot be stored and are ignored. Updates
are serialized with a lock file (`$_FASD_DATA.lock`); if the lock cannot be
taken within one second, the update is skipped so the prompt never blocks.

# Compatibility

This version of fasd is written for zsh and requires zsh 5.5 or newer; it
exits with an error on older versions. It does not support bash, tcsh or other
POSIX shells (the original POSIX version of fasd does). Besides zsh, fasd
needs `awk` (any of mawk, gawk, BSD awk), `sed`, `sort`, `tr` and `mktemp`.

On other shells you can still execute `fasd` as a command (for instance
`fasd -A path` or `` cd "$(fasd -d foo)" ``) as long as zsh is installed, but
there is no automatic tracking.

# Synopsis

    fasd [options] [query ...]
    [f|a|s|d|z] [options] [query ...]
      options:
        -s         list paths with scores
        -l         list paths without scores
        -i         interactive mode
        -e <cmd>   set command to execute on the result file
        -b <name>  only use <name> backend
        -B <name>  add additional backend <name>
        -a         match files and directories
        -d         match directories only
        -f         match files only
        -r         match by rank only
        -t         match by recent access only
        -R         reverse listing order
        -h         show a brief help message
        -[0-9]     select the nth entry

    fasd [-A|-D] [paths ...]
        -A    add paths
        -D    delete paths

# Tab Completion

Fasd offers two completion modes for zsh, command mode completion and word
mode completion.

Command mode completion is just like completion for any other commands. It is
triggered when you hit tab on a `fasd` command or its aliases. Under this mode
your queries can be separated by a space. Tip: if you find that the completion
result overwrites your queries, type an extra space before you hit tab.

Word mode completion can be triggered on *any* command. Word completion is
triggered by any command line argument that starts with `,` (all), `f,`
(files), or `d,` (directories), or that ends with `,,` (all), `,,f` (files), or
`,,d` (directories). Examples:

    $ vim ,rc,lo<Tab>
    $ vim /etc/rc.local

    $ mv index.html d,www<Tab>
    $ mv index.html /var/www/

There are also three zle widgets: `fasd-complete`, `fasd-complete-f`,
`fasd-complete-d`. You can bind them to keybindings you like:

```sh
bindkey '^X^A' fasd-complete    # C-x C-a to do fasd-complete (files and directories)
bindkey '^X^F' fasd-complete-f  # C-x C-f to do fasd-complete-f (only files)
bindkey '^X^D' fasd-complete-d  # C-x C-d to do fasd-complete-d (only directories)
```

# Backends

Fasd can take advantage of different sources of recent / frequent files. Most
desktop environments (such as OS X and Gtk) and some editors (such as Vim) keep
a list of accessed files. Fasd can use them as additional backends if the data
can be converted into fasd's native format. Below is a list of available
backends.

```
`spotlight`
OSX spotlight, provides entries that are changed today or opened within the
past month

`recently-used`
GTK's recently-used file (Usually available on Linux)

`current`
Provides everything in $PWD (whereever you are executing `fasd`)

`viminfo`
Vim's editing history, useful if you want to define an alias just for editing
things in vim
```

You can define your own backend by declaring a function by that name in your
`.fasdrc`. You can set default backend with `_FASD_BACKENDS` variable in our
`.fasdrc`.

Fasd can mimic [v](http://github.com/rupa/v)'s behavior by this alias:

```sh
alias v='f -t -e vim -b viminfo'
```

# Tweaks

Some shell variables that you can set before sourcing `fasd`. You can set them
in `$HOME/.fasdrc`

```
$_FASD_DATA
Path to the fasd data file, default "$HOME/.fasd".

$_FASD_BLACKLIST
List of blacklisted strings. Commands matching them will not be processed.
Default is "--help".

$_FASD_SHIFT
List of all commands that needs to be shifted, defaults to "sudo busybox".

$_FASD_IGNORE
List of all commands that will be ignored, defaults to "fasd ls echo".

$_FASD_TRACK_PWD
Fasd defaults to track your "$PWD". Set this to 0 to disable this behavior.

$_FASD_AWK
Which awk to use. Fasd can detect and use a compatible awk.

$_FASD_SINK
File to log all STDERR to, defaults to "/dev/null".

$_FASD_MAX
Max total score / weight, defaults to 2000.

$_FASD_BACKENDS
Default backends.

$_FASD_RO
If set to any non-empty string, fasd will not add or delete entries from
database. You can set and export this variable from command line.

$_FASD_FUZZY
Level of "fuzziness" when doing fuzzy matching. More precisely, the number of
characters that can be skipped to generate a match. Set to empty or 0 to
disable fuzzy matching. Default value is 2.

$_FASD_VIMINFO
Path to .viminfo file for viminfo backend, defaults to "$HOME/.viminfo"

$_FASD_RECENTLY_USED_XBEL
Path to XDG recently-used.xbel file for recently-used backend, defaults to
"$HOME/.local/share/recently-used.xbel"

$_FASD_NORC
If set to any non-empty string, "/etc/fasdrc" and "$HOME/.fasdrc" are not
sourced. Set it in the environment, not in an rc file.

$_FASD_NOW
If set, used as the current time (epoch seconds) instead of the clock. Meant
for tests.

```

# Debugging

If fasd does not work as expected, please file a bug report describing the
unexpected behavior along with your OS version, shell version, awk version, sed
version, and a log file.

You can set `_FASD_SINK` in your `.fasdrc` to obtain a log.

```sh
_FASD_SINK="$HOME/.fasd.log"
```

To run the test suite (needs only zsh and the tools listed under
Compatibility):

```sh
make test              # all tests
make test T=matching   # only test/matching.test.zsh
_FASD_AWK=gawk make test
```

# COPYING

Fasd is originally written based on code from [z](https://github.com/rupa/z) by
rupa deadwyler under the WTFPL license. Most if not all of the code has been
rewritten. Fasd is licensed under the "MIT/X11" license.

