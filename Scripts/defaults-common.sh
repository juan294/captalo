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

# Prints the domain's state from positive evidence only: `absent` when the
# export succeeds as an empty dictionary (a deleted or never-written domain
# exports as one), `present` when it succeeds with keys, and `unreadable`
# when the export or its conversion fails. A failed inspection never counts
# as absent.
domain_state() {
  local exported json
  exported=$(defaults export "$DOMAIN" - 2>/dev/null) || { echo unreadable; return; }
  json=$(printf '%s' "$exported" | plutil -convert json -o - - 2>/dev/null) || { echo unreadable; return; }
  case $json in
    "{}") echo absent ;;
    "{"*) echo present ;;
    *) echo unreadable ;;
  esac
}

# Exits 1 when the state is unreadable; nothing is recorded or marked.
require_readable() {
  if [ "$1" = unreadable ]; then
    echo "$(basename "$0"): cannot read $DOMAIN; nothing recorded or marked" >&2
    exit 1
  fi
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
