# Shared by defaults-backup and defaults-restore (sourced, not executed).
# CAPTALO_DEFAULTS_DOMAIN, CAPTALO_DEFAULTS_DIR and CAPTALO_DEFAULTS_PREFS exist
# only for the script tests.
DOMAIN=${CAPTALO_DEFAULTS_DOMAIN:-com.thecreativetoken.captalo}
PREFS=${CAPTALO_DEFAULTS_PREFS:-"$HOME/Library/Preferences"}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=${CAPTALO_DEFAULTS_DIR:-"$ROOT/.local/shell"}

require_quit() {
  if pgrep -f '^/Applications/Captalo.app/Contents/MacOS/Captalo( |$)' >/dev/null; then
    echo "$(basename "$0"): Cáptalo is running; quit it first." >&2
    exit 1
  fi
}

# Prints `absent` or `present` from positive evidence only; otherwise prints
# "cannot read" to stderr and returns 1, so `CURRENT=$(domain_state)` aborts
# the caller under `set -e` before anything is recorded or marked.
# `absent`: the export is an empty dictionary and the domain's plist file is
# missing or an empty dictionary (what `defaults delete` leaves). An export
# can print an empty dictionary for an unreadable or corrupt file, so a file
# that fails `plutil -lint` or still holds keys is unreadable, never absent.
# Call it only in a command substitution: it sets pipefail for its subshell.
domain_state() {
  set -o pipefail
  local plist="$PREFS/$DOMAIN.plist" exported
  if exported=$(defaults export "$DOMAIN" - 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null); then
    if grep -qx '<dict>' <<<"$exported"; then
      echo present
      return 0
    fi
    if grep -qx '<dict/>' <<<"$exported" && { [ ! -e "$plist" ] || {
         plutil -lint -s "$plist" >/dev/null 2>&1 &&
         plutil -convert xml1 -o - "$plist" 2>/dev/null | grep -qx '<dict/>'; }; }; then
      echo absent
      return 0
    fi
  fi
  echo "$(basename "$0"): cannot read $DOMAIN; nothing recorded or marked" >&2
  return 1
}

# Normalized XML of a plist file, for byte comparison.
xml() { plutil -convert xml1 -o - "$1"; }

# True when the live domain equals the plist file.
domain_matches() {
  live=$(mktemp -t captalo-defaults)
  defaults export "$DOMAIN" "$live"
  xml "$live" | cmp -s - <(xml "$1")
  result=$?
  rm -f "$live"
  return $result
}
