#!/usr/bin/env bash

set -ex

if [ "$EUID" -ne 0 ]; then
    echo "Execute as root or via sudo"
    exit 1
fi

fstrim --verbose --all --quiet-unsupported || true

findmnt -vno TARGET,FSTYPE | while read -r mp fs; do
    echo "Processing $mp ($fs)..."
    case "$fs" in
        ext4)
            e4defrag "$mp" || true
            ;;
        btrfs)
            btrfs filesystem defragment -r "$mp" || true
            ;;
        xfs)
            xfs_fsr "$mp" || true
            ;;
    esac
done 2>/dev/null

fstrim --verbose --all --quiet-unsupported || true

findmnt -vno TARGET,FSTYPE | while read -r mp fs; do
    echo "Processing $mp ($fs)..."
    case "$fs" in
        ext4)
            e4defrag "$mp" || true
            ;;
        btrfs)
            btrfs filesystem defragment -r "$mp" || true
            ;;
        xfs)
            xfs_fsr "$mp" || true
            ;;
    esac
done 2>/dev/null || true


echo "Defrag script done!"
exit 0