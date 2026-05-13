#!/usr/bin/env bash

set -euo pipefail

# LOAD VARIABLES

set -o allexport

source .env.defaults

if [ -f .env ]; then
    source .env
fi

set +o allexport

# VALIDATE VARIABLES

if [[ -z "${ZIPLINE_SCREENSHOT_UPLOAD_TOKEN}" ]]; then
    echo "Error: ZIPLINE_SCREENSHOT_UPLOAD_TOKEN environment variable must be set and non-empty" >&2
    exit 1
fi

if [[ -z "${ZIPLINE_SCREENSHOT_UPLOAD_URL}" ]]; then
    echo "Error: ZIPLINE_SCREENSHOT_UPLOAD_URL environment variable must be set and non-empty" >&2
    exit 1
fi

# START SCRIPT

TEMP_FILE=$(mktemp --suffix=.png)

cleanup() {
    rm -f "$TEMP_FILE"
}

trap cleanup EXIT

### check missing deps
missingDeps=()
for cmd in spectacle curl jq wl-copy notify-send; do
    
cmd="spectacle"
if ! command -v "$cmd" >/dev/null 2>&1; then
    missingDeps+=("$cmd")
fi

cmd="curl"
if ! command -v "$cmd" >/dev/null 2>&1; then
    missingDeps+=("$cmd")
fi

cmd="jq"
if ! command -v "$cmd" >/dev/null 2>&1; then
    missingDeps+=("$cmd")
fi

cmd="wl-copy"
if ! command -v "$cmd" >/dev/null 2>&1; then
    missingDeps+=("$cmd")
fi

cmd="notify-send"
if ! command -v "$cmd" >/dev/null 2>&1; then
    missingDeps+=("$cmd")
fi

if [[ ${#missingDeps[@]} -gt 0 ]]; then
    notify-send "Zipline Error" "Missing dependencies: ${missingDeps[*]}" -u critical
    exit 1
fi

### take screenshot
spectacle -rbno "$TEMP_FILE"
if [[ ! -s "$TEMP_FILE" ]]; then
    exit 0
fi

### upload
response=$(curl -s -w "\n%{http_code}" -L -4 \
    -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36" \
    -H "authorization: $ZIPLINE_SCREENSHOT_UPLOAD_TOKEN" \
    -H "x-zipline-authorization: $ZIPLINE_SCREENSHOT_UPLOAD_TOKEN" \
    -F "file=@$TEMP_FILE" \
    "$ZIPLINE_SCREENSHOT_UPLOAD_URL")

http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | sed '$ d')

if [[ "$http_code" -ne 200 ]]; then
    notify-send "Zipline Error" "Upload failed with HTTP $http_code" -u critical
    exit 1
fi

### extract url
url=$(echo "$response" | jq -r '.files[0].url // .files[0] // empty' 2>/dev/null || true)

if [[ -z "$url" || "$url" == "null" ]]; then
    url=$(echo "$response" | grep -oE 'https?://[^"]+' | head -n 1 || true)
fi

if [[ -z "$url" ]]; then
    notify-send "Zipline Error" "Failed to parse URL from response" -u critical
    exit 1
fi

### copy url to clipboard
echo -n "$url" | wl-copy

### send notification
notify-send "Zipline" "Upload successful. Link copied." -i camera-photo