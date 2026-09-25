# option parsing and selection

export _FASD_NOW=1000000

# add "name:rank" entries (dirs relative to $T/tree), accessed just now
entries() {
  local e
  for e in "$@"; do
    mkdir -p "$T/tree/${e%%:*}"
    print -r -- "$T/tree/${e%%:*}|${e#*:}|$_FASD_NOW" >> $_FASD_DATA
  done
}

rel() { sed "s|$T/tree/||"; }

test_list() {
  entries alpha:3 alp2:2
  assert_eq $'alp2\nalpha' "$(fasd -l alp | rel)"
  assert_eq $'12 alp2\n18 alpha' "$(squeeze "$(fasd -s alp)" | rel)"
}

test_exec_option() {
  entries alpha:3 alp2:2
  assert_eq "cmd:$T/tree/alpha" "$(fasd -e 'printf cmd:%s' alp)" "-e cmd"
  assert_eq "$T/tree/alpha" "$(fasd -eecho alp)" "-ecmd"
  assert_eq "$T/tree/alp2|2|1000000"$'\n'"$T/tree/alpha|3.63333|1000000" "$(db)" "selection added back (twice)"
}

test_nth_selection() {
  entries alpha:3 alp2:2 alp3:1
  assert_eq "$T/tree/alp2" "$(fasd -2 alp)"
  assert_eq "$T/tree/alp3" "$(fasd -d -3 alp)"
}

test_backend_replace() { # -b name / -bname
  entries alpha:3
  mkbin other "echo '$T/tree/Mixed|1|$_FASD_NOW'"
  assert_eq "Mixed" "$(fasd -l -b other | rel)" "-b name"
  assert_eq "Mixed" "$(fasd -l -bother | rel)" "-bname"
}

test_backend_append() { # P1-5: -B name / -Bname
  entries alpha:3
  mkbin other "echo '$T/tree/Mixed|1|$_FASD_NOW'"
  assert_eq $'Mixed\nalpha' "$(fasd -l -B other | rel)" "-B name"
  assert_eq $'Mixed\nalpha' "$(fasd -l -Bother | rel)" "-Bname"
}

test_non_tty_prints_best_and_adds() {
  entries alpha:3 alp2:2
  assert_eq "$T/tree/alpha" "$(fasd alp)"
  assert_eq "$T/tree/alp2|2|1000000"$'\n'"$T/tree/alpha|3.33333|1000000" "$(db)"
}

test_no_match_prints_nothing() {
  entries alpha:3
  assert_eq "" "$(fasd zzz)"
  assert_eq "$T/tree/alpha|3|1000000" "$(db)"
}

test_completed_path_bypasses_query() {
  entries alpha:3
  assert_eq "$T/tree/Mixed" "$(fasd -e echo $T/tree/Mixed)"
  assert_eq "$T/tree/alpha|3|1000000" "$(db)" "db unchanged"
}

test_exec_no_code_injection() { # regression for 6b9f524
  local d1='inj$(touch pwned1)' d2='inj`touch pwned2`'
  entries "$d1:3" "$d2:2"
  assert_eq "$T/tree/$d1" "$(fasd -e echo inj)" "query path"
  assert_eq "$T/tree/$d2" "$(fasd -e echo $T/tree/$d2)" "completed path"
  assert_eq "$T/tree/$d1" "$(fasd inj)" "print path"
  assert_eq "" "$(print -l $T/tree/pwned*(N) $T/pwned*(N))" "nothing executed"
}

test_help_and_version() {
  local out err
  out=$(fasd -h 2>$T/err)
  assert_eq 0 $? "-h status"
  assert_eq "" "$out" "-h stdout"
  assert_match '*options:*-s*list paths with scores*' "$(< $T/err)" "-h stderr"
  assert_eq "1.0.1 (zsh-optimized)" "$(fasd --version)"
}

test_interactive() {
  entries alpha:3 alp2:2
  assert_eq "$T/tree/alp2" "$(print 2 | fasd -i alp 2>$T/err)" "choice 2"
  assert_match "*2	*alp2*1	*alpha*" "$(< $T/err)" "numbered list on stderr"
  assert_eq "$T/tree/alp2|2.5|1000000"$'\n'"$T/tree/alpha|3|1000000" "$(db)" "choice added back"
  print x | fasd -i alp >/dev/null 2>&1
  assert_eq 1 $? "invalid choice"
  print | fasd -i alp >/dev/null 2>&1
  assert_eq 1 $? "empty choice"
}

test_interactive_single_match() {
  entries alpha:3
  assert_eq "$T/tree/alpha" "$(fasd -i alpha </dev/null 2>/dev/null)"
}
