# --init, version check, completion triggers, scoping

test_zsh_version_check() { # P1-6
  local out
  if [[ $MODE == exec ]]; then
    mkdir -p $T/zdot
    print 'ZSH_VERSION=5.4' >| $T/zdot/.zshenv
    out=$(ZDOTDIR=$T/zdot $FASD_BIN --version 2>&1)
    assert_eq 1 $? "status"
    assert_eq "fasd: zsh >= 5.5 required" "$out"
  else
    out=$(zsh -fc 'ZSH_VERSION=5.4; source $1; print "st=$? fn=$+functions[fasd]"' \
      zsh $FASD_BIN 2>&1)
    assert_eq "fasd: zsh >= 5.5 required"$'\n'"st=1 fn=0" "$out"
  fi
}

test_init_modules_syntax() {
  local m
  for m in env auto posix-alias zsh-hook zsh-ccomp zsh-ccomp-install \
      zsh-wcomp zsh-wcomp-install; do
    fasd --init $m >| $T/init.zsh
    assert_status 0 zsh -n $T/init.zsh
  done
}

test_init_auto() {
  ln -s $FASD_BIN $T/bin/fasd
  local load='true'
  [[ $MODE == source ]] && load='source $1'
  local out
  out=$(zsh -fc "$load"'
    eval "$(fasd --init auto)"
    print -r -- "hooks: $preexec_functions"
    for a in z f d a s sd sf zz; do (( $+aliases[$a] )) || print -r -- "missing alias $a"; done
    _fasd_preexec "" "vim $2" "vim $2"
  ' zsh $FASD_BIN $T/tree/file.txt 2>&1)
  assert_eq "hooks: _fasd_preexec" "$out"
  assert_match "$T/tree/file.txt\\|1\\|<->" "$(db)" "hook adds the argument"
}

test_word_complete_trigger() {
  local t=_c
  assert_eq "_c e ,q" "$(fasd --word-complete-trigger $t ,q)"
  assert_eq "_c f ,q" "$(fasd --word-complete-trigger $t f,q)"
  assert_eq "_c d ,q" "$(fasd --word-complete-trigger $t d,q)"
  assert_eq "_c e q,," "$(fasd --word-complete-trigger $t q,,)"
  assert_eq "_c f q,," "$(fasd --word-complete-trigger $t q,,f)"
  assert_eq "_c d q,," "$(fasd --word-complete-trigger $t q,,d)"
  assert_eq "" "$(fasd --word-complete-trigger $t q)"
}

test_word_complete_results() {
  [[ $MODE == source ]] || skip "needs the emitted completion functions"
  export _FASD_NOW=1000
  mkdir -p $T/tree/foo/sub
  : >| $T/tree/foo/sub/foo.go
  db_write "$T/tree/foo|1|1000" "$T/tree/foo/sub|5|1000" "$T/tree/foo/sub/foo.go|3|1000"
  compdef() { :; }
  eval "$(fasd --init zsh-wcomp)"
  local -A compstate
  compadd() { print -rl -- "${@[${@[(i)--]}+1,-1]}"; }
  assert_eq "$T/tree/foo" "$(_fasd_zsh_word_complete d ,foo)" "d, lists dirs only"
  assert_eq "$T/tree/foo/sub/foo.go" "$(_fasd_zsh_word_complete f foo.go)" "f, lists files only"
  assert_eq "$T/tree/foo/sub/foo.go"$'\n'"$T/tree/foo" "$(_fasd_zsh_word_complete e ,foo)" \
    "e lists both, best first"
}

test_command_complete() {
  print -r -- "$T/tree/alpha|1|1" >| $_FASD_DATA
  assert_eq "$T/tree/alpha" "$(fasd --complete 'fasd -d alp')"
}

test_only_fasd_functions_defined() {
  [[ $MODE == source ]] || skip "sourced mode only"
  local -a before after new
  before=(${(k)functions})
  source $FASD_BIN
  after=(${(k)functions})
  new=(${after:|before})
  local fn
  for fn in $new; do
    case $fn in
      fasd|_fasd_*|is-at-least) ;;
      *) _fail "unexpected function defined by sourcing fasd" "$fn" ;;
    esac
  done
}

test_function_line_counts() {
  [[ $MODE == source ]] || skip "sourced mode only"
  local fn n
  for fn in ${(k)functions}; do
    case $fn in
      fasd|_fasd_*) ;;
      *) continue ;;
    esac
    [[ $fn == _fasd_init_code ]] && continue # mostly heredoc text
    n=$(functions -- $fn | wc -l)
    (( n <= 80 )) || _fail "$fn is $n lines (> 80)"
  done
}

test_no_global_leaks() { # P1-4
  [[ $MODE == source ]] || skip "sourced mode only"
  local -a before after fbefore fafter leaked
  mkdir -p $T/tree/alp2
  print -rl -- "$T/tree/alpha|2|1" "$T/tree/alp2|1|1" >| $_FASD_DATA
  before=(${(k)parameters})
  fbefore=(${(k)functions})

  fasd -A $T/tree/Mixed
  fasd -d -2 a >/dev/null
  fasd -l a >/dev/null
  fasd -s -t >/dev/null
  fasd a >/dev/null
  fasd -e : a
  print 1 | fasd -i alp >/dev/null 2>&1
  fasd --backend current >/dev/null
  fasd --proc vim file.txt
  fasd --word-complete-trigger _c ,a >/dev/null
  fasd --complete 'fasd -d a' >/dev/null
  fasd -h 2>/dev/null
  fasd --version >/dev/null
  fasd -D $T/tree/Mixed

  after=(${(k)parameters})
  fafter=(${(k)functions})
  leaked=(${after:|before})
  leaked=(${leaked:#_FASD_*})
  assert_eq "" "${(o)leaked}" "new global parameters"
  fafter=(${fafter:|fbefore})
  assert_eq "" "${(o)fafter}" "new functions"
  assert_eq "" "$(grep -s 'created globally' $_FASD_SINK)" "warncreateglobal warnings"
}
