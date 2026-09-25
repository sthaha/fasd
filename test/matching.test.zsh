# query semantics

# add dirs (relative to $T/tree) to the db with rank 1
entries() {
  local d
  for d in "$@"; do
    [[ $d == *.txt ]] || mkdir -p "$T/tree/$d"
    print -r -- "$T/tree/$d|1|1" >> $_FASD_DATA
  done
}

# fasd -l <args>, sorted, relative to $T/tree
q() { fasd -l "$@" | sort | sed "s|^$T/tree/||"; }

test_terms_in_order() {
  entries beta/gamma
  assert_eq "beta/gamma" "$(q beta gam)"
  assert_eq "" "$(q gam beta)" "out of order"
}

test_last_term_matches_last_segment() { # P1-2
  entries beta beta/gamma beta/delta.txt file.txt
  assert_eq "beta" "$(q beta)"
  assert_eq "beta/delta.txt" "$(q delt)"
}

test_trailing_slash() { # P1-2
  entries beta beta/gamma beta/delta.txt
  assert_eq "beta/gamma" "$(q -d beta/)" "trailing / on the last term"
  assert_eq "beta/delta.txt"$'\n'"beta/gamma" "$(q beta /)" "/ as the last term"
}

test_dollar_anchors_end() { # P1-2
  entries beta/delta.txt file.txt alpha
  assert_eq "" "$(q 'delta$')"
  assert_eq "beta/delta.txt"$'\n'"file.txt" "$(q 'txt$')"
  assert_eq "alpha" "$(q 'pha$')"
}

test_case_sensitive_wins() {
  entries Mixed xmixed
  assert_eq "xmixed" "$(q mixed)"
  assert_eq "Mixed" "$(q Mix)"
}

test_case_insensitive_fallback() {
  entries Mixed xmixed
  assert_eq "Mixed"$'\n'"xmixed" "$(q MIXED)"
}

test_fuzzy_only_when_no_match() {
  entries abc axbc
  assert_eq "abc" "$(q abc)"
}

test_fuzzy_skip_count() { # P1-3
  entries axbc axxbc axxxbc
  export _FASD_FUZZY=1
  assert_eq "axbc" "$(q abc)" "_FASD_FUZZY=1"
  export _FASD_FUZZY=2
  assert_eq "axbc"$'\n'"axxbc" "$(q abc)" "_FASD_FUZZY=2"
  export _FASD_FUZZY=3
  assert_eq "axbc"$'\n'"axxbc"$'\n'"axxxbc" "$(q abc)" "_FASD_FUZZY=3"
  assert_eq "axbc"$'\n'"axxbc" "$(q AC)" "fuzzy pass ignores case"
}

test_fuzzy_disabled() {
  entries axbc
  export _FASD_FUZZY=0
  assert_eq "" "$(q abc)"
}

test_fuzzy_does_not_cross_slash() {
  entries ab/c
  assert_eq "" "$(q abc)"
}

test_glob_metachars_literal() { # P1-1
  entries 'alp(' '[b' 'a*a' 'aXa' 'q?q' 'qxq' 'h#h' 't~t' 'c^c'
  local w
  for w in 'alp(' '[b' 'a*a' 'q?q' 'h#h' 't~t' 'c^c'; do
    assert_eq "$w" "$(q $w)" "query $w"
  done
  assert_eq "" "$(q 'zz(' '[')" "unmatched metachars"
  assert_eq "" "$(grep -s 'pattern' $_FASD_SINK)" "no pattern errors"
}

test_type_filter() {
  entries alpha file.txt beta/delta.txt
  assert_eq "alpha" "$(q -d)"
  assert_eq "beta/delta.txt"$'\n'"file.txt" "$(q -f)"
  assert_eq "alpha"$'\n'"beta/delta.txt"$'\n'"file.txt" "$(q -a)"
}

test_deleted_paths_skipped() {
  entries alpha gone
  rmdir $T/tree/gone
  assert_eq "alpha" "$(q)"
  assert_eq "" "$(q gone)"
}
