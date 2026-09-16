#!/bin/sh
# Deliver the continuous fan policy to the K3 board and report its state.
#
# The board credentials are read from the workspace-local record at
# <workspace>/.ssh-k3, which is never printed. Only the host, account, and
# secret are used to build the connection.
#
# Actions:
#   (default)   install, enable, start, and verify the fan policy
#   --status    print the current fan and thermal state without changing it
#   --uninstall stop and remove the policy, leaving the kernel in control
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
WORKSPACE=$(CDPATH='' cd -- "$ROOT/../.." && pwd)
CREDENTIALS=${K3_FAN_CREDENTIALS:-"$WORKSPACE/.ssh-k3"}
REMOTE_STAGE=/tmp/k3-fan-control-install
REMOTE_LIB=/usr/local/lib/k3-fan-control
REMOTE_DOC=/usr/local/share/doc/k3-fan-control
UNIT=/etc/systemd/system/k3-fan-continuous.service

ACTION=install
case "${1:-}" in
    "") ;;
    --status) ACTION=status ;;
    --uninstall) ACTION=uninstall ;;
    *) echo "usage: $0 [--status|--uninstall]" >&2; exit 2 ;;
esac

command -v sshpass >/dev/null 2>&1 || {
    echo "sshpass is required for password delivery" >&2
    exit 1
}
command -v ssh >/dev/null 2>&1 || { echo "ssh is required" >&2; exit 1; }
command -v scp >/dev/null 2>&1 || { echo "scp is required" >&2; exit 1; }

[ -r "$CREDENTIALS" ] || { echo "cannot read credentials: $CREDENTIALS" >&2; exit 1; }
mode=$(stat -c '%a' "$CREDENTIALS")
[ "$mode" = "600" ] || { echo "credentials $CREDENTIALS must be mode 0600 (found $mode)" >&2; exit 1; }

host=
user=
secret=
while read -r field_host field_user field_secret _rest; do
    host=$field_host
    user=$field_user
    secret=$field_secret
    break
done < "$CREDENTIALS"
if [ -z "$host" ] || [ -z "$user" ] || [ -z "$secret" ]; then
    echo "credentials record must contain: host account secret" >&2
    exit 1
fi

SSHPASS=$secret
export SSHPASS
SSH_OPTS="-o StrictHostKeyChecking=accept-new \
-o UserKnownHostsFile=$WORKSPACE/.local/known_hosts \
-o ConnectTimeout=20 -o NumberOfPasswordPrompts=1 \
-o PreferredAuthentications=password,publickey"
DEST="$user@$host"

# shellcheck disable=SC2086
remote() {
    sshpass -e ssh $SSH_OPTS "$DEST" "$@"
}

case "$ACTION" in
    status)
        if remote "test -x $REMOTE_LIB/k3-fan-guard"; then
            remote "$REMOTE_LIB/k3-fan-guard --status"
            remote "systemctl is-active k3-fan-continuous.service || true"
            remote "systemctl is-enabled k3-fan-continuous.service || true"
        else
            echo "policy is not installed on the board" >&2
            exit 2
        fi
        ;;
    install)
        remote "mkdir -p $REMOTE_STAGE"
        # shellcheck disable=SC2086
        sshpass -e scp -q $SSH_OPTS \
            "$ROOT/src/k3-fan-guard" \
            "$ROOT/etc/k3-fan-control.conf" \
            "$ROOT/systemd/k3-fan-continuous.service" \
            "$ROOT/README.md" \
            "$DEST:$REMOTE_STAGE/"
        remote sh -s <<REMOTE_SCRIPT
set -eu
install -d -m 0755 "$REMOTE_LIB" "$REMOTE_DOC"
install -m 0755 "$REMOTE_STAGE/k3-fan-guard" "$REMOTE_LIB/k3-fan-guard"
install -m 0644 "$REMOTE_STAGE/README.md" "$REMOTE_DOC/README.md"
if [ -e /etc/k3-fan-control.conf ]; then
    echo "keeping existing /etc/k3-fan-control.conf"
else
    install -m 0644 "$REMOTE_STAGE/k3-fan-control.conf" /etc/k3-fan-control.conf
fi
install -m 0644 "$REMOTE_STAGE/k3-fan-continuous.service" "$UNIT"
systemctl daemon-reload
systemctl enable k3-fan-continuous.service >/dev/null
systemctl restart k3-fan-continuous.service
sleep 3
"$REMOTE_LIB/k3-fan-guard" --status
echo "service_active=\$(systemctl is-active k3-fan-continuous.service)"
echo "service_enabled=\$(systemctl is-enabled k3-fan-continuous.service)"
REMOTE_SCRIPT
        ;;
    uninstall)
        remote sh -s <<REMOTE_SCRIPT
set -eu
systemctl disable --now k3-fan-continuous.service || true
rm -f "$UNIT"
systemctl daemon-reload
rm -f "$REMOTE_LIB/k3-fan-guard"
rmdir "$REMOTE_LIB" 2>/dev/null || true
echo "policy removed; the kernel step_wise governor is in control again"
REMOTE_SCRIPT
        ;;
esac
