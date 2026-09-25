#!/usr/bin/env zsh
# Test runner for fasd. Plain zsh, no dependencies, TAP output.
#
#   zsh test/run.zsh              # run all test/*.test.zsh files
#   zsh test/run.zsh matching     # run test/matching.test.zsh only
#
# A test file defines functions named test_<name>. Each test runs in its own
# subshell, twice: once with `fasd` calling the script as an executable
# (MODE=exec) and once with the script sourced as a function (MODE=source).
# Tests call `skip <reason>` or `todo <reason>` to mark themselves.

emulate -R zsh
setopt extendedglob
zmodload zsh/datetime

TEST_ROOT=${0:A:h}
FASD_BIN=${TEST_ROOT:h}/fasd
FIXTURES=$TEST_ROOT/fixtures

# ---------------------------------------------------------------- helpers

_fail() {
  (( _failures++ ))
  print -r -- "# FAIL: $1"
  shift
  local line
  for line in "$@"; do print -r -- "#   $line"; done
}

assert_eq() { # expected actual [message]
  [[ "$1" == "$2" ]] && return 0
  _fail "${3:-assert_eq}" "expected: ${(qqqq)1}" "actual:   ${(qqqq)2}"
  return 1
}

assert_match() { # pattern actual [message]
  [[ "$2" == $~1 ]] && return 0
  _fail "${3:-assert_match}" "pattern: $1" "actual:  ${(qqqq)2}"
  return 1
}

assert_file_eq() { # file expected-content [message]
  local content
  [[ -e "$1" ]] && content="$(< "$1")" || content="<missing file>"
  assert_eq "$2" "$content" "${3:-assert_file_eq $1}"
}

assert_status() { # expected-status command...
  local expected=$1; shift
  "$@"
  local st=$?
  (( st == expected )) && return 0
  _fail "assert_status: $*" "expected status $expected, got $st"
  return 1
}

skip() { print -r -- "$*" >| "$_TEST_TMP/.skip"; exit 0; }
todo() { print -r -- "$*" >| "$_TEST_TMP/.todo"; }

# sort the lines of a db file (awk writes them in hash order)
db() { [[ -e "$_FASD_DATA" ]] && sort "$_FASD_DATA"; }

# write sorted "path|rank|time" lines to the db
db_write() { print -rl -- "$@" | sort >| "$_FASD_DATA"; }

# squeeze runs of spaces, so `-s` output can be compared exactly
squeeze() { local l; for l in "${(@f)1}"; do print -r -- "${l// ##/ }"; done; }

setup() { # fresh, isolated environment in $T
  T=$1
  local v
  for v in ${(k)parameters[(I)_FASD_*]}; do
    [[ $v == _FASD_AWK ]] || unset $v
  done
  unset ZDOTDIR LC_ALL
  export LC_COLLATE=C
  export HOME=$T/home
  export _FASD_DATA=$T/fasd.db _FASD_NORC=1 _FASD_TRACK_PWD=0
  export _FASD_SINK=$T/sink
  export PATH=$T/bin:$PATH
  mkdir -p $HOME $T/bin $T/tree/{alpha,beta/gamma,Mixed}
  : >| $T/tree/beta/delta.txt
  : >| $T/tree/file.txt
  cd $T/tree
}

# write an executable script to $T/bin/<name>, usable as a custom backend
mkbin() { print -r -- "#!/bin/sh"$'\n'"$2" >| $T/bin/$1; chmod +x $T/bin/$1; }

# ---------------------------------------------------------------- runner

run_one() { # file test mode tmpdir
  local file=$1 name=$2
  MODE=$3
  _TEST_TMP=$4
  _failures=0
  setup $4/t
  source $file
  if [[ $MODE == source ]]; then
    source $FASD_BIN
  else
    fasd() { $FASD_BIN "$@"; }
  fi
  $name
  exit $(( _failures > 0 ))
}

local -a files
if [[ -n $1 ]]; then
  files=($TEST_ROOT/${1%.test.zsh}.test.zsh)
  [[ -f $files[1] ]] || { print -u2 "no such test file: $files[1]"; exit 2; }
else
  files=($TEST_ROOT/*.test.zsh)
fi

integer n=0 pass=0 fail=0 skipped=0 todos=0
local file name mode tmp desc directive st
for file in $files; do
  print -r -- "# ${file:t}"
  for name in ${(f)"$(sed -n 's/^\(test_[A-Za-z0-9_]*\)().*/\1/p' $file)"}; do
    for mode in exec source; do
      tmp=$(mktemp -d "${TMPDIR:-/tmp}/fasd-test.XXXXXX") || exit 2
      tmp=${tmp:A}
      mkdir -p $tmp/t
      ( run_one $file $name $mode $tmp ) >| $tmp/.out 2>&1 </dev/null
      st=$?
      (( n++ ))
      desc="${file:t:r:r} ${name#test_} [$mode]"
      directive=
      if [[ -e $tmp/.skip ]]; then
        directive=" # SKIP $(< $tmp/.skip)"
        (( skipped++ ))
      elif [[ -e $tmp/.todo ]]; then
        directive=" # TODO $(< $tmp/.todo)"
        (( todos++ ))
      fi
      if (( st == 0 )); then
        print -r -- "ok $n - $desc$directive"
        [[ -z $directive ]] && (( pass++ ))
      else
        print -r -- "not ok $n - $desc$directive"
        [[ -z $directive ]] && (( fail++ ))
        sed 's/^/# /' $tmp/.out
      fi
      command rm -rf $tmp
    done
  done
done

print "1..$n"
print "# tests $n, pass $pass, fail $fail, skip $skipped, todo $todos (_FASD_AWK=${_FASD_AWK:-default})"
(( fail == 0 ))
