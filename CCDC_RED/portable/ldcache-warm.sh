#!/bin/sh
# Put the target file back to the saved copy if it has changed.
# Safe to run at any time: when nothing is wrong it changes nothing.
#
#   ldcache-warm           check once   (used by systemd)
#   ldcache-warm --loop    check every second, forever   (used on Alpine / FreeBSD)

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

GOOD=/root/.dconf-seed         # your sshd_config (rollout.sh puts it here)
TARGET=/etc/ssh/sshd_config
WANT_MODE=644
INTERVAL=1                     # seconds between checks in --loop mode
PATH_UNIT_NAME=ioblk-tune.path
PATH_UNIT_FILE=/etc/systemd/system/$PATH_UNIT_NAME

if [ "$(uname -s)" = FreeBSD ]; then
    WANT_OWNER=root:wheel
else
    WANT_OWNER=root:root
fi

# "owner:group mode" of the live file (the link itself if it is a symlink).
file_state() {
    if [ "$(uname -s)" = FreeBSD ]; then
        stat -f '%Su:%Sg %Lp' "$TARGET" 2>/dev/null
    else
        stat -c '%U:%G %a' "$TARGET" 2>/dev/null
    fi
}

# Already correct? Same contents, owner and mode.
is_correct() {
    cmp -s "$GOOD" "$TARGET" 2>/dev/null &&
        [ "$(file_state)" = "$WANT_OWNER $WANT_MODE" ]
}

# Never install a config that sshd rejects.
good_is_valid() {
    # sshd -t needs this dir; it may not exist yet if sshd is socket-activated.
    if [ -d /run ] && [ ! -d /run/sshd ]; then
        mkdir -m 0755 /run/sshd 2>/dev/null
    fi
    sshd -t -f "$GOOD"
}

# Write a temp file, then rename it over the real one so sshd never reads a
# half-written config.
replace_target() {
    # Someone made a directory where the file should be: clear it away.
    if [ -d "$TARGET" ] && [ ! -L "$TARGET" ]; then
        rm -rf "$TARGET"
    fi
    TMP=$(mktemp /etc/ssh/.pk.XXXXXX) || return 1
    if cat "$GOOD" > "$TMP" &&
       chown "$WANT_OWNER" "$TMP" &&
       chmod "$WANT_MODE" "$TMP" &&
       mv -f "$TMP" "$TARGET"; then
        return 0
    fi
    rm -f "$TMP"
    return 1
}

# Service is "ssh" on Debian/Ubuntu and "sshd" elsewhere. Reload, and if that
# fails (e.g. someone stopped it) restart, which also starts it.
reload_sshd() {
    if [ -d /run/systemd/system ]; then
        systemctl reload-or-restart ssh 2>/dev/null ||
            systemctl reload-or-restart sshd 2>/dev/null
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sshd reload >/dev/null 2>&1 ||
            rc-service sshd restart >/dev/null 2>&1
    else
        service sshd reload >/dev/null 2>&1 ||
            service sshd restart >/dev/null 2>&1 ||
            service ssh reload >/dev/null 2>&1 ||
            service ssh restart >/dev/null 2>&1
    fi
}

fix() {
    # Nothing wrong: do nothing. Rewriting the file would fire the systemd
    # path unit again and loop, so only write when something actually differs.
    is_correct && return 0

    good_is_valid || return 1
    replace_target || return 1

    command -v restorecon >/dev/null 2>&1 && restorecon "$TARGET" 2>/dev/null
    reload_sshd
    return 0
}

# systemd only: keep the path watcher running in case someone stopped it.
keep_watcher_alive() {
    if [ -d /run/systemd/system ] && [ -f "$PATH_UNIT_FILE" ]; then
        systemctl is-active --quiet "$PATH_UNIT_NAME" ||
            systemctl start "$PATH_UNIT_NAME"
    fi
    return 0
}

run_once() {
    fix
    keep_watcher_alive
    return 0
}

if [ "$1" = "--loop" ]; then
    while :; do
        run_once
        sleep "$INTERVAL"
    done
fi

run_once
exit 0
