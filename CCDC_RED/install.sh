#!/bin/bash
# Run as root on the Linux machine, from the folder holding these files:
#
#   bash install.sh /path/to/your/sshd_config
#   bash install.sh --no-timer /path/to/your/sshd_config     (skip the 30s backup timer)
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

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root." >&2
    exit 1
fi
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
    echo "Usage: bash install.sh [--no-timer] /path/to/your/sshd_config" >&2
    exit 1
fi

# Refuse a config sshd would reject (SSH is probably a scored service).
[ -d /run/sshd ] || mkdir -p -m 0755 /run/sshd
if ! sshd -t -f "$SRC"; then
    echo "sshd rejects that config. Nothing was installed." >&2
    exit 1
fi

set -e

install -m 600 -o root -g root "$SRC" /root/.sshcfg.good
install -m 750 -o root -g root "$HERE/sshcfg.sh" /usr/local/sbin/sshcfg.sh
install -m 644 -o root -g root \
    "$HERE/sshcfg.path" "$HERE/sshcfg.service" "$HERE/sshcfg.timer" \
    /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now sshcfg.path
if [ "$TIMER" = "yes" ]; then
    systemctl enable --now sshcfg.timer
fi

# Apply your config right now.
/usr/local/sbin/sshcfg.sh

echo "Done. sshd_config now matches your file and is being watched."
