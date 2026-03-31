#!/usr/bin/env bash

set -e

SIDE="${1:-}"
UF2_DIR="$HOME/Downloads"
MOUNT_POINT="/run/media/$USER/NICENANO"

usage() {
    echo "Usage: $0 [left|right]"
    exit 1
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
    local side="$1"
    local uf2_file

    case "$side" in
        left)  uf2_file="$UF2_DIR/charybdis_mini_LEFT.uf2" ;;
        right) uf2_file="$UF2_DIR/charybdis_mini_RIGHT.uf2" ;;
        *)     usage ;;
    esac

    if [ ! -f "$uf2_file" ]; then
        echo "Error: $uf2_file not found."
        exit 1
    fi

    echo "==> Flashing $side side with $(basename $uf2_file)"
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

case "$SIDE" in
    left|right) flash "$SIDE" ;;
    *) usage ;;
esac
