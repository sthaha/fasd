# database I/O: --add / --delete

export _FASD_NOW=1000000

test_add_creates_missing_db() { # P0-1
  rm -f $_FASD_DATA
  fasd -A $T/tree/alpha
  assert_file_eq $_FASD_DATA "$T/tree/alpha|1|1000000"
}

test_add_new_path_rank_1() {
  db_write "$T/tree/alpha|3|10"
  fasd -A $T/tree/file.txt
  assert_eq "$T/tree/alpha|3|10"$'\n'"$T/tree/file.txt|1|1000000" "$(db)"
}

test_add_existing_path_increments_rank() {
  db_write "$T/tree/alpha|4|10"
  fasd -A $T/tree/alpha
  assert_eq "$T/tree/alpha|4.25|1000000" "$(db)"
}

test_aging_and_drop() {
  export _FASD_MAX=10
  db_write "$T/tree/alpha|5|10" "$T/tree/Mixed|6|10" "$T/tree/file.txt|1|10"
  fasd -A $T/tree/alpha
  assert_eq "$T/tree/Mixed|5.4|10"$'\n'"$T/tree/alpha|4.68|1000000"$'\n'"$T/tree/file.txt|0.9|10" \
    "$(db)" "total > max: ranks multiplied by 0.9"
  export _FASD_MAX=2000
  fasd -A $T/tree/Mixed
  assert_eq "$T/tree/Mixed|5.58519|1000000"$'\n'"$T/tree/alpha|4.68|1000000" \
    "$(db)" "rank < 1 dropped on next write"
}

test_nonexistent_ignored_relative_absolute() {
  fasd -A $T/tree/nope alpha beta/delta.txt
  assert_eq "$T/tree/alpha|1|1000000"$'\n'"$T/tree/beta/delta.txt|1|1000000" "$(db)"
}

test_quoted_args_unquoted() {
  mkdir -p "$T/tree/foo bar"
  fasd -A "'foo bar'" '"alpha"'
  assert_eq "$T/tree/alpha|1|1000000"$'\n'"$T/tree/foo bar|1|1000000" "$(db)"
}

test_special_chars_round_trip() { # P0-2
  local -a dirs
  dirs=("$T/tree/with space" "$T/tree/back\\slash" "$T/tree/ünïcødé ✓" "$T/tree/pct%s\\n")
  mkdir -p $dirs
  fasd -A $dirs
  assert_eq "$(print -rl -- ${(o)dirs/%/|1|1000000})" "$(db)"
  assert_eq "$(print -rl -- ${(o)dirs})" "$(fasd -l | sort)" "query returns the exact paths"
}

test_pipe_and_newline_rejected() { # P0-2
  mkdir -p "$T/tree/we|rd" "$T/tree/new"$'\n'"line"
  db_write "$T/tree/alpha|2|10"
  fasd -A "$T/tree/we|rd" "$T/tree/new"$'\n'"line"
  assert_eq "$T/tree/alpha|2|10" "$(db)" "db unchanged"
  fasd -A "$T/tree/we|rd" $T/tree/Mixed
  assert_eq "$T/tree/Mixed|1|1000000"$'\n'"$T/tree/alpha|2|10" "$(db)" "other args still added"
}

test_delete_only_given() {
  db_write "$T/tree/alpha|2|10" "$T/tree/Mixed|3|10" "$T/tree/file.txt|4|10"
  fasd -D $T/tree/alpha file.txt
  assert_eq "$T/tree/Mixed|3|10" "$(db)"
}

test_delete_backslash_path() { # P0-2
  mkdir -p "$T/tree/back\\slash"
  db_write "$T/tree/back\\slash|2|10" "$T/tree/backslash|3|10"
  fasd -D "$T/tree/back\\slash"
  assert_eq "$T/tree/backslash|3|10" "$(db)"
}

test_readonly() {
  db_write "$T/tree/alpha|2|10"
  export _FASD_RO=1
  fasd -A $T/tree/alpha $T/tree/Mixed
  fasd -D $T/tree/alpha
  assert_eq "$T/tree/alpha|2|10" "$(db)"
}

test_foreign_owner_noop() {
  (( EUID == 0 )) || skip "needs root"
  db_write "$T/tree/alpha|2|10"
  chown nobody $_FASD_DATA
  fasd -A $T/tree/alpha
  fasd -D $T/tree/alpha
  assert_eq "$T/tree/alpha|2|10" "$(db)"
}

test_awk_failure_keeps_db() {
  db_write "$T/tree/alpha|2|10"
  export _FASD_AWK=false
  fasd -A $T/tree/alpha
  fasd -D $T/tree/alpha
  assert_eq "$T/tree/alpha|2|10" "$(db)"
  assert_eq "" "$(print -l $_FASD_DATA.??????(N))" "no temp files left"
}

test_no_global_warnings() {
  fasd -A $T/tree/alpha
  fasd -l alpha >/dev/null
  assert_eq "" "$(grep -s 'created globally' $_FASD_SINK)"
}
