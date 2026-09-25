# scoring, with a fixed clock

export _FASD_NOW=1000000

# add "name:rank:age-in-seconds" entries (dirs relative to $T/tree)
entries() {
  local e
  for e in "$@"; do
    local -a f=("${(@s.:.)e}")
    mkdir -p "$T/tree/$f[1]"
    print -r -- "$T/tree/$f[1]|$f[2]|$(( _FASD_NOW - f[3] ))" >> $_FASD_DATA
  done
}

# fasd -s <args>: "score name" lines, in output order
scores() { squeeze "$(fasd -s "$@")" | sed "s|$T/tree/||"; }

test_frecency_buckets() {
  entries a:1:3599 b:1:3600 c:1:86399 d:1:86400 e:1:604799 f:1:604800
  assert_eq $'1 f\n2 d\n2 e\n4 b\n4 c\n6 a' "$(scores | sort)"
}

test_frecency_times_rank() {
  entries a:2.5:10 b:3:90000
  assert_eq $'6 b\n15 a' "$(scores)"
}

test_rank_mode() {
  entries a:2:10 b:5:9999999
  assert_eq $'2 a\n5 b' "$(scores -r)"
}

test_recent_mode() {
  entries a:9:99999 b:1:0
  assert_eq $'1 a\n316.228 b' "$(scores -t)"
}

test_duplicates_across_backends() {
  entries a:3:100000
  mkbin dup "echo '$T/tree/a|2|$(( _FASD_NOW - 10 ))'"
  export _FASD_BACKENDS="native dup"
  assert_eq "30 a" "$(scores)" "ranks summed (5), newest time kept (weight 6)"
}

test_sort_and_reverse() {
  entries a:2:10 b:3:10 c:1:10
  assert_eq $'6 c\n12 a\n18 b' "$(scores)" "ascending"
  assert_eq $'18 b\n12 a\n6 c' "$(scores -R)" "-R reverses"
  assert_eq $'b\na\nc' "$(fasd -lR | sed "s|$T/tree/||")" "-lR reverses"
}
