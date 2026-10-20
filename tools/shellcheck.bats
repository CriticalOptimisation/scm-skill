#!/usr/bin/env bats
# Structural test: shellcheck finds nothing in the scripts and tests of
# tools/, nor in the gh stub (#29). Ported from skill-repo-development
# tools/shellcheck.bats at commit 0511763.
#
# Skipped when shellcheck is not installed; CI installs it and forbids skips.
# No .shellcheckrc and no blanket disable: a directive must carry its reason,
# after a "#" that follows its codes.

bats_require_minimum_version 1.5.0

setup() {
  command -v shellcheck > /dev/null || skip "shellcheck is not installed"
  FILES=("$BATS_TEST_DIRNAME"/*.sh "$BATS_TEST_DIRNAME"/*.bats "$BATS_TEST_DIRNAME/fixtures/gh")
}

# check <file>...: runs shellcheck; its findings are the output of the test.
check() { shellcheck "$@"; }

# unreasoned <file>...: prints <file>:<line>:<text> for each disable directive
# with no reason after its codes. Prints nothing when every one has its reason.
unreasoned() {
  grep -nHE '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]+disable=' "$@" |
    grep -vE 'disable=SC[0-9]+(,SC[0-9]+)*[[:space:]]+#[[:space:]]*[^[:space:]]' ||
    true
}

@test "tools/*.sh, tools/*.bats and tools/fixtures/gh are shellcheck-clean" {
  run check "${FILES[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "a planted finding is reported" {
  planted="$BATS_TEST_TMPDIR/planted.sh"
  cat > "$planted" << 'EOF'
#!/usr/bin/env bash
[ $x = 1 ]
EOF
  run check "$planted"
  [ "$status" -ne 0 ]
  [[ "$output" == *SC2086* ]]
}

@test "every shellcheck disable directive gives its reason" {
  run unreasoned "${FILES[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
