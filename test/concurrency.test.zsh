# concurrent writers

export _FASD_NOW=1000

test_concurrent_adds() { # P2-2
  local k
  for k in {1..20}; do
    fasd -A $T/tree/alpha &
  done
  wait
  local actual="$(< $_FASD_DATA)"
  assert_match "${(b)T}/tree/alpha\\|[0-9.]##\\|1000" "$actual" "db parseable"

  # expected value: the same 20 adds, one after the other
  export _FASD_DATA=$T/sequential.db
  for k in {1..20}; do
    fasd -A $T/tree/alpha
  done
  assert_eq "$(< $_FASD_DATA)" "$actual" "no lost updates"
}

test_lock_held_skips_update() { # P2-2
  print -r -- "$T/tree/alpha|2|10" >| $_FASD_DATA
  : >| $_FASD_DATA.lock
  zsh -fc 'zmodload zsh/system; zsystem flock $1; print locked; sleep 3' \
    zsh $_FASD_DATA.lock >| $T/holder &
  local holder=$! k
  for k in {1..100}; do [[ -s $T/holder ]] && break; sleep 0.05; done
  local start=$EPOCHREALTIME
  fasd -A $T/tree/alpha
  local elapsed=$(( EPOCHREALTIME - start ))
  kill $holder 2>/dev/null
  assert_eq "$T/tree/alpha|2|10" "$(< $_FASD_DATA)" "db unchanged"
  (( elapsed < 2.5 )) || _fail "fasd -A waited ${elapsed}s for the lock"
}
