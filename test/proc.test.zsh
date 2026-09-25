# hook command processing: --proc

export _FASD_NOW=1000

test_blacklist() {
  fasd --proc vim --help file.txt
  assert_eq "" "$(db)"
}

test_shift() {
  fasd --proc sudo busybox vim file.txt
  assert_eq "$T/tree/file.txt|1|1000" "$(db)"
}

test_ignore() {
  fasd --proc ls file.txt
  fasd --proc echo file.txt
  assert_eq "" "$(db)"
}

test_command_word_not_added() {
  fasd --proc alpha file.txt
  assert_eq "$T/tree/file.txt|1|1000" "$(db)"
}

test_quoted_token() {
  mkdir -p "$T/tree/foo bar"
  fasd --proc ${(z):-"vim 'foo bar'"}
  assert_eq "$T/tree/foo bar|1|1000" "$(db)"
}

test_track_pwd() {
  export _FASD_TRACK_PWD=1
  fasd --proc vim file.txt
  assert_eq "$T/tree/file.txt|1|1000"$'\n'"$T/tree|1|1000" "$(db)" "PWD added"
  rm -f $_FASD_DATA
  cd $HOME
  fasd --proc vim $T/tree/file.txt
  assert_eq "$T/tree/file.txt|1|1000" "$(db)" "PWD == HOME not added"
}

test_track_pwd_rejects_pipe_dir() { # P0-2
  export _FASD_TRACK_PWD=1
  mkdir -p "$T/tree/we|rd"
  cd "$T/tree/we|rd"
  fasd -A $T/tree/alpha
  assert_eq "$T/tree/alpha|1|1000" "$(db)"
  assert_eq "" "$(awk -F'|' 'NF != 3' $_FASD_DATA)" "every line has 3 fields"
}
