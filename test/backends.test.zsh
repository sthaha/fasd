# --backend

export _FASD_NOW=1000

test_viminfo() {
  export _FASD_VIMINFO=$FIXTURES/viminfo
  assert_eq "$HOME/notes/todo.md|1|940"$'\n'"/fixture/src/main.c|1|880" \
    "$(fasd --backend viminfo)"
}

test_recently_used() {
  export _FASD_RECENTLY_USED_XBEL=$FIXTURES/recently-used.xbel
  assert_eq $'/fixture/docs/report.txt|5\n/fixture/pics/cat.png|1' \
    "$(fasd --backend recently-used)"
}

test_current() { # P1-4
  local path_before=$PATH
  local -a path_arr_before=($path)
  assert_eq "$(print -l $T/tree/{Mixed,alpha,beta,file.txt}'|1')" \
    "$(fasd --backend current | sort)"
  fasd --backend current >/dev/null
  assert_eq "$path_before" "$PATH" "\$PATH unchanged"
  assert_eq "$path_arr_before" "$path" "\$path unchanged"
  assert_eq "$T/tree/alpha" "$(fasd -l -b current alp)" "query with -b current"
}

test_current_empty_dir() {
  cd $T/tree/alpha
  assert_eq "" "$(fasd --backend current 2>&1)"
}

test_custom_backend_eval() {
  assert_eq "$T/tree/alpha|3|5" "$(fasd --backend "print -r -- '$T/tree/alpha|3|5'")"
  mkbin mybackend "echo '$T/tree/Mixed|1|1000'"
  export _FASD_BACKENDS=mybackend
  assert_eq "$T/tree/Mixed" "$(fasd -l)"
}

test_missing_db_with_other_backend() { # P0-1
  rm -f $_FASD_DATA
  mkbin mybackend "echo '$T/tree/Mixed|1|1000'"
  export _FASD_BACKENDS=mybackend
  assert_eq "$T/tree/Mixed" "$(fasd -l)"
  export _FASD_BACKENDS="native mybackend"
  assert_eq "$T/tree/Mixed" "$(fasd -l)"
  assert_eq "" "$(< $_FASD_SINK)" "no errors"
}

test_spotlight() {
  (( $+commands[mdfind] )) || skip "no mdfind"
  local out
  out=$(fasd --backend spotlight)
  assert_eq 0 $? "status"
  local l
  for l in ${(f)out}; do
    assert_match '/*\|2' "$l" || break
  done
}
