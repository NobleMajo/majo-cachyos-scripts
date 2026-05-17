#!/usr/bin/env bash

set -e

export LC_NUMERIC=C

ORIGIN_USER="${1:-$USER}"
ORIGIN_HOME="${2:-$HOME}"

SCRIPTS_DIR=$(dirname "$(readlink -f "$0")")
WORKER_SCRIPT="$SCRIPTS_DIR/disk-tester-worker.sh"
TMUX_SESSION_ARG="${3:-$TMUX}"

cleanup() {
    local exit_code=$?
    if [[ -n "${TEST_DIR_TMP:-}" && -d "$TEST_DIR_TMP" ]]; then
        rm -rf "$TEST_DIR_TMP" 2>/dev/null || true
    fi
    if [[ -n "${TEST_DIR_WRITE:-}" && -d "$TEST_DIR_WRITE" ]]; then
        rm -rf "$TEST_DIR_WRITE" 2>/dev/null || true
    fi
    if [ "$TMUX_SESSION_ARG" == "tmux_active" ]; then
        echo
        echo "----------------------------------------"
        echo "Session finished (Exit Code: $exit_code)."
        echo "Press Enter to exit tmux..."
        echo "----------------------------------------"
        read -r
    fi
}
trap cleanup EXIT

if [ "$TMUX_SESSION_ARG" == "" ]; then
    if [ "$EUID" == 0 ]; then
        echo "Error: Cannot be executed as root user directly, please use the non-root sudo user."
        exit 1
    fi

    echo "Root access required for hardware testing..."
    sudo echo "Root access granted!"

    echo "Starting tmux session..."
    sudo tmux new-session -A -s disktest "$(readlink -f "$0")" "$ORIGIN_USER" "$ORIGIN_HOME" "tmux_active"
    echo "Tmux session closed."
    exit 0
fi

if [ "$EUID" != 0 ]; then
    mkdir -p "$SCRIPTS_DIR/logs" || true
    mv -f "$SCRIPTS_DIR/logs/disktest.log2" "$SCRIPTS_DIR/logs/disktest.log3" >/dev/null 2>&1 || true
    mv -f "$SCRIPTS_DIR/logs/disktest.log1" "$SCRIPTS_DIR/logs/disktest.log2" >/dev/null 2>&1 || true

    echo "Starting root execution..."
    sudo su root -c "$(readlink -f "$0") $ORIGIN_USER $ORIGIN_HOME tmux_active 2>&1 | tee -a $SCRIPTS_DIR/logs/disktest.log1"
    exit 0
fi

if [ "${ORIGIN_USER//\\/}" == "root" ]; then
    echo "Error: Cannot run as root user payload, use the non-root sudo user."
    exit 1
fi

if [ "${ORIGIN_HOME//\\/}" == "/root" ]; then
    echo "Error: Cannot run with root home directory."
    exit 1
fi

export TMP_DIR="${TMP_DIR:-/tmp}"

if [[ ! -f "$WORKER_SCRIPT" ]]; then
    echo "ERROR: worker script not found: $WORKER_SCRIPT" >&2
    exit 1
fi

declare -a mounts=()
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^\[ ]] && continue
    if [[ "$line" == "/" || "$line" =~ ^/(boot|home|var|run/media|mnt) ]]; then
        mounts+=("$line")
    fi
done < <(lsblk -nro MOUNTPOINTS 2>/dev/null | sed "s/\\\\x0a/\\n/g" | grep -v "^$" | sort -u || true)

if [[ "${#mounts[@]}" -eq 0 ]]; then
    echo "ERROR: No mounted block devices found." >&2
    exit 1
fi

declare -a test_mounts=()
declare -a test_sizes=()
declare -a test_bss=()
declare -a result_write_int=()
declare -a result_read_int=()
declare -a result_write_time=()
declare -a result_write_speed=()
declare -a result_read_time=()
declare -a result_read_speed=()

select_mount() {
    echo "Available Mounted paths:"
    for i in "${!mounts[@]}"; do
        echo "$((i + 1))) ${mounts[$i]}"
    done
    echo

    local choice
    read -rp "Select mount index [1-${#mounts[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "${#mounts[@]}" ]]; then
        echo "ERROR: Invalid index selected." >&2
        exit 1
    fi
    SELECTED_MOUNT="${mounts[$((choice - 1))]}"
}

ask_test_config() {
    local size bs
    read -rp "File size (GB, default 1): " size
    size="${size:-1}"
    if [[ ! "$size" =~ ^[0-9]+$ ]] || [[ "$size" -le 0 ]]; then
        echo "ERROR: Size must be a positive integer." >&2
        exit 1
    fi

    read -rp "Block size (MB, default 10): " bs
    bs="${bs:-10}"
    if [[ ! "$bs" =~ ^[0-9]+$ ]] || [[ "$bs" -le 0 ]]; then
        echo "ERROR: Block size must be a positive integer." >&2
        exit 1
    fi

    test_mounts+=("$SELECTED_MOUNT")
    test_sizes+=("$size")
    test_bss+=("$bs")
}

select_mount
ask_test_config

while true; do
    echo
    read -rp "Add an additional test configuration? (y/N): " yn
    yn="${yn:-n}"
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
        break
    fi
    echo
    ask_test_config
done

echo
echo "Executing hardware benchmark workflow..."

for i in "${!test_mounts[@]}"; do
    m="${test_mounts[$i]}"
    s="${test_sizes[$i]}"
    bs_mb="${test_bss[$i]}"

    echo "Running configuration $((i + 1))/${#test_mounts[@]} (${s} GB, ${bs_mb} MB) on $m..."

    output=$(bash "$WORKER_SCRIPT" "$m" "$s" "$bs_mb" 2>&1 || true)
    echo "$output"

    w_int=$(echo "$output" | grep "^WRITE_INTEGRITY=" | cut -d= -f2- || true)
    r_int=$(echo "$output" | grep "^READ_INTEGRITY=" | cut -d= -f2- || true)
    w_t=$(echo "$output" | grep "^WRITE_TIME=" | cut -d= -f2 || true)
    w_s=$(echo "$output" | grep "^WRITE_SPEED=" | cut -d= -f2 || true)
    r_t=$(echo "$output" | grep "^READ_TIME=" | cut -d= -f2 || true)
    r_s=$(echo "$output" | grep "^READ_SPEED=" | cut -d= -f2 || true)

    if [[ -z "$w_int" && -z "$r_int" ]]; then
        w_int="Error: Execution failed completely"
        r_int="Error: Execution failed completely"
    fi

    result_write_int+=("${w_int:-Error: Unknown}")
    result_read_int+=("${r_int:-Pending}")
    result_write_time+=("${w_t:-0.00}")
    result_write_speed+=("${w_s:-0.00}")
    result_read_time+=("${r_t:-0.00}")
    result_read_speed+=("${r_s:-0.00}")
done

printf "\n%s\n" "----------------------------------------"
printf "%s\n" "ALL TEST RESULTS SUMMARY"
printf "%s\n" "----------------------------------------"

for i in "${!test_mounts[@]}"; do
    printf "Configuration #%d:\n" "$((i + 1))"
    printf "  Mount point:     %s\n" "${test_mounts[$i]}"
    printf "  File size:       %s GB\n" "${test_sizes[$i]}"
    printf "  Block size:      %s MB\n" "${test_bss[$i]}"
    printf "  Write Integrity: %s\n" "${result_write_int[$i]}"
    printf "  Read Integrity:  %s\n" "${result_read_int[$i]}"
    printf "  Write Time:      %s s\n" "${result_write_time[$i]}"
    printf "  Write Speed:     %s MB/s\n" "${result_write_speed[$i]}"
    printf "  Read Time:       %s s\n" "${result_read_time[$i]}"
    printf "  Read Speed:      %s MB/s\n" "${result_read_speed[$i]}"
    printf "%s\n" "----------------------------------------"
done

total_write_time=0
total_read_time=0
total_write_mb=0
total_read_mb=0

for i in "${!test_mounts[@]}"; do
    w_t="${result_write_time[$i]}"
    r_t="${result_read_time[$i]}"
    s_mb=$((${test_sizes[$i]} * 1024))

    if [[ "$w_t" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        total_write_time=$(awk "BEGIN {print $total_write_time + $w_t}")
    fi
    if [[ "$r_t" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        total_read_time=$(awk "BEGIN {print $total_read_time + $r_t}")
    fi

    if [[ "$w_t" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN {exit !($w_t > 0)}"; then
        total_write_mb=$((total_write_mb + s_mb))
    fi
    if [[ "$r_t" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN {exit !($r_t > 0)}"; then
        total_read_mb=$((total_read_mb + s_mb))
    fi
done

avg_w_s="0.00"
if awk "BEGIN {exit !($total_write_time > 0)}"; then
    avg_w_s=$(awk "BEGIN {printf \"%.2f\", $total_write_mb / $total_write_time}")
fi

avg_r_s="0.00"
if awk "BEGIN {exit !($total_read_time > 0)}"; then
    avg_r_s=$(awk "BEGIN {printf \"%.2f\", $total_read_mb / $total_read_time}")
fi

printf "\n%s\n" "========================================"
printf "%s\n" "OVERALL BENCHMARK STATISTICS"
printf "%s\n" "========================================"
printf "  Total Write Time: %.2f s\n" "$total_write_time"
printf "  Total Read Time:  %.2f s\n" "$total_read_time"
printf "  Avg Write Speed:  %s MB/s\n" "$avg_w_s"
printf "  Avg Read Speed:   %s MB/s\n" "$avg_r_s"
printf "%s\n" "========================================"