#!/usr/bin/env bash

set -e

TARGET="${1:-}"
# Artifacts land wherever they were unzipped; check the plain Downloads drop
# first, then the per-run subdirectory `gh run download -D` creates.
UF2_DIRS=("${UF2_DIR:-$HOME/Downloads}" "${UF2_DIR:-$HOME/Downloads}/charybdis-fw")
MOUNT_POINT="/run/media/$USER/NICENANO"

usage() {
    echo "Usage: $0 [left|right|dongle-left|dongle-right|dongle]"
    echo ""
    echo "  left, right                 bt/usb format firmware"
    echo "  dongle-left, dongle-right   dongle format halves"
    echo "  dongle                      the dongle itself"
    echo ""
    echo "Set UF2_DIR to override the search root (default: \$HOME/Downloads)."
    exit 1
}

find_uf2() {
    local name="$1" dir
    for dir in "${UF2_DIRS[@]}"; do
        if [ -f "$dir/$name" ]; then
            echo "$dir/$name"
            return 0
        fi
    done
    return 1
}

wait_for_device() {
    echo "Waiting for NICENANO to appear..."
    for i in $(seq 1 20); do
        DEVICE=$(lsblk -rno NAME,SIZE | awk '$2 == "32.1M" {print "/dev/" $1}' | head -1)
        if [ -n "$DEVICE" ]; then
            echo "Found: $DEVICE"
            return 0
        fi
        sleep 0.5
    done
    echo "Error: NICENANO not found. Make sure you double-tapped reset."
    exit 1
}

flash() {
    local target="$1"
    local uf2_name uf2_file

    case "$target" in
        left)         uf2_name="charybdis_mini_LEFT.uf2" ;;
        right)        uf2_name="charybdis_mini_RIGHT.uf2" ;;
        dongle-left)  uf2_name="charybdis_mini_dongle_LEFT.uf2" ;;
        dongle-right) uf2_name="charybdis_mini_dongle_RIGHT.uf2" ;;
        dongle)       uf2_name="charybdis_mini_dongle.uf2" ;;
        *)            usage ;;
    esac

    if ! uf2_file=$(find_uf2 "$uf2_name"); then
        echo "Error: $uf2_name not found in: ${UF2_DIRS[*]}"
        exit 1
    fi

    echo "==> Flashing $target with $(basename "$uf2_file")"
    echo "    Double-tap reset now..."

    wait_for_device

    udisksctl mount -b "$DEVICE" 2>/dev/null || true

    if [ ! -d "$MOUNT_POINT" ]; then
        echo "Error: Could not mount $DEVICE"
        exit 1
    fi

    cp "$uf2_file" "$MOUNT_POINT/"
    echo "==> Done! Device will reboot automatically."
}

case "$TARGET" in
    left|right|dongle-left|dongle-right|dongle) flash "$TARGET" ;;
    *) usage ;;
esac
