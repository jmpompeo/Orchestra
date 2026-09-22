#!/bin/sh
# Network-free behavioural tests for scripts/install.sh.

set -eu

REPOSITORY_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
INSTALLER=$REPOSITORY_ROOT/scripts/install.sh
TMP_BASE=$(CDPATH= cd "${TMPDIR:-/tmp}" && pwd -P)
TEST_ROOT=$(mktemp -d "$TMP_BASE/orchestra-install-sh-tests.XXXXXX")
FIXTURE_DIR=$TEST_ROOT/fixture
MOCK_DIR=$TEST_ROOT/mock-bin
BASE_PATH=/usr/bin:/bin

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Test prerequisite '$1' is not available."
}

assert_contains() {
  needle=$1
  file=$2
  grep -F "$needle" "$file" >/dev/null 2>&1 || fail "Expected '$needle' in $file."
}

assert_status() {
  expected=$1
  [ "$LAST_STATUS" -eq "$expected" ] || fail "Expected exit status $expected for $LAST_NAME, got $LAST_STATUS. Output: $(cat "$LAST_OUTPUT")"
}

assert_same_file() {
  expected=$1
  actual=$2
  cmp -s "$expected" "$actual" || fail "Expected '$actual' to have the exact fixture executable content."
}

case "$(uname -s):$(uname -m)" in
  Darwin:arm64) RID=osx-arm64 ;;
  Darwin:x86_64) RID=osx-x64 ;;
  Linux:x86_64|Linux:amd64) RID=linux-x64 ;;
  *) fail "This POSIX installer test requires a supported macOS or Linux x64 host." ;;
esac

require_command zip
require_command unzip
require_command cmp
if command -v shasum >/dev/null 2>&1; then
  HASH_COMMAND='shasum -a 256'
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_COMMAND=sha256sum
else
  fail "Test prerequisite 'shasum' or 'sha256sum' is not available."
fi

mkdir -p "$FIXTURE_DIR" "$MOCK_DIR"
ASSET=orchestrate-$RID.zip
FIXTURE_EXECUTABLE=$FIXTURE_DIR/orchestrate
FIXTURE_ZIP=$FIXTURE_DIR/$ASSET
VALID_SUMS=$FIXTURE_DIR/SHA256SUMS.valid
INVALID_SUMS=$FIXTURE_DIR/SHA256SUMS.invalid

printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "orchestra-test-payload"' > "$FIXTURE_EXECUTABLE"
chmod 755 "$FIXTURE_EXECUTABLE"
(cd "$FIXTURE_DIR" && zip -q "$ASSET" orchestrate)
# shellcheck disable=SC2086 # HASH_COMMAND deliberately holds a fixed command.
$HASH_COMMAND "$FIXTURE_ZIP" | awk -v asset="$ASSET" '{ print $1 "  " asset }' > "$VALID_SUMS"
printf '%064d  %s\n' 0 "$ASSET" > "$INVALID_SUMS"

cat > "$MOCK_DIR/curl" <<'EOF'
#!/bin/sh
set -eu
output=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output=$2
      shift 2
      ;;
    --retry|--connect-timeout)
      shift 2
      ;;
    -fL)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done
[ -n "$output" ] && [ -n "$url" ]
printf '%s\n' "$url" >> "$ORCHESTRA_TEST_URL_LOG"
case "$url" in
  */SHA256SUMS) cp "$ORCHESTRA_TEST_SUMS" "$output" ;;
  *) cp "$ORCHESTRA_TEST_ZIP" "$output" ;;
esac
EOF
chmod 755 "$MOCK_DIR/curl"

run_installer() {
  LAST_NAME=$1
  shift
  LAST_OUTPUT=$TEST_ROOT/$LAST_NAME.output
  LAST_URL_LOG=$TEST_ROOT/$LAST_NAME.urls
  : > "$LAST_URL_LOG"
  if ORCHESTRA_TEST_ZIP="$FIXTURE_ZIP" ORCHESTRA_TEST_SUMS="$CURRENT_SUMS" ORCHESTRA_TEST_URL_LOG="$LAST_URL_LOG" PATH="$TEST_PATH" /bin/sh "$INSTALLER" "$@" > "$LAST_OUTPUT" 2>&1; then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

# New install: use a verified mocked public release and confirm exact output.
CURRENT_SUMS=$VALID_SUMS
TEST_PATH=$MOCK_DIR:$BASE_PATH
NEW_BIN=$TEST_ROOT/new/bin
run_installer new-install --version v2.1.0 --install-dir "$NEW_BIN"
assert_status 0
assert_same_file "$FIXTURE_EXECUTABLE" "$NEW_BIN/orchestrate"
assert_contains "Checksum verified." "$LAST_OUTPUT"
assert_contains "Next step: add '$NEW_BIN' to PATH" "$LAST_OUTPUT"
assert_contains "https://github.com/jmpompeo/orchestra/releases/download/v2.1.0/$ASSET" "$LAST_URL_LOG"
assert_contains "https://github.com/jmpompeo/orchestra/releases/download/v2.1.0/SHA256SUMS" "$LAST_URL_LOG"
"$NEW_BIN/orchestrate" | grep -Fx 'orchestra-test-payload' >/dev/null 2>&1 || fail "Installed executable did not run the fixture payload."

# One safe PATH target is upgraded in place rather than redirected elsewhere.
EXISTING_BIN=$TEST_ROOT/existing/bin
mkdir -p "$EXISTING_BIN"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "old-payload"' > "$EXISTING_BIN/orchestrate"
chmod 755 "$EXISTING_BIN/orchestrate"
CURRENT_SUMS=$VALID_SUMS
TEST_PATH=$MOCK_DIR:$EXISTING_BIN:$BASE_PATH
run_installer safe-path-upgrade --version v2.1.0
assert_status 0
assert_same_file "$FIXTURE_EXECUTABLE" "$EXISTING_BIN/orchestrate"
assert_contains "Updating the one orchestrate executable found on PATH: $EXISTING_BIN/orchestrate" "$LAST_OUTPUT"

# Repeating the same directory on PATH still identifies one executable.
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "old-again"' > "$EXISTING_BIN/orchestrate"
chmod 755 "$EXISTING_BIN/orchestrate"
CURRENT_SUMS=$VALID_SUMS
TEST_PATH=$MOCK_DIR:$EXISTING_BIN:$EXISTING_BIN:$BASE_PATH
run_installer duplicate-path-entry --version v2.1.0
assert_status 0
assert_same_file "$FIXTURE_EXECUTABLE" "$EXISTING_BIN/orchestrate"

# A bad manifest must not alter an otherwise safe existing executable.
MISMATCH_BIN=$TEST_ROOT/mismatch/bin
mkdir -p "$MISMATCH_BIN"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "must-remain"' > "$MISMATCH_BIN/orchestrate"
chmod 755 "$MISMATCH_BIN/orchestrate"
cp "$MISMATCH_BIN/orchestrate" "$TEST_ROOT/mismatch-before"
CURRENT_SUMS=$INVALID_SUMS
TEST_PATH=$MOCK_DIR:$BASE_PATH
run_installer checksum-mismatch --version v2.1.0 --install-dir "$MISMATCH_BIN"
assert_status 1
assert_contains 'SHA-256 mismatch' "$LAST_OUTPUT"
assert_same_file "$TEST_ROOT/mismatch-before" "$MISMATCH_BIN/orchestrate"

# Multiple PATH candidates are ambiguous and must not trigger a download.
AMBIGUOUS_A=$TEST_ROOT/ambiguous/a
AMBIGUOUS_B=$TEST_ROOT/ambiguous/b
mkdir -p "$AMBIGUOUS_A" "$AMBIGUOUS_B"
cp "$FIXTURE_EXECUTABLE" "$AMBIGUOUS_A/orchestrate"
cp "$FIXTURE_EXECUTABLE" "$AMBIGUOUS_B/orchestrate"
CURRENT_SUMS=$VALID_SUMS
TEST_PATH=$MOCK_DIR:$AMBIGUOUS_A:$AMBIGUOUS_B:$BASE_PATH
run_installer ambiguous-path --version v2.1.0
assert_status 1
assert_contains 'Found multiple orchestrate entries on PATH' "$LAST_OUTPUT"
[ ! -s "$LAST_URL_LOG" ] || fail "Ambiguous PATH case attempted a download."

# A non-executable PATH collision must not be silently replaced.
NON_EXECUTABLE_BIN=$TEST_ROOT/non-executable/bin
mkdir -p "$NON_EXECUTABLE_BIN"
printf '%s\n' 'personal file' > "$NON_EXECUTABLE_BIN/orchestrate"
chmod 644 "$NON_EXECUTABLE_BIN/orchestrate"
CURRENT_SUMS=$VALID_SUMS
TEST_PATH=$MOCK_DIR:$NON_EXECUTABLE_BIN:$BASE_PATH
run_installer non-executable-path --version v2.1.0
assert_status 1
assert_contains 'but it is not executable' "$LAST_OUTPUT"
assert_contains 'personal file' "$NON_EXECUTABLE_BIN/orchestrate"
[ ! -s "$LAST_URL_LOG" ] || fail "Non-executable PATH collision attempted a download."

# A symlink target is refused before a download or replacement can occur.
SYMLINK_BIN=$TEST_ROOT/symlink/bin
mkdir -p "$SYMLINK_BIN"
ln -s "$FIXTURE_EXECUTABLE" "$SYMLINK_BIN/orchestrate"
CURRENT_SUMS=$VALID_SUMS
TEST_PATH=$MOCK_DIR:$BASE_PATH
run_installer symlink-target --version v2.1.0 --install-dir "$SYMLINK_BIN"
assert_status 1
assert_contains 'because it is a symlink' "$LAST_OUTPUT"
[ -L "$SYMLINK_BIN/orchestrate" ] || fail "Symlink target was unexpectedly changed."
[ ! -s "$LAST_URL_LOG" ] || fail "Symlink target case attempted a download."

# Version validation happens before platform/download work.
CURRENT_SUMS=$VALID_SUMS
TEST_PATH=$MOCK_DIR:$BASE_PATH
run_installer invalid-version --version v2.bad.0 --install-dir "$TEST_ROOT/invalid/bin"
assert_status 1
assert_contains 'stable release tag in the form vX.Y.Z' "$LAST_OUTPUT"
[ ! -s "$LAST_URL_LOG" ] || fail "Invalid version case attempted a download."

printf '%s\n' 'PASS: scripts/install.sh network-free installer tests'
