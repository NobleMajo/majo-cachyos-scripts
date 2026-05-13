#!/usr/bin/env bash

set -euo pipefail

TOKEN="MTc3Mjk3NDM3Mzk2NQ==.ZjE5ZTE1NWRkNjAzNWU4YjczZjM4ZjBjLjg4MDJmODkyMzYxNTZlZDUwZTQ3Y2NkMThlZDViM2NjNThhMTQ0M2U5ZDg0YTUzMzA4N2I4OGMxNWI1OGZhMDlkZmRkNjQzMjg2NWQ1OWU0OGE2MzA4ZWM4MDk2NDYwZWRiYmViYWEyMDZhNWMzN2Q4ZGU5NzhmMjE3ZTJlNDhmODMuMzVlNWFmMDY2ODgxY2QzMTY3MmZkMWIyZjc3MTBhZjg="
URL="https://screens.coreunit.net/api/upload"
TEMP_FILE=$(mktemp --suffix=.png)

cleanup() {
    rm -f "$TEMP_FILE"
}

trap cleanup EXIT

check_dependencies() {
    local missing=()
    for cmd in spectacle curl jq wl-copy notify-send; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        notify-send "Zipline Error" "Missing dependencies: ${missing[*]}" -u critical
        exit 1
    fi
}

take_screenshot() {
    spectacle -rbno "$TEMP_FILE"
    if [[ ! -s "$TEMP_FILE" ]]; then
        exit 0
    fi
}

upload_screenshot() {
    local response
    local http_code
    local response_body

    response=$(curl -s -w "\n%{http_code}" -L -4 \
        -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36" \
        -H "authorization: $TOKEN" \
        -H "x-zipline-authorization: $TOKEN" \
        -F "file=@$TEMP_FILE" \
        "$URL")

    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | sed '$ d')

    if [[ "$http_code" -ne 200 ]]; then
        notify-send "Zipline Error" "Upload failed with HTTP $http_code" -u critical
        exit 1
    fi

    echo "$response_body"
}

extract_url() {
    local response="$1"
    local url

    url=$(echo "$response" | jq -r '.files[0].url // .files[0] // empty' 2>/dev/null || true)

    if [[ -z "$url" || "$url" == "null" ]]; then
        url=$(echo "$response" | grep -oE 'https?://[^"]+' | head -n 1 || true)
    fi

    if [[ -z "$url" ]]; then
        notify-send "Zipline Error" "Failed to parse URL from response" -u critical
        exit 1
    fi

    echo "$url"
}

main() {
    check_dependencies
    take_screenshot
    
    local response
    response=$(upload_screenshot)
    
    local url
    url=$(extract_url "$response")
    
    echo -n "$url" | wl-copy
    notify-send "Zipline" "Upload successful. Link copied." -i camera-photo
}

main "$@"