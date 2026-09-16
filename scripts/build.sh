#!/bin/sh
# Validate the fan policy payload. No side effects on the device.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

PAYLOAD="src/k3-fan-guard etc/k3-fan-control.conf systemd/k3-fan-continuous.service"

for file in $PAYLOAD; do
    [ -f "$file" ] || { echo "missing payload file: $file" >&2; exit 1; }
done

sh -n src/k3-fan-guard
sh -n scripts/build.sh
sh -n scripts/run.sh

# The configuration file is sourced by the guard, so a parse failure would take
# the fan policy down with it.
# shellcheck disable=SC1091
( . ./etc/k3-fan-control.conf
  case "${FAN_MIN_STATE:-}" in
      ''|*[!0-9]*) echo "FAN_MIN_STATE must be an integer" >&2; exit 1 ;;
  esac
  [ "$FAN_MIN_STATE" -le 8 ] || { echo "FAN_MIN_STATE must be 0..8" >&2; exit 1; }
  case "${FAN_REASSERT_SECONDS:-}" in
      ''|*[!0-9]*) echo "FAN_REASSERT_SECONDS must be an integer" >&2; exit 1 ;;
  esac
  [ "$FAN_REASSERT_SECONDS" -ge 1 ] || { echo "FAN_REASSERT_SECONDS must be >= 1" >&2; exit 1; } )

grep -q '^\[Service\]$' systemd/k3-fan-continuous.service
grep -q '^ExecStart=/usr/local/lib/k3-fan-control/k3-fan-guard$' \
    systemd/k3-fan-continuous.service
grep -q '^Restart=always$' systemd/k3-fan-continuous.service

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s sh src/k3-fan-guard scripts/build.sh scripts/run.sh
    echo "shellcheck: passed"
fi

echo "payload manifest:"
for file in $PAYLOAD; do
    sha256sum "$file"
done
