#!/usr/bin/env bash

set -euo pipefail

export LC_NUMERIC=C

MOUNT_PATH="${1:?}"
FILE_SIZE_GB="${2:?}"
BS_MB="${3:?}"
TMP_DIR="${TMP_DIR:-/tmp}"

TEST_UID=$(echo -n "$MOUNT_PATH" | md5sum | awk '{print $1}')

TEST_DIR_TMP="$TMP_DIR/test-$TEST_UID"
TEST_DIR_WRITE="$MOUNT_PATH/test-$TEST_UID"

BASE_DATA="$TEST_DIR_TMP/base-data"
WRITE_DATA="$TEST_DIR_WRITE/write-data"
READ_DATA="$TMP_DIR/test-$TEST_UID/read-data"

if [[ -d "$TEST_DIR_TMP" ]]; then
    rm -rf "$TEST_DIR_TMP"
fi

if [[ -d "$TEST_DIR_WRITE" ]]; then
    rm -rf "$TEST_DIR_WRITE"
fi

mkdir -p "$TEST_DIR_TMP"
mkdir -p "$TEST_DIR_WRITE"

trap 'rm -rf "$TEST_DIR_TMP" "$TEST_DIR_WRITE" 2>/dev/null || true' EXIT

COUNT=$(( (FILE_SIZE_GB * 1024) / BS_MB ))
BS="${BS_MB}M"

if ! dd if=/dev/urandom of="$BASE_DATA" bs="$BS" count="$COUNT" status=none 2>/dev/null; then
    echo "WRITE_INTEGRITY=Error: Failed to generate base data."
    echo "READ_INTEGRITY=Pending"
    exit 0
fi

HASH1=$(md5sum "$BASE_DATA" | awk '{print $1}')

START_WRITE=$(date +%s.%N)
if ! dd if="$BASE_DATA" of="$WRITE_DATA" bs="$BS" status=none 2>/dev/null; then
    echo "WRITE_INTEGRITY=Error: Failed to write to disk."
    echo "READ_INTEGRITY=Pending"
    exit 0
fi
sync
END_WRITE=$(date +%s.%N)

TIME_WRITE=$(awk "BEGIN {print $END_WRITE - $START_WRITE}")
SPEED_WRITE=$(awk "BEGIN {print ($FILE_SIZE_GB * 1024) / $TIME_WRITE}")

HASH2=$(md5sum "$WRITE_DATA" | awk '{print $1}')

if [[ "$HASH1" != "$HASH2" ]]; then
    echo "WRITE_INTEGRITY=Mismatch ($HASH1 / $HASH2)"
    echo "READ_INTEGRITY=Pending"
    printf "WRITE_TIME=%.2f\nWRITE_SPEED=%.2f\n" "$TIME_WRITE" "$SPEED_WRITE"
    exit 0
fi

echo "WRITE_INTEGRITY=Fine"

sync
if [ "$EUID" -eq 0 ]; then
    echo 3 > /proc/sys/vm/drop_caches
else
    sudo sysctl vm.drop_caches=3 >/dev/null 2>&1 || true
fi

START_READ=$(date +%s.%N)
if ! dd if="$WRITE_DATA" of="$READ_DATA" bs="$BS" status=none 2>/dev/null; then
    echo "READ_INTEGRITY=Error: Failed to read from disk."
    printf "WRITE_TIME=%.2f\nWRITE_SPEED=%.2f\n" "$TIME_WRITE" "$SPEED_WRITE"
    exit 0
fi
sync
END_READ=$(date +%s.%N)

TIME_READ=$(awk "BEGIN {print $END_READ - $START_READ}")
SPEED_READ=$(awk "BEGIN {print ($FILE_SIZE_GB * 1024) / $TIME_READ}")

HASH3=$(md5sum "$READ_DATA" | awk '{print $1}')

if [[ "$HASH1" != "$HASH3" ]]; then
    echo "READ_INTEGRITY=Mismatch ($HASH2 / $HASH3)"
else
    echo "READ_INTEGRITY=Fine"
fi

printf "WRITE_TIME=%.2f\nWRITE_SPEED=%.2f\nREAD_TIME=%.2f\nREAD_SPEED=%.2f\n" "$TIME_WRITE" "$SPEED_WRITE" "$TIME_READ" "$SPEED_READ"
exit 0