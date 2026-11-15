# Shared by defaults-backup and defaults-restore (sourced, not executed).
# CAPTALO_DEFAULTS_DOMAIN and CAPTALO_DEFAULTS_DIR exist only for the script tests.
DOMAIN=${CAPTALO_DEFAULTS_DOMAIN:-com.thecreativetoken.captalo}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=${CAPTALO_DEFAULTS_DIR:-"$ROOT/.local/shell"}

require_quit() {
  if pgrep -f '^/Applications/Captalo.app/Contents/MacOS/Captalo( |$)' >/dev/null; then
    echo "$(basename "$0"): Cáptalo is running; quit it first." >&2
    exit 1
  fi
}

# A deleted domain can still read back as an empty dictionary: empty means absent.
is_empty() { [ "$(defaults export "$DOMAIN" - 2>/dev/null | plutil -convert json -o - - 2>/dev/null)" = "{}" ] || ! defaults read "$DOMAIN" >/dev/null 2>&1; }

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
