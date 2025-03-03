#!/bin/bash

# Exit on any error
set -e

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root!" >&2
    exit 1
fi

# Define constants
readonly IMAGE="disk.img"
readonly MOUNT_POINT="/mnt/fat16"
readonly FILE_SOURCE="FilesForOCMCore"

# Function to cleanup on exit or error
cleanup() {
    echo "Cleaning up..."
    # Unmount if mounted
    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT" || echo "Warning: Failed to unmount $MOUNT_POINT" >&2
    fi
    # Detach loop device if set
    if [[ -n "$LOOPDEV" ]]; then
        losetup -d "$LOOPDEV" || echo "Warning: Failed to detach $LOOPDEV" >&2
    fi
}

# Trap errors and exit to ensure cleanup
trap cleanup EXIT ERR

# Check if source directory exists
if [[ ! -d "$FILE_SOURCE" ]]; then
    echo "Error: Source directory '$FILE_SOURCE' not found!" >&2
    exit 1
fi

# Create a 1GB raw image with sparse file support
echo "Creating disk image..."
dd if=/dev/zero of="$IMAGE" bs=1M count=0 seek=1024 status=progress

# Partition the image using fdisk
echo "Partitioning image..."
printf "n\np\n1\n\n\n\nt\n6\nw\n" | fdisk "$IMAGE" >/dev/null 2>&1

# Attach loop device
echo "Setting up loop device..."
LOOPDEV=$(losetup -fP --show "$IMAGE") || {
    echo "Error: Failed to setup loop device!" >&2
    exit 1
}

# Format the partition as FAT16
echo "Formatting as FAT16..."
mkfs.fat -F 16 "${LOOPDEV}p1" >/dev/null || {
    echo "Error: Failed to format partition!" >&2
    exit 1
}

# Create and mount point
echo "Mounting partition..."
mkdir -p "$MOUNT_POINT"
mount "${LOOPDEV}p1" "$MOUNT_POINT" || {
    echo "Error: Failed to mount partition!" >&2
    exit 1
}

# Copy files with progress
echo "Copying files..."
cp -rv "$FILE_SOURCE"/* "$MOUNT_POINT" || {
    echo "Error: Failed to copy files!" >&2
    exit 1
}

# Set permissions (using more restrictive 666 instead of 777)
chmod 666 "$IMAGE"

echo "Disk image '$IMAGE' successfully created, formatted as FAT16, and files copied."

