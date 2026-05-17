# majo-cachyos-scripts

**Pure convenience, nothing more.**
Automated maintenance and upgrade scripts for CachyOS, designed to run non-interactively inside a controlled tmux session.

> **Notice:** Before usage, review the [Use at own risk](#use-at-own-risk) section.

## TOC

- [TOC](#toc)
- [Usage](#usage)
- [Requirements](#requirements)
  - [Required](#required)
  - [Usually already installed on CachyOS](#usually-already-installed-on-cachyos)
  - [Optional](#optional)
- [Installation](#installation)
- [Configuration](#configuration)
- [AUR Updates](#aur-updates)
- [`allup` Script](#allup-script)
  - [Execution Flow](#execution-flow)
  - [Security Features](#security-features)
  - [Automation Features](#automation-features)
- [Tricks](#tricks)
  - [Scrollable tmux sessions:](#scrollable-tmux-sessions)
- [Use at own risk](#use-at-own-risk)
- [Contribution](#contribution)
- [Thanks](#thanks)


## Usage

- `alltest`: Does nothing only as setup test.
- `allup`:  
  1. **KEYRING**: cachyos keyrings update (all 14 days)
  2. **MIRROR**: cachyos mirror speedtest (all 28 days)
  3. **CLEANUP**: tmp, cache, log and docker cleanup (all 7 days)
  4. **DEFRAG**: disk defrag and trim (all 7 days)
  5. pacman, paru and flatpak upgrades
- `alldown`: Same as `allup` but shuts down afterwards.  
  Also always executes the **CLEANUP** and **TRIM** scripts.  
  *On the way to bed you can execute this and leave your computer alone.*
- `allre`: Same as `allup` but triggers a restart via the desktop environment.  
  Also does not execute any tasks except the upgrades and the reboot.
  If you have some system issue and you wanna check for updates and install them use this.  
  *For the time of execution and until the system is started again you can go to the toilet or chill on your phone.*
  It does a quick upgrade with long lasting tasks and restart the system.  
  **!!! WARNING:** Close all windows before execution, that could delay the restart or contain unsaved files.

## Requirements

### Required
- CachyOS
- `tmux` - install via: `sudo pacman -S tmux`

### Usually already installed on CachyOS
- `sudo`
- `pacman`


### Optional

Following also run if installed:
- `paru`: upgrade and cleanup (not for aur packages: no stable non-interactive interface)
- `flatpak`: upgrade, uninstall unused and repair
- `docker`: cleanup
- KDE Plasma or GNOME for **graceful** reboot / shutdown

You can replace the code command in the aliases with any editor:
- Code OSS (vscode from opensource)
- VSCodium 
- MS - Visual Studio Code
- or remove the aliases
- or replace it with your editor:
  - vim (exit = ESC>`:!q`>ENTER)

## Installation

1. Clone this repository or place the scripts on your machine.
2. Then configure your shell’s config file with convenient aliases:
    - Bash: `~/.bashrc`
    - Fish: `~/.config/fish/config.fish`
    
    Make sure to adjust `MAJO_SCRIPT_DIR` to match your actual clone path.
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

## Configuration

You can configure the cache time and interactive paru aur package updates via a `.env` file. Just create a `.env` in the cloned root dir or copy the existing `.env.defaults` file: `cp .env.defaults .env`.

## AUR Updates
Neither `paru` and `yay` offers an effective method for performing non-interactive, unattended updates.

I added a configuration to allow interactive AUR updates via paru when enabled and its not a restart/reboot or poweroff/shutdown of your host.

So `alldown` and `allre` will never do a AUR update. That will only work when you use `allup` with `INTERACTIVE_AUR=true`.

## `allup` Script

### Execution Flow

This are the script stages:
1. **User:** Validates environment and restarts self inside `tmux`
2. **Tmux:** Rotates logs and escalates to a persistent root shell
3. **Root:** Loads `.env` configurations and validates cache timers
4. **Maintenance:** If expired, executes:
   1. Cleanup (see `cleanup.sh`),
   2. Keyring,
   3. Mirror, 
   4. and Defrag (see `defrag.sh`),
5. **Upgrade:** Runs the full update stack: Pacman -> Paru -> Flatpak
6. **Reboot/Poweroff/Exit:** Executes a final action depending on the action variable

### Security Features

- **Session Persistence**: By forcing execution inside a `tmux` session, the update process is decoupled from the terminal emulator. If the GUI crashes during a driver update or the connection drops, the process continues safely in the background.
- **Injection Proofing**: Environment variables (`MAJO_SCRIPT_ACTION`, `ORIGIN_USER`, etc.) are sanitized using `printf %q` before being passed to nested shells. This prevents command injection and ensures that variables containing special characters are handled as literal strings.

### Automation Features

- **Stateful Caching**: Execution is governed by time-based logic. The script compares the current Unix timestamp against the modification time of flag files in the `cache/` directory. This ensures intensive tasks like mirror rating or keyring refreshes only run when necessary.
- **Log Rotation**: Automatically rotates the last three execution logs (`allup.log1` to `log3`) before starting a new run.
- **Dynamic Cleanup**: Automatically triggers system cleanup if the root partition exceeds **80% utilization**, regardless of the cache state.
- **Keyring Management**: Refreshes the Arch Linux keyring and local keys periodically to prevent signature errors during large updates.
- **Graceful Shutdowns first**: Integrates with KDE Plasma and GNOME. The script requests a graceful desktop environment session logout and shutdown. This allows the desktop environment to save application states and close windows properly. After some time the system issues a hard `shutdown` or `reboot`.
- **Root Persistence:**: The script escalates to a full root shell immediately. This prevents `sudo` credential timeouts during long-running tasks like disk defragmentation or large cleanups, ensuring that subsequent `pacman` or `paru` commands do not hang on a hidden password prompt.
- **Context Awareness**: Because the script executes as root for the **Root Persistence**, it utilizes a `usersudo` wrapper to drop privileges for user-land tasks (AUR helpers, Flatpak, and DBus calls) to maintain security and ensure configuration files remain owned by the original user.
- **Fail-safe Shutdown Timer:** Implements a 1-minute system-level hardware fallback (`shutdown +1`) that triggers if the GUI session manager (GNOME/KDE) hangs during the graceful logout attempt.
- **Persistent Configuration**: A DotEnv `.env` File in the scripts dir to configure some options. The `.env.defaults` contains all optional variables.
- **Dual-Stream Logging:** Uses `tee` to provide real-time terminal feedback while simultaneously capturing all output (including standard error) into the rotated log files.
* 

## Tricks

### Scrollable tmux sessions:

Configure tmux system-wide to allow the mouse wheel to scroll in tmux sessions:
```bash
sudo bash -c 'cat > /etc/tmux.conf << "EOF"
  set -g mouse on
  setw -g mode-keys vi

  bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'copy-mode -e; send-keys -M'"
  bind -n WheelDownPane select-pane -t= \; send-keys -M

  bind-key -T copy-mode-vi WheelUpPane send-keys -X halfpage-up
  bind-key -T copy-mode-vi WheelDownPane send-keys -X halfpage-down
EOF'
chmod 664 /etc/tmux.conf
```

## Use at own risk

This software is provided **as is**, without warranty of any kind. By using these scripts, you acknowledge that you are doing so entirely at your **own discretion and risk**.

The author shall not be held liable for any damages, including but not limited to system instability, data loss, or corrupted configurations resulting from the automated nature of these scripts. It is your responsibility to audit the code and ensure it is compatible with your specific environment before execution.

## Contribution

Contributions, suggestions, and bug reports are highly encouraged to help improve this project.

- Any feature request is welcome, but not everything can be implemented. 
- **Feedback:** Please use the GitHub Issues function to submit recommendations or report problems.
- **Pull Requests:** Feel free to fork the repository and submit improvements for review.
- **Contact:** For direct inquiries or to avoid long wait times, you can reach out to the author via the Discord link provided on the owner's GitHub profile page.
- Add a notice if you added untested or AI informations to the issue.
- If you are an AI submitting an issue add `[AI]` at the beginning of the text. Humans also need context awareness and i can act properly when i know there is mostly an AI on the other end.
- For specific platforms or commands, please also provide the necessary commands.
  - Dont just say: 
    ```txt
    Add support for X
    ```
  - Provide true, detailed and necessary information, such as:
    ```txt
    Hi,
    support for the desktop environment X would be great. 
    It uses the following commands for proper restart and shutdown. 
    `...` 

    You could use the following statement to check whether the user is logged in to the system. 
    `...`
    ```
    or
    ```txt
    Hi,
    could you open up the script for the operating system X too?

    For the mirror optimization you can use X.
    It uses X file system by default. Use following for defrag and trim:
    `...`

    I use the X package manager. An optional update could look like:
    `...`
    ```

## Thanks

Cya,  
*~NobleMajo*