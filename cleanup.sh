#!/usr/bin/env bash

set -ex

ORIGIN_USER="$1"
ORIGIN_HOME="$2"

if [ "$ORIGIN_USER" == "" ]; then
    echo "Error: none-root username needs to be set as first parameter: <cmd> <username> <homepath>"
    exit 1
fi

if [ "$ORIGIN_HOME" == "" ]; then
    echo "Error: none-root homedir path needs to be set as second parameter: <cmd> <username> <homepath>"
    exit 1
fi

if [ "$ORIGIN_USER" == "root" ]; then
    echo "Error: Cant be executed as root user, please use the none-root sudo user."
    exit 1
fi

if [ "$ORIGIN_HOME" == "/root" ]; then
    echo "Error: Cant be executed as root user, please use the none-root sudo user."
    exit 1
fi

usersudo() {
    su $ORIGIN_USER -c "$*"
}

### INIT HEAD END

usersudo mkdir -p $CACHE_DIR

used=$(df / | tail -n1 | tr -s ' ' | cut -d' ' -f5 | tr -d '%')
if [ "$used" -gt 90 ]; then
    echo "More then 90% used of the root partition (/), start deep cleanup! $used% in use!"

    # cache, tmp & desktop
    rm -rf $ORIGIN_HOME/.cache/* $ORIGIN_HOME/.thumbnails/* $ORIGIN_HOME/.cache/plasma* $ORIGIN_HOME/.cache/krunner* /var/cache/plasma* $ORIGIN_HOME/.local/share/Trash/* 2>/dev/null || true
    find /tmp -mindepth 1 -atime +1 -delete 2>/dev/null || true
    find /var/tmp -mindepth 1 -atime +1 -delete 2>/dev/null || true
    
    # logs
    find /var/log -name "*.log.*" -type f -mtime +1 -delete || true
    logrotate --force /etc/logrotate.conf || true

    # journalctl
    journalctl --vacuum-time=7d || true
    journalctl --vacuum-size=500M || true

    # docker
    if usersudo command -v flatpak >/dev/null; then
        echo "Docker found, start cleanup..."
        usersudo docker rm -f $(docker ps -aq) || true
        usersudo docker container prune -f || true
        usersudo docker image prune -a -f || true
        usersudo docker network prune -f || true
        usersudo docker volume prune -f || true
        usersudo docker system prune -a -f --volumes || true
    else
        echo "Docker not found, skipping cleanup."
    fi
else
    # cache & tmp
    find $ORIGIN_HOME/.cache -type f -atime +14 -delete 2>/dev/null || true
    find $ORIGIN_HOME/.cache -type d -empty -delete 2>/dev/null || true
    find $ORIGIN_HOME/.thumbnails -type f -atime +14 -delete 2>/dev/null || true
    find $ORIGIN_HOME/.thumbnails -type d -empty -delete 2>/dev/null || true
    find $ORIGIN_HOME/.local/share/Trash -mindepth 1 -type f -atime +14 -delete 2>/dev/null || true
    find $ORIGIN_HOME/.local/share/Trash -type d -empty -delete 2>/dev/null || true

    # desktop
    find $ORIGIN_HOME/.cache/plasma* -mindepth 1 -type f -atime +14 -delete 2>/dev/null || true
    find $ORIGIN_HOME/.cache/plasma* -type d -empty -delete 2>/dev/null || true
    find $ORIGIN_HOME/.cache/krunner* -mindepth 1 -type f -atime +14 -delete 2>/dev/null || true
    find $ORIGIN_HOME/.cache/krunner* -type d -empty -delete 2>/dev/null || true
    find /var/cache/plasma* -mindepth 1 -type f -atime +14 -delete 2>/dev/null || true
    find /var/cache/plasma* -type d -empty -delete 2>/dev/null || true

    # logs
    find /var/log -name "*.log.*" -type f -mtime +14 -delete || true
    logrotate /etc/logrotate.conf || true

    # journalctl
    journalctl --vacuum-time=14d || true
    journalctl --vacuum-size=1000M || true

    # docker
    if usersudo command -v flatpak >/dev/null; then
        echo "Docker found, start cleanup..."
        usersudo flatpak update --assumeyes --noninteractive -v || true
        usersudo flatpak uninstall --unused -y --noninteractive --delete-data || true
        usersudo flatpak repair -v || true
    else
        echo "Docker not found, skipping cleanup."
    fi

    usersudo docker system prune -a -f --filter "until=168h" || true
    usersudo docker volume prune -f || true
fi

echo "Cleanup script done!"
exit 0