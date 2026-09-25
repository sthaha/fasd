Fasd is a self-contained zsh script that can be either sourced or executed. It
requires zsh 5.5 or newer. A Makefile is provided to install `fasd` to
desired places.


System-wide install:

    make install

Install to $HOME:

    PREFIX=$HOME make install

Or alternatively you can just copy `fasd` to anywhere you like.

To get fasd working in zsh, some initialization code must be run. Put the line
below in your `.zshrc`.

    eval "$(fasd --init auto)"

This will setup a command hook (zsh `preexec`) that executes on every command
and tab completion.

If you want more control over what gets into your shell environment, you can
pass customized set of arguments to `fasd --init`.

    zsh-hook             # define _fasd_preexec and add it to zsh preexec array
    zsh-ccomp            # zsh command mode completion definitions
    zsh-ccomp-install    # setup command mode completion for zsh
    zsh-wcomp            # zsh word mode completion definitions
    zsh-wcomp-install    # setup word mode completion for zsh
    posix-alias          # define the default aliases and the fasd_cd function

Example for a minimal zsh setup (no tab completion):

    eval "$(fasd --init posix-alias zsh-hook)"

Note that this method will slightly increase your shell start-up time, since
calling binaries has overhead. You can cache fasd init code if you want minimal
overhead. Example code (to be put into .zshrc):

    fasd_cache="$HOME/.fasd-init-zsh"
    if [[ "$(command -v fasd)" -nt "$fasd_cache" || ! -s "$fasd_cache" ]]; then
      fasd --init posix-alias zsh-hook zsh-ccomp zsh-ccomp-install \
    zsh-wcomp zsh-wcomp-install >| "$fasd_cache"
    fi
    source "$fasd_cache"
    unset fasd_cache

Optionally, you can also source `fasd` if you want `fasd` to be a shell
function instead of an executable.

You can tweak initialization code. For instance, if you want to use "c"
instead of "z" to do directory jumping. You run the code below:

    # function to execute built-in cd
    fasd_cd() {
      if [ $# -le 1 ]; then
        fasd "$@"
      else
        local _fasd_ret="$(fasd -e 'printf %s' "$@")"
        [ -z "$_fasd_ret" ] && return
        [ -d "$_fasd_ret" ] && cd "$_fasd_ret" || printf '%s\n' "$_fasd_ret"
      fi
    }
    alias c='fasd_cd -d'

To run the test suite:

    make test
