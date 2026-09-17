#!/bin/sh
# Offline functional test for the fan guard.
#
# The guard reads /sys/class/thermal and /sys/class/hwmon, and the board is not
# always reachable, so this test builds a fake sysfs tree and binds it inside a
# private mount namespace (unshare -m). Nothing outside that namespace changes.
#
# It covers the three claims the guard makes: it raises a level below the floor,
# it uses the configured floor rather than a hard-coded one, and a long-running
# guard picks up an edited floor without a restart.
#
#   tests/guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
GUARD=$SCRIPT_DIR/../src/k3-fan-guard

command -v unshare >/dev/null 2>&1 || { echo "unshare is required" >&2; exit 1; }
unshare -m true 2>/dev/null || {
    echo "unshare -m is not permitted here, so the guard cannot be tested offline" >&2
    exit 1
}

ROOT=$(mktemp -d)
FAKE_SYS=$ROOT/sys
CDEV=$FAKE_SYS/class/thermal/cooling_device0
HWMON=$FAKE_SYS/class/hwmon/hwmon0
CONF=$ROOT/fan.conf
LOG=$ROOT/guard.log
mkdir -p "$CDEV" "$HWMON" "$FAKE_SYS/class/thermal/thermal_zone0"

printf 'pwm-fan\n'          > "$CDEV/type"
printf '8\n'                > "$CDEV/max_state"
printf '0\n'                > "$CDEV/cur_state"
printf 'pwmfan\n'           > "$HWMON/name"
printf '1\n'                > "$HWMON/pwm1_enable"
printf '213\n'              > "$HWMON/pwm1"
printf 'thermal_cluster0\n' > "$FAKE_SYS/class/thermal/thermal_zone0/type"
printf 'step_wise\n'        > "$FAKE_SYS/class/thermal/thermal_zone0/policy"
printf '45000\n'            > "$FAKE_SYS/class/thermal/thermal_zone0/temp"

failures=0

with_fake_sysfs() { # with_fake_sysfs <shell command>
    unshare -m sh -c "
        mount --bind '$FAKE_SYS/class/thermal' /sys/class/thermal &&
        mount --bind '$FAKE_SYS/class/hwmon' /sys/class/hwmon &&
        $1"
}

expect() { # expect <what> <wanted> <got>
    if [ "$2" = "$3" ]; then
        printf 'ok   %s: %s\n' "$1" "$3"
    else
        printf 'FAIL %s: wanted %s, got %s\n' "$1" "$2" "$3" >&2
        failures=$((failures + 1))
    fi
}

# 1. A level below the floor is raised.
printf '0\n' > "$CDEV/cur_state"
printf 'FAN_MIN_STATE=8\nFAN_REASSERT_SECONDS=1\n' > "$CONF"
with_fake_sysfs "K3_FAN_CONF='$CONF' timeout 5 '$GUARD' --once" > "$LOG" 2>&1 || true
expect "floor 8 raises the level" 8 "$(cat "$CDEV/cur_state")"

# 2. The configured floor is used, not a hard-coded one.
printf '0\n' > "$CDEV/cur_state"
printf 'FAN_MIN_STATE=3\nFAN_REASSERT_SECONDS=1\n' > "$CONF"
with_fake_sysfs "K3_FAN_CONF='$CONF' timeout 5 '$GUARD' --once" > "$LOG" 2>&1 || true
expect "floor 3 raises the level only to 3" 3 "$(cat "$CDEV/cur_state")"

# 3. A long-running guard re-reads the configuration each interval, which is
#    what makes an edited floor take effect without a service restart.
printf '0\n' > "$CDEV/cur_state"
printf 'FAN_MIN_STATE=2\nFAN_REASSERT_SECONDS=1\n' > "$CONF"
with_fake_sysfs "
    K3_FAN_CONF='$CONF' '$GUARD' > '$LOG' 2>&1 &
    sleep 2
    printf 'FAN_MIN_STATE=7\nFAN_REASSERT_SECONDS=1\n' > '$CONF'
    printf '0\n' > '$CDEV/cur_state'
    sleep 2
    kill \$! || true
    wait \$! 2>/dev/null || true" || true
expect "the running guard picks up the edited floor" 7 "$(cat "$CDEV/cur_state")"
grep -q 'raised fan level 0 -> 7' "$LOG" ||
    { echo "FAIL the guard log does not show the edited floor" >&2; failures=$((failures + 1)); }

echo "guard-test: $failures failure(s)"
[ "$failures" -eq 0 ]
