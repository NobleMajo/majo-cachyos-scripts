# majo-cachyos-scripts

Automated maintenance and upgrade scripts for CachyOS, designed to run non-interactively inside a controlled tmux session.

## Requirements

### Required
- CachyOS
- `tmux` - install via: `sudo pacman -S tmux`

### Usually already installed on CachyOS
- `sudo`
- `pacman`
- `paru`

### Optional
- `flatpak`
- an `code` command
  - VSCodium 
  - Code OSS (opensource vscode)
  - Microsoft Visual Studio Code
  - or remove the aliases
  - or replace it with your editor:
    - vim (exit = ESC>`:!q`>ENTER)

## Usage

- `alltest`: Does nothing only as setup test.
- `allup`: 
  1. **KEYRING**: cachyos keyrings update (all 14 days)
  2. **MIRROR**: cachyos mirror speedtest (all 28 days)
  3. **CARE**: tmp, cache, log and docker cleanup (all 7 days)
  4. **DEFRAG**: disk defrag and trim (all 7 days)
  5. pacman, paru and flatpak upgrades
- `alldown`: Same as `allup` but shuts down afterwards.
  Also always executes the **CARE** and **TRIM** scripts. 
  *On the way to bed you can execute this and leave your computer alone.*
- `allre`: Same as `allup` but triggers a restart via the desktop enviornment.
  Also never executes **KEYRING**, **MIRROR**, **CARE** or **TRIM**. Is an upgrade and restart only.
  If you have some system issue and you wanna check for updates and install them use this.
  *For the time of execution and until the system is started again you can go to the toilet or chill on your phone.*
  It does a quick upgrade with long lasting tasks and restart the system.
  **!!! WARNING:** Close all windows before execution, that could delay the restart or contain unsaved files.

## Installation

1. Clone this repository or place the scripts on your machine.
2. Then configure your shell’s config file with convenient aliases:
    - Bash: `~/.bashrc`
    - Fish: `~/.config/fish/config.fish`
    
    Make sure to adjust `MAJO_SCRIPT_DIR` to match your actual path.
    ### Bash
    ```bash
    MAJO_SCRIPT_DIR="~/ws/majo-cachyos-scripts"
    alias allup="$MAJO_SCRIPT_DIR/allup.sh"
    alias alltest="MAJO_SCRIPT_ACTION=test $MAJO_SCRIPT_DIR/allup.sh"
    alias allre="MAJO_SCRIPT_ACTION=restart $MAJO_SCRIPT_DIR/allup.sh"
    alias alldown="MAJO_SCRIPT_ACTION=poweroff $MAJO_SCRIPT_DIR/allup.sh"
    alias alledit="code $MAJO_SCRIPT_DIR/"
    alias codews="code $MAJO_SCRIPT_DIR/ws.code-workspace"
    ```

    ### Fish
    ```fish
    set -gx MAJO_SCRIPT_DIR ~/ws/majo-cachyos-scripts

    alias allup "$MAJO_SCRIPT_DIR/allup.sh"

    function alltest
        env MAJO_SCRIPT_ACTION=test $MAJO_SCRIPT_DIR/allup.sh
    end

    function allre
        env MAJO_SCRIPT_ACTION=restart $MAJO_SCRIPT_DIR/allup.sh
    end

    function alldown
        env MAJO_SCRIPT_ACTION=poweroff $MAJO_SCRIPT_DIR/allup.sh
    end

    alias alledit "code $MAJO_SCRIPT_DIR/"
    alias codews "code $MAJO_SCRIPT_DIR/ws.code-workspace"
    ```

3. After updating your shell's config, load the changes:
    - Bash: `source ~/.bashrc`
    - Fish: `source ~/.config/fish/config.fish`

4. Test them using `alltest`

## Script Parts

### Init Head

This section prepares execution and ensures the script runs safely.

- Enables strict execution (`set -ex`) to stop on errors and print commands.
- Captures the original user and home directory to avoid running as root directly.
- Defines working directories:
  - Script directory
  - Cache directory
- Builds a recursive command (`NEST_CMD`) to re-run the script with preserved environment variables.

Execution flow:
- If not inside tmux:
  - Refuses execution as root.
  - Requests sudo permissions.
  - Starts a tmux session (`allup`) and re-runs the script inside it.
- If inside tmux but not root:
  - Rotates logs (`logs/allup.log1 → log2 → log3`).
  - Re-executes the script as root while logging output.
- Final execution happens as root inside tmux.

A helper function `usersudo` is defined to run commands as the original (non-root) user when needed.

***

### CachyOS Keyring

This step ensures package signing keys are up to date.

- Uses a cache file: `cache/cachyos-keys`
- If missing or older than ~14 days:
  - Updates keyring via:
    - `pacman -Sy archlinux-keyring`
    - `pacman-key --refresh-keys`
  - Updates the cache timestamp

This avoids frequent key refreshes while preventing signature errors.

***

### CachyOS Mirror

This step maintains an optimized mirror list.

- Uses a cache file: `cache/cachyos-rate-mirrors`
- If missing or older than ~28 days:
  - Runs `cachyos-rate-mirrors`
  - Updates the cache timestamp

This ensures good download performance without running every time.

***

### Care Script (does some log, cache, tmp file and docker cleanup, docker if found)

This controls execution of `care.sh`.

- Performs cleanup tasks (logs, cache, tmp files, Docker if available).
- Executed via:
  ```
  sudo care.sh <original-user>
  ```

Execution conditions:
- Runs if:
  - Cache file is missing, or
  - Last run was more than 7 days ago
- Forced execution when:
  - Root filesystem usage exceeds 80%
  - `MAJO_SCRIPT_ACTION=poweroff` (cache marker is removed)

A cache file is updated after execution to track last run time.

***

### Defrag Script (only infos included, does disk trims and defrags on all disks)

This controls execution of `defrag.sh`.

- Performs disk trim and defragmentation across all disks.
- Executed via:
  ```
  sudo defrag.sh <original-user>
  ```

Execution conditions:
- Runs if:
  - Cache file is missing, or
  - Last run was more than 7 days ago

A cache file is updated after execution.

***

### Upgrade

Handles full system updates across package managers.

- System packages:
  - `pacman -Syu --noconfirm`
- AUR packages:
  - `paru -Syu --noconfirm --noremovemake`
  - `paru -Scc --noconfirm` (clean cache)
- Flatpak (if installed):
  - Updates apps
  - Removes unused packages
  - Repairs installations

If Flatpak is not available, this step is skipped.

***

### Script actions

Controls behavior before or after the update process using `MAJO_SCRIPT_ACTION`.

- `allup` (default, empty MAJO_SCRIPT_ACTION):
  - No reboot or shutdown
  - Waits for user input before exiting
- `alltest` (`MAJO_SCRIPT_ACTION=test`):
  - Tests if the scripts can be executed and does nothing.
- `allre` (`MAJO_SCRIPT_ACTION=restart`):
  - Schedules a reboot
  - Triggers immediate user session restart via KDE
- `alldown` (`MAJO_SCRIPT_ACTION=poweroff`):
  - Schedules shutdown
  - Triggers immediate user session shutdown via KDE

This allows flexible usage depending on whether you want to stay in the session, reboot, or power off after updates.
