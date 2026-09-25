# fasd.plugin.zsh: loading through a plugin manager

export _FASD_NOW=1000

# load the plugin in a clean zsh and run $1 afterwards
load_plugin() {
  ZSH_CACHE_DIR=$T/cache zsh -f -c "source ${FASD_BIN:h}/fasd.plugin.zsh; $1"
}

test_plugin_loads() {
  [[ $MODE == source ]] || skip "runs its own zsh; once is enough"
  local out
  out=$(load_plugin 'whence -w fasd; print -r -- $preexec_functions; alias z j; whence -w _fasd_plugin_init')
  assert_match "*fasd: function*" "$out" "fasd sourced as a function"
  assert_match "*_fasd_preexec*" "$out" "preexec hook registered"
  assert_match "*z='fasd_cd -d'*" "$out" "init aliases defined"
  assert_match "*j='fasd_cd -d'*" "$out" "plugin aliases defined"
  assert_match "*_fasd_plugin_init: none*" "$out" "init helper removed"
}

test_plugin_hook_records() {
  [[ $MODE == source ]] || skip "runs its own zsh; once is enough"
  load_plugin '_fasd_preexec "vim file.txt" "vim file.txt"'
  assert_eq "$T/tree/file.txt|1|1000" "$(db)"
}

test_plugin_init_cache() {
  [[ $MODE == source ]] || skip "runs its own zsh; once is enough"
  local cache=$T/cache/fasd-init-cache
  load_plugin :
  assert_match "*add-zsh-hook preexec _fasd_preexec*" "$(<$cache)" "cache holds expanded init code"

  print -r -- 'alias fasd_cache_marker=1' >| $cache
  touch -t 203001010000 $cache
  assert_match "*fasd_cache_marker*" "$(load_plugin 'alias')" "fresh cache reused"

  touch -t 200001010000 $cache
  load_plugin :
  assert_match "*_fasd_preexec*" "$(<$cache)" "stale cache regenerated"
}
