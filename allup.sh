#!/usr/bin/env bash

set -ex

### HEAD START

ORIGIN_USER="${1:-$USER}"
ORIGIN_HOME="${2:-$HOME}"

SCRIPTS_DIR=$(dirname "$0")
CACHE_DIR="$SCRIPTS_DIR/cache"
TMUX="${TMUX:-$3}"
NEST_CMD="MAJO_SCRIPT_ACTION=\"$MAJO_SCRIPT_ACTION\" DBUS_SESSION_BUS_ADDRESS=\"$DBUS_SESSION_BUS_ADDRESS\" $0 $ORIGIN_USER $ORIGIN_HOME $TMUX"

if [ "$TMUX" == "" ]; then
    if [ "$EUID" == 0 ]; then
        echo "Error: Cant be executed as root user, please use the none-root sudo user."
        exit 1
    fi

    echo "Root access required for system upgrades..."
    sudo echo "Root access granted!"

    echo "Start tmux session..."
    sudo tmux new-session -A -s allup "$NEST_CMD"
    echo "Tmux session done!"
    exit 0
fi

if [ "$EUID" != 0 ]; then
    mkdir -p $SCRIPTS_DIR/logs || true
    mv -f $SCRIPTS_DIR/logs/allup.log2 $SCRIPTS_DIR/logs/allup.log3 >/dev/null 2>&1 || true
    mv -f $SCRIPTS_DIR/logs/allup.log1 $SCRIPTS_DIR/logs/allup.log2 >/dev/null 2>&1 || true

    echo "Start root execution..."
    sudo su - root -c "$NEST_CMD 2>&1 | tee -a $SCRIPTS_DIR/logs/allup.log1"
    echo "Root execution done!"
    exit 0
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

usersudo mkdir -p $CACHE_DIR

### INIT HEAD END

if [ "$MAJO_SCRIPT_ACTION" == "test" ]; then
    echo "Test run done, script should work!"
    exit 0
fi

if [ "$MAJO_SCRIPT_ACTION" != "restart" ]; then 
    if [ ! -f $CACHE_DIR/cachyos-keys ] || [ $(( $(date +%s) - $(stat -c %Y $CACHE_DIR/cachyos-keys) )) -gt 1210000 ]; then
        echo "Check cachyos keys..."
        usersudo pacman -Sy archlinux-keyring || true
        usersudo pacman-key --refresh-keys || true
        usersudo touch $CACHE_DIR/cachyos-keys
    fi

    if [ ! -f $CACHE_DIR/cachyos-rate-mirrors ] || [ $(( $(date +%s) - $(stat -c %Y $CACHE_DIR/cachyos-rate-mirrors) )) -gt 2419000 ]; then
        echo "Check cachyos mirrors..."
        usersudo cachyos-rate-mirrors || true
        usersudo touch $CACHE_DIR/cachyos-rate-mirrors
    fi

    if [ "$MAJO_SCRIPT_ACTION" == "poweroff" ]; then
        usersudo rm -f $CACHE_DIR/cachyos-care $CACHE_DIR/cachyos-defrag
    else 
        used=$(df / | tail -n1 | tr -s ' ' | cut -d' ' -f5 | tr -d '%')
        if [ "$used" -gt 80 ]; then
            echo "More then 80% used of the root partition (/), start care script! $used% in use!"
            usersudo rm -f $CACHE_DIR/cachyos-care
        fi
    fi

    if [ ! -f $CACHE_DIR/cachyos-care ] || [ $(( $(date +%s) - $(stat -c %Y $CACHE_DIR/cachyos-care) )) -gt 604800 ]; then
            echo "Run care script..."
            sudo -- $SCRIPTS_DIR/care.sh $ORIGIN_USER || true
            usersudo touch $CACHE_DIR/cachyos-care
    fi
    if [ ! -f $CACHE_DIR/cachyos-defrag ] || [ $(( $(date +%s) - $(stat -c %Y $CACHE_DIR/cachyos-defrag) )) -gt 604800 ]; then
        echo "Run defrag script..."
        sudo -- $SCRIPTS_DIR/defrag.sh $ORIGIN_USER  || true
        usersudo touch $CACHE_DIR/cachyos-defrag
    fi
fi

pacman -Syu --noconfirm || true

paru -Syu --noconfirm --noremovemake || true
paru -Scc --noconfirm || true

if usersudo command -v flatpak >/dev/null; then
    echo "Flatpak found, start update..."
    usersudo flatpak update --assumeyes --noninteractive -v || true
    usersudo flatpak uninstall --unused -y --noninteractive --delete-data || true
    usersudo flatpak repair -v || true
else
    echo "Flatpak not found, skipping updates."
fi

if [ "$MAJO_SCRIPT_ACTION" == "restart" ]; then
    echo "\nAllup done!\n\nRestart in 5 seconds..."
    sleep 5
    sudo shutdown -r +1 || true # plan restart in 1 minute
    usersudo qdbus6 org.kde.Shutdown /Shutdown logoutAndReboot || true # graceful user restart now
    exit 0
fi

if [ "$MAJO_SCRIPT_ACTION" == "poweroff" ]; then
    echo "\nAllup done!\n\nScheduled a shutdown in 10 seconds..."
    sudo shutdown -P +2 || true # plan shutdown in 2 minutes
    sleep 10
    usersudo qdbus6 org.kde.Shutdown /Shutdown logoutAndShutdown || true # graceful user shutdown now
    exit 0
fi

echo "\nAllup done!\n\nPress enter to exit session..."
read