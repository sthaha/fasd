# Plugin entry point for zsh plugin managers, e.g. `zinit load sthaha/fasd`

# Zsh Plugin Standard: resolve the plugin file path reliably
0="${ZERO:-${${0:#$ZSH_ARGZERO}:-${(%):-%N}}}"
0="${${(M)0:#/*}:-$PWD/$0}"

_fasd_plugin_init() {
  local fasd_bin=${1:h}/fasd
  local cache="${ZSH_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fasd}/fasd-init-cache"
  [[ -d ${cache:h} ]] || command mkdir -p ${cache:h}

  # source fasd so the preexec hook runs in-process (no fork per command)
  source $fasd_bin || return

  # cache the expanded init code; regenerated when fasd is updated
  if [[ $fasd_bin -nt $cache || ! -s $cache ]]; then
    fasd --init posix-alias zsh-hook zsh-ccomp zsh-ccomp-install \
      zsh-wcomp zsh-wcomp-install >| $cache
  fi
  source $cache

  alias v="f -e ${EDITOR:-nvim}"
  alias o="a -e ${${commands[xdg-open]:+xdg-open}:-open}"
  alias j='fasd_cd -d'
}

_fasd_plugin_init $0
unfunction _fasd_plugin_init
