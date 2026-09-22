#!/bin/sh
# Install the public Orchestra release binary without requiring GitHub CLI auth.

set -eu

REPOSITORY="jmpompeo/orchestra"
VERSION=""
INSTALL_DIR=""

usage() {
  cat <<'EOF'
Usage: install.sh [--version vX.Y.Z] [--install-dir PATH]

Downloads a public Orchestra release, verifies it against SHA256SUMS, and
installs only the orchestrate executable. This script never changes PATH,
shell profiles, or system prerequisites.
EOF
}

die() {
  printf '%s\n' "Error: $*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required. Install it with your operating system's package manager, then run this installer again."
}

validate_version() {
  case "$VERSION" in
    v*) ;;
    *) die "--version must be a stable release tag in the form vX.Y.Z (for example, v2.1.0)." ;;
  esac

  version_numbers=${VERSION#v}
  old_ifs=$IFS
  IFS=.
  set -- $version_numbers
  IFS=$old_ifs
  [ "$#" -eq 3 ] || die "--version must be a stable release tag in the form vX.Y.Z (for example, v2.1.0)."
  for component in "$@"; do
    case "$component" in
      ''|*[!0-9]*) die "--version must be a stable release tag in the form vX.Y.Z (for example, v2.1.0)." ;;
    esac
  done
}

is_system_path() {
  case "$1" in
    /bin|/bin/*|/sbin|/sbin/*|/usr/bin|/usr/bin/*|/usr/sbin|/usr/sbin/*|/usr/local/bin|/usr/local/bin/*|/System|/System/*|/Library|/Library/*|/opt/homebrew/bin|/opt/homebrew/bin/*)
      return 0
      ;;
    *) return 1 ;;
  esac
}

file_owner_id() {
  case "$HOST_OS" in
    Darwin) stat -f '%u' "$1" ;;
    Linux) stat -c '%u' "$1" ;;
    *) return 1 ;;
  esac
}

assert_no_symlink_ancestors() {
  ancestor=$1
  while [ "$ancestor" != / ]; do
    [ ! -L "$ancestor" ] || die "Refusing install directory '$1' because '$ancestor' is a symlink. Choose a real user-owned directory with --install-dir."
    ancestor=${ancestor%/*}
    [ -n "$ancestor" ] || ancestor=/
  done
}

assert_safe_directory() {
  directory=$1
  case "$directory" in
    /*) ;;
    *) die "--install-dir must be an absolute path. Choose a user-owned directory such as '$HOME/.local/bin'." ;;
  esac
  case "$directory" in
    ..|../*|*/../*|*/..) die "--install-dir must not contain '..'. Use a normalized absolute user-owned path such as '$HOME/.local/bin'." ;;
  esac
  while [ "$directory" != / ] && [ "${directory%/}" != "$directory" ]; do directory=${directory%/}; done
  is_system_path "$directory" && die "Refusing system install directory '$directory'. Use --install-dir with a user-owned directory, for example '$HOME/.local/bin'."
  assert_no_symlink_ancestors "$directory"
  [ -e "$directory" ] || mkdir -p "$directory" || die "Could not create install directory '$directory'. Choose a writable user-owned directory with --install-dir."
  [ ! -L "$directory" ] || die "Refusing install directory '$directory' because it is a symlink. Choose a real user-owned directory with --install-dir."
  [ -d "$directory" ] || die "Install path '$directory' is not a directory. Choose a directory with --install-dir."
  directory_owner=$(file_owner_id "$directory") || die "Could not determine the owner of '$directory'. Choose a user-owned --install-dir."
  [ "$directory_owner" = "$CURRENT_UID" ] || die "Refusing install directory '$directory' because it is not owned by the current user. Choose a user-owned --install-dir."
  [ -w "$directory" ] || die "Install directory '$directory' is not writable. Choose a writable user-owned directory with --install-dir."
}

assert_safe_target() {
  target=$1
  if [ -L "$target" ]; then
    die "Refusing '$target' because it is a symlink. Remove the link manually or choose a different --install-dir."
  fi
  if [ -e "$target" ]; then
    [ -f "$target" ] || die "Refusing '$target' because it is not a regular file. Remove it manually or choose a different --install-dir."
    target_owner=$(file_owner_id "$target") || die "Could not determine the owner of '$target'. Choose a user-owned --install-dir."
    [ "$target_owner" = "$CURRENT_UID" ] || die "Refusing to replace '$target' because it is not owned by the current user. Use a user-owned --install-dir."
    [ -w "$target" ] || die "Refusing to replace '$target' because it is not writable. Fix its permissions or choose a different --install-dir."
  fi
}

download() {
  url=$1
  output=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 -o "$output" "$url" || die "Download failed: $url. Check your network connection and that the requested release exists."
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url" || die "Download failed: $url. Check your network connection and that the requested release exists."
  else
    die "Neither 'curl' nor 'wget' is available. Install one, then run this installer again."
  fi
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    die "Neither 'shasum' nor 'sha256sum' is available. Install a SHA-256 tool, then run this installer again."
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || die "--version requires a value such as v2.1.0."
      VERSION=$2
      shift 2
      ;;
    --install-dir)
      [ "$#" -ge 2 ] || die "--install-dir requires a directory path."
      INSTALL_DIR=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "Unknown argument '$1'. Run with --help for usage." ;;
  esac
done

[ -n "$VERSION" ] && validate_version

HOST_OS=$(uname -s 2>/dev/null || true)
HOST_ARCH=$(uname -m 2>/dev/null || true)
case "$HOST_OS:$HOST_ARCH" in
  Darwin:arm64) RID=osx-arm64 ;;
  Darwin:x86_64) RID=osx-x64 ;;
  Linux:x86_64|Linux:amd64) RID=linux-x64 ;;
  *) die "Unsupported platform. Orchestra bootstrap releases support macOS arm64/x64 and Linux x64 only. Download the matching release manually if your platform is not supported." ;;
esac

CURRENT_UID=$(id -u) || die "Could not determine the current user."
ASSET="orchestrate-$RID.zip"

# Do not use `command -v` alone: PATH may contain more than one executable.
PATH_CANDIDATES=""
PATH_CANDIDATE_KEYS=""
PATH_CANDIDATE_COUNT=0
PATH_FIRST_CANDIDATE=""
remaining_path=${PATH-}
while :; do
  case "$remaining_path" in
    *:*) path_entry=${remaining_path%%:*}; remaining_path=${remaining_path#*:} ;;
    *) path_entry=$remaining_path; remaining_path=; last_path_entry=yes ;;
  esac
  [ -n "$path_entry" ] || path_entry=.
  normalized_entry=$(CDPATH= cd -L "$path_entry" 2>/dev/null && pwd -L) || normalized_entry=$path_entry
  candidate=$normalized_entry/orchestrate
  if [ -e "$candidate" ] || [ -L "$candidate" ]; then
    case ":$PATH_CANDIDATE_KEYS:" in
      *":$candidate:"*) ;;
      *)
        PATH_CANDIDATE_KEYS="${PATH_CANDIDATE_KEYS:+$PATH_CANDIDATE_KEYS:}$candidate"
        PATH_CANDIDATE_COUNT=$((PATH_CANDIDATE_COUNT + 1))
        PATH_CANDIDATES="${PATH_CANDIDATES}\n  $candidate"
        [ -n "$PATH_FIRST_CANDIDATE" ] || PATH_FIRST_CANDIDATE=$candidate
        ;;
    esac
  fi
  [ "${last_path_entry-}" = yes ] && break
done

if [ -z "$INSTALL_DIR" ]; then
  command_resolution=$(command -v orchestrate 2>/dev/null || true)
  if [ "$PATH_CANDIDATE_COUNT" -gt 1 ]; then
    printf '%b\n' "Error: Found multiple orchestrate entries on PATH:${PATH_CANDIDATES}" >&2
    die "Refusing to guess which executable to replace. Remove or rename the unwanted entries, or rerun with --install-dir PATH to install a new executable explicitly."
  fi
  if [ -n "$command_resolution" ] && [ ! -f "$command_resolution" ] && [ ! -L "$command_resolution" ]; then
    die "'orchestrate' resolves to '$command_resolution', not a PATH executable. Remove the alias/function or rerun with --install-dir PATH."
  fi
  if [ "$PATH_CANDIDATE_COUNT" -eq 1 ]; then
    [ -x "$PATH_FIRST_CANDIDATE" ] || die "Found '$PATH_FIRST_CANDIDATE' on PATH, but it is not executable. Remove or rename it, fix its execute permission, or rerun with --install-dir PATH."
    INSTALL_DIR=$PATH_FIRST_CANDIDATE
    INSTALL_DIR=${INSTALL_DIR%/orchestrate}
    note "Updating the one orchestrate executable found on PATH: $INSTALL_DIR/orchestrate"
  else
    [ -n "${HOME-}" ] || die "HOME is not set. Pass --install-dir PATH to choose a user-owned install directory."
    INSTALL_DIR=$HOME/.local/bin
    note "No orchestrate executable was found on PATH; installing to $INSTALL_DIR/orchestrate."
  fi
else
  note "Installing to explicitly requested path: $INSTALL_DIR/orchestrate"
fi

assert_safe_directory "$INSTALL_DIR"
TARGET=$INSTALL_DIR/orchestrate
assert_safe_target "$TARGET"

require_command awk
require_command unzip
require_command mktemp

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/orchestra-install.XXXXXX") || die "Could not create a temporary directory."
STAGED_FILE=""
trap 'rm -rf "$TMP_DIR"; [ -z "$STAGED_FILE" ] || rm -f "$STAGED_FILE"' EXIT HUP INT TERM
ZIP_FILE=$TMP_DIR/$ASSET
SUMS_FILE=$TMP_DIR/SHA256SUMS

if [ -n "$VERSION" ]; then
  RELEASE_URL="https://github.com/$REPOSITORY/releases/download/$VERSION"
else
  RELEASE_URL="https://github.com/$REPOSITORY/releases/latest/download"
fi

note "Downloading $ASSET and SHA256SUMS anonymously from the public GitHub release."
download "$RELEASE_URL/$ASSET" "$ZIP_FILE"
download "$RELEASE_URL/SHA256SUMS" "$SUMS_FILE"

expected_hashes=$(awk -v file="$ASSET" '$1 ~ /^[[:xdigit:]]{64}$/ && ($2 == file || $2 == "*" file) { print tolower($1) }' "$SUMS_FILE")
expected_count=$(printf '%s\n' "$expected_hashes" | awk 'NF { count++ } END { print count + 0 }')
[ "$expected_count" -eq 1 ] || die "SHA256SUMS must contain exactly one SHA-256 entry for '$ASSET'; found $expected_count. Refusing to extract the archive."
expected_hash=$(printf '%s\n' "$expected_hashes" | awk 'NF { print; exit }')
actual_hash=$(sha256_file "$ZIP_FILE")
[ "$actual_hash" = "$expected_hash" ] || die "SHA-256 mismatch for '$ASSET'. The download was not installed; retry later or inspect the public release assets."
note "Checksum verified."

archive_binary_count=$(unzip -Z1 "$ZIP_FILE" | awk '$0 == "orchestrate" { count++ } END { print count + 0 }') || die "Could not inspect '$ASSET' as a ZIP archive."
[ "$archive_binary_count" -eq 1 ] || die "Verified archive must contain exactly one top-level 'orchestrate' executable; found $archive_binary_count. Refusing to install."

# Revalidate the directory after network I/O before creating anything in it.
assert_safe_directory "$INSTALL_DIR"
assert_safe_target "$TARGET"
STAGED_FILE=$(mktemp "$INSTALL_DIR/.orchestrate.XXXXXX") || die "Could not create a staging file in '$INSTALL_DIR'."
if ! unzip -p "$ZIP_FILE" orchestrate > "$STAGED_FILE"; then
  rm -f "$STAGED_FILE"
  die "Could not extract the verified orchestrate executable."
fi
chmod 755 "$STAGED_FILE" || die "Could not mark the staged executable as runnable."

# Recheck immediately before the atomic same-directory rename.
assert_safe_directory "$INSTALL_DIR"
assert_safe_target "$TARGET"
mv -f "$STAGED_FILE" "$TARGET" || die "Could not atomically replace '$TARGET'. Close programs using it or choose a writable --install-dir."
STAGED_FILE=""
note "Installed $TARGET"

case ":${PATH-}:" in
  *":$INSTALL_DIR:"*)
    note "Next steps:"
    note "  orchestrate install --tools codex --dry-run"
    note "  orchestrate install --tools codex"
    ;;
  *)
    note "Next step: add '$INSTALL_DIR' to PATH in your shell configuration and open a new terminal. Then preview and apply your selected configuration:"
    note "  orchestrate install --tools codex --dry-run"
    note "  orchestrate install --tools codex"
    ;;
esac
