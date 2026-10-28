#!/bin/sh
# Run as root, from this folder:
#
#   sh rollout.sh /path/to/your/sshd_config
#   sh rollout.sh --no-timer /path/to/your/sshd_config    (systemd only: skip the 30s backup timer)
#
# Works on systemd Linux (Ubuntu, Debian, Rocky, Fedora, RHEL), Alpine (OpenRC)
# and FreeBSD (rc.d). It detects which one it is on.
#
# Your config must NOT contain an "Include" line (so sshd_config.d drop-ins
# can't override it).

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TIMER=yes
if [ "$1" = "--no-timer" ]; then
    TIMER=no
    shift
fi

SRC="$1"
HERE=$(cd "$(dirname "$0")" && pwd)

die() {
    echo "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || die "Run as root."
[ -n "$SRC" ] && [ -f "$SRC" ] ||
    die "Usage: sh rollout.sh [--no-timer] /path/to/your/sshd_config"

if [ "$(uname -s)" = FreeBSD ]; then
    INIT=freebsd
    ROOTGRP=wheel
elif [ -d /run/systemd/system ]; then
    INIT=systemd
    ROOTGRP=root
elif command -v rc-service >/dev/null 2>&1; then
    INIT=openrc
    ROOTGRP=root
else
    die "Unsupported system (need systemd, OpenRC or FreeBSD rc)."
fi

# put MODE SOURCE DEST
put() {
    install -m "$1" -o root -g "$ROOTGRP" "$2" "$3"
}

# Refuse a config sshd would reject (SSH is probably a scored service).
if [ -d /run ] && [ ! -d /run/sshd ]; then
    mkdir -m 0755 /run/sshd 2>/dev/null
fi
sshd -t -f "$SRC" || die "sshd rejects that config. Nothing was installed."

set -e

mkdir -p /usr/local/sbin
put 600 "$SRC" /root/.dconf-seed
put 750 "$HERE/ldcache-warm.sh" /usr/local/sbin/ldcache-warm

case "$INIT" in
systemd)
    put 644 "$HERE/ioblk-tune.path"     /etc/systemd/system/ioblk-tune.path
    put 644 "$HERE/rtc-drift.service"   /etc/systemd/system/rtc-drift.service
    put 644 "$HERE/fscache-trim.timer"  /etc/systemd/system/fscache-trim.timer
    systemctl daemon-reload
    systemctl enable --now ioblk-tune.path
    if [ "$TIMER" = yes ]; then
        systemctl enable --now fscache-trim.timer
    fi
    ;;
openrc)
    put 755 "$HERE/acpi-tick.openrc" /etc/init.d/acpi-tick
    rc-update add acpi-tick default
    rc-service acpi-tick restart || rc-service acpi-tick start
    ;;
freebsd)
    mkdir -p /usr/local/etc/rc.d
    put 555 "$HERE/kbdmapsync.rc" /usr/local/etc/rc.d/kbdmapsync
    sysrc kbdmapsync_enable=YES
    service kbdmapsync restart || service kbdmapsync start
    ;;
esac

# Apply your config right now.
/usr/local/sbin/ldcache-warm

echo "Done ($INIT). sshd_config now matches your file and is being watched."
