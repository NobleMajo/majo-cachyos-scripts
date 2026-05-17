#!/usr/bin/env bash

set -ex

### HEAD START

ORIGIN_USER="${1:-$USER}"
ORIGIN_HOME="${2:-$HOME}"

SCRIPTS_DIR=$(dirname "$0")
CACHE_DIR="$SCRIPTS_DIR/cache"
TMUX="${TMUX:-$3}"

# escapes variables and prevents command injection
MAJO_SCRIPT_ACTION=$(printf "%q" "$MAJO_SCRIPT_ACTION")
DBUS_SESSION_BUS_ADDRESS=$(printf "%q" "$DBUS_SESSION_BUS_ADDRESS")
XDG_CURRENT_DESKTOP=$(printf "%q" "$XDG_CURRENT_DESKTOP")
ORIGIN_USER=$(printf "%q" "$ORIGIN_USER")
ORIGIN_HOME=$(printf "%q" "$ORIGIN_HOME")
TMUX=$(printf "%q" "$TMUX")
SAFE_SCRIPT=$(printf "%q" "$0")

NEST_CMD="MAJO_SCRIPT_ACTION=$MAJO_SCRIPT_ACTION XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS $SAFE_SCRIPT $ORIGIN_USER $ORIGIN_HOME $TMUX"

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

# LOAD VARIABLES

set -o allexport

source $SCRIPTS_DIR/.env.defaults

if [ -f .env ]; then
    source $SCRIPTS_DIR/.env
fi

set +o allexport

# VALIDATE VARIABLES

if [ "$INTERACTIVE_AUR" != "false" ] && [ "$INTERACTIVE_AUR" != "true" ]; then
  echo "INTERACTIVE_AUR is unset or not a boolean"
fi

if [[ -z "${ALLUP_CLEANUP_CACHE_DAYS:-}" || ! "$ALLUP_CLEANUP_CACHE_DAYS" =~ ^[0-9]+$ ]]; then
  echo "ALLUP_CLEANUP_CACHE_DAYS is unset or not a whole number"
fi
ALLUP_CLEANUP_CACHE_SECS=$(( ALLUP_CLEANUP_CACHE_DAYS * 86400 ))

if [[ -z "${ALLUP_KEYRING_CACHE_DAYS:-}" || ! "$ALLUP_KEYRING_CACHE_DAYS" =~ ^[0-9]+$ ]]; then
  echo "ALLUP_KEYRING_CACHE_DAYS is unset or not a whole number"
fi
ALLUP_KEYRING_CACHE_SECS=$(( ALLUP_KEYRING_CACHE_DAYS * 86400 ))

if [[ -z "${ALLUP_MIRROR_CACHE_DAYS:-}" || ! "$ALLUP_MIRROR_CACHE_DAYS" =~ ^[0-9]+$ ]]; then
  echo "ALLUP_MIRROR_CACHE_DAYS is unset or not a whole number"
fi
ALLUP_MIRROR_CACHE_SECS=$(( ALLUP_MIRROR_CACHE_DAYS * 86400 ))

if [[ -z "${ALLUP_DEFRAG_CACHE_DAYS:-}" || ! "$ALLUP_DEFRAG_CACHE_DAYS" =~ ^[0-9]+$ ]]; then
  echo "ALLUP_DEFRAG_CACHE_DAYS is unset or not a whole number"
fi
ALLUP_DEFRAG_CACHE_SECS=$(( ALLUP_DEFRAG_CACHE_DAYS * 86400 ))

# START SCRIPT

if [ "$MAJO_SCRIPT_ACTION" == "test" ]; then
    echo "Test run done, script should work!"
    exit 0
fi

if [ "$MAJO_SCRIPT_ACTION" != "restart" ]; then 
    if [ "$MAJO_SCRIPT_ACTION" == "poweroff" ]; then
        usersudo rm -f $CACHE_DIR/cachyos-cleanup $CACHE_DIR/cachyos-defrag
    else 
        used=$(df / | tail -n1 | tr -s ' ' | cut -d' ' -f5 | tr -d '%')
        if [ "$used" -gt 80 ]; then
            echo "More then 80% used of the root partition (/), start cleanup script! $used% in use!"
            usersudo rm -f $CACHE_DIR/cachyos-cleanup
        fi
    fi

    # CLEANUP
    if [ ! -f $CACHE_DIR/cachyos-cleanup ] || [ $(( $(date +%s) - $(stat -c %Y $CACHE_DIR/cachyos-cleanup) )) -gt $ALLUP_CLEANUP_CACHE_SECS ]; then
            echo "Run cleanup script..."
            sudo -- $SCRIPTS_DIR/cleanup.sh $ORIGIN_USER $ORIGIN_HOME || true
            usersudo touch $CACHE_DIR/cachyos-cleanup
    fi

    # KEYRING
    if [ ! -f $CACHE_DIR/cachyos-keys ] || [ $(( $(date +%s) - $(stat -c %Y $CACHE_DIR/cachyos-keys) )) -gt $ALLUP_KEYRING_CACHE_SECS ]; then
        echo "Check cachyos keys..."
        usersudo pacman -Sy archlinux-keyring || true
        usersudo pacman-key --refresh-keys || true
        usersudo touch $CACHE_DIR/cachyos-keys
    fi

    # MIRROR
    if [ ! -f $CACHE_DIR/cachyos-rate-mirrors ] || [ $(( $(date +%s) - $(stat -c %Y $CACHE_DIR/cachyos-rate-mirrors) )) -gt $ALLUP_MIRROR_CACHE_SECS ]; then
        echo "Check cachyos mirrors..."
        usersudo cachyos-rate-mirrors || true
        usersudo touch $CACHE_DIR/cachyos-rate-mirrors
    fi

    # DEFRAG
    if [ ! -f $CACHE_DIR/cachyos-defrag ] || [ $(( $(date +%s) - $(stat -c %Y $CACHE_DIR/cachyos-defrag) )) -gt $ALLUP_DEFRAG_CACHE_SECS ]; then
        echo "Run defrag script..."
        sudo -- $SCRIPTS_DIR/defrag.sh $ORIGIN_USER  || true
        usersudo touch $CACHE_DIR/cachyos-defrag
    fi
fi

# UPGRADE
pacman -Syu --noconfirm || true

find /var/cache/pacman/pkg/ -name "download-*" -delete || true
pacman -Sc --noconfirm || true

if usersudo command -v paru >/dev/null; then
    echo "Paru found, start update..."
    paru -Syu --repo --noconfirm --noremovemake
    paru -Sc --noconfirm

    if [ "$MAJO_SCRIPT_ACTION" == "" ] && [ "$INTERACTIVE_AUR" == "true" ]; then
        echo "Paru interactive aur updates..."
        paru -Sua --noconfirm --noremovemake
        paru -Sc --noconfirm
    fi
else
    echo "Paru not found, skipping updates."
fi

if usersudo command -v flatpak >/dev/null; then
    echo "Flatpak found, start update..."
    usersudo flatpak update --assumeyes --noninteractive -v || true
    usersudo flatpak uninstall --unused -y --noninteractive --delete-data || true
    usersudo flatpak repair -v || true
else
    echo "Flatpak not found, skipping updates."
fi

echo "All done!"
sleep 3

if [ "$MAJO_SCRIPT_ACTION" == "restart" ]; then
    shutdown -r +1

    if [ "$XDG_CURRENT_DESKTOP" = "GNOME" ]; then
        echo "XDG_CURRENT_DESKTOP is 'GNOME'. Restart now...."
        usersudo gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager --method org.gnome.SessionManager.Reboot || true
        exit 0
    elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
        echo "Found 'qdbus6', probably KDE Plasma detected. Restart now...."
        usersudo qdbus6 org.kde.Shutdown /Shutdown logoutAndReboot || true
        exit 0
    else
        echo "Desktop environment not detected, restart in 1 minute." 
    fi

    exit 0
fi

if [ "$MAJO_SCRIPT_ACTION" == "poweroff" ]; then
    shutdown -P +1

    if [ "$XDG_CURRENT_DESKTOP" = "GNOME" ]; then
        echo "XDG_CURRENT_DESKTOP is 'GNOME'. Poweroff now...."
        usersudo gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager --method org.gnome.SessionManager.Shutdown || true
    elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
        echo "Found 'qdbus6', probably KDE Plasma detected. Poweroff now...."
        usersudo qdbus6 org.kde.Shutdown /Shutdown logoutAndShutdown || true
    else 
        echo "Desktop environment not detected, poweroff in 1 minute."
    fi
    exit 0
fi

echo "Press enter to exit session..."
read