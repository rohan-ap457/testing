#!/bin/bash
# Put /etc/ssh/sshd_config back to the saved copy if it has changed.
# Safe to run at any time: when nothing is wrong it changes nothing.

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

GOOD=/root/.sshcfg.good        # your sshd_config (install.sh puts it here)
TARGET=/etc/ssh/sshd_config
WANT_OWNER=root:root
WANT_MODE=644
PATH_UNIT=sshcfg.path

# One run at a time (the path unit and the timer can both fire).
exec 9>/run/sshcfg.lock
flock -w 30 9 || exit 1

# sshd -t needs this dir; it may not exist yet if sshd is socket-activated.
[ -d /run/sshd ] || mkdir -p -m 0755 /run/sshd

# Never install a config that sshd rejects.
sshd -t -f "$GOOD" || exit 1

# Already correct? Then do nothing. Rewriting the file would fire the path
# unit again and loop, so only write when something actually differs.
if ! { cmp -s "$GOOD" "$TARGET" &&
       [ "$(stat -c '%U:%G %a' "$TARGET")" = "$WANT_OWNER $WANT_MODE" ]; }; then
    TMP=$(mktemp /etc/ssh/.sshd_config.XXXXXX) || exit 1
    trap 'rm -f "$TMP"' EXIT

    # Write a temp file, then rename it over the real one so sshd never
    # reads a half-written config.
    cat "$GOOD" > "$TMP" &&
    chown "$WANT_OWNER" "$TMP" &&
    chmod "$WANT_MODE" "$TMP" &&
    mv -fT "$TMP" "$TARGET" || exit 1

    restorecon "$TARGET" 2>/dev/null

    # Service is "ssh" on Debian/Ubuntu and "sshd" on RHEL-family.
    # reload-or-restart also starts it if someone stopped it.
    systemctl reload-or-restart ssh 2>/dev/null ||
        systemctl reload-or-restart sshd 2>/dev/null
fi

# Keep the watcher running in case someone stopped it.
systemctl is-active --quiet "$PATH_UNIT" || systemctl start "$PATH_UNIT"

exit 0
