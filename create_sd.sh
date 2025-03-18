#!/bin/bash

PARTITION1_SIZE="2000MiB"  # 2GB in MiB
MOUNT_POINT1="/mnt/sdcard"
MOUNT_POINT2="/mnt/sdcard2"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"  # Get the script's directory
DIR1="$SCRIPT_DIR/FAT16_P1_Files"           # Directory for FAT16 partition files
DIR2="$SCRIPT_DIR/FAT32_P2_Files"           # Directory for FAT32 partition files
MAX_SIZE_GB=257                             # Maximum size in GB

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[1;31mError:\e[0m This script must be run as root. Please use sudo."
    exit 1
fi

echo -e "\e[1;34m=== Starting Disk Partitioning Process ===\e[0m"

# Function to check and create directories
check_and_create_dir() {
    local dir=$1
    echo "Checking directory: $dir"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chmod 777 "$dir"
        echo -e "\e[1;32mCreated:\e[0m $dir with full access (rwxrwxrwx)"
    else
        echo -e "\e[1;33mDirectory already exists:\e[0m $dir (skipping creation)"
    fi
}

# Check and create required directories
check_and_create_dir "$DIR1"
check_and_create_dir "$DIR2"
echo "Place files in $DIR1 and $DIR2 to copy to the respective partitions."

# Function to list available devices under 257GB
list_devices() {
    echo -e "\e[1;34mDetecting available block devices (under 257GB)...\e[0m"
    mapfile -t DEVICES < <(lsblk -d -n -o NAME,TYPE,SIZE | awk '$3 ~ /[0-9]+G/ && int($3) < 257 && $2 == "disk" {print "/dev/"$1 " ("$3")"}')
    
    if [ ${#DEVICES[@]} -eq 0 ]; then
        echo -e "\e[1;31mError:\e[0m No suitable block devices found (must be under 257GB). Please insert a device and try again."
        exit 1
    fi
}

# Function to prompt user for confirmation
prompt_confirmation() {
    local message=$1
    local response
    read -p "$message (y/N): " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Main script starts here
list_devices
echo "Available devices:"
PS3="Select a device by number (or 'q' to quit): "
select DEVICE in "${DEVICES[@]}" "Quit"; do
    if [ "$DEVICE" = "Quit" ] || [ "$REPLY" = "q" ]; then
        echo -e "\e[1;33mProcess aborted by user.\e[0m"
        exit 0
    elif [ -n "$DEVICE" ]; then
        DEVICE=$(echo "$DEVICE" | awk '{print $1}')
        echo -e "\e[1;32mSelected device:\e[0m $DEVICE"
        break
    else
        echo -e "\e[1;31mInvalid selection.\e[0m Please choose a number from the list or 'q' to quit."
    fi
done

echo -e "\e[1;31mWARNING:\e[0m All data on $DEVICE will be erased."
if ! prompt_confirmation "Confirm selection"; then
    echo -e "\e[1;33mProcess aborted by user.\e[0m"
    exit 0
fi

PARTITION1="${DEVICE}1"
PARTITION2="${DEVICE}2"

echo "Unmounting existing partitions on $DEVICE..."
sudo umount ${DEVICE}* 2>/dev/null

echo "Wiping existing partition table on $DEVICE..."
sudo wipefs --all $DEVICE
sleep 2

echo "Creating new MSDOS partition table on $DEVICE..."
sudo parted $DEVICE --script mklabel msdos
sleep 2

echo "Creating $PARTITION1_SIZE FAT16 partition ($PARTITION1)..."
sudo parted $DEVICE --script mkpart primary fat16 1MiB $PARTITION1_SIZE
sleep 3

echo "Creating FAT32 partition with remaining space ($PARTITION2)..."
sudo parted $DEVICE --script mkpart primary fat32 $PARTITION1_SIZE 100%
sleep 3

echo "Refreshing partition table..."
sudo partprobe $DEVICE
sudo udevadm trigger
sleep 3

echo "Verifying partition creation..."
for i in {1..5}; do
    if [ -e "$PARTITION1" ] && [ -e "$PARTITION2" ]; then
        echo -e "\e[1;32mSuccess:\e[0m Partitions $PARTITION1 and $PARTITION2 detected."
        break
    fi
    echo "Waiting for partitions... (Attempt $i/5)"
    sleep 2
done

if [ ! -e "$PARTITION1" ] || [ ! -e "$PARTITION2" ]; then
    echo -e "\e[1;31mError:\e[0m Partition creation failed. Please check the device and try again."
    exit 1
fi

echo "Formatting $PARTITION1 as FAT16..."
sudo mkfs.vfat -F 16 -n "MYDISK16" $PARTITION1
sleep 2

echo "Formatting $PARTITION2 as FAT32..."
sudo mkfs.vfat -F 32 -n "MYDISK32" $PARTITION2
sleep 2

echo "Creating mount points..."
sudo mkdir -p $MOUNT_POINT1 $MOUNT_POINT2

echo "Mounting $PARTITION1 to $MOUNT_POINT1..."
sudo mount $PARTITION1 $MOUNT_POINT1
sleep 2

echo "Mounting $PARTITION2 to $MOUNT_POINT2..."
sudo mount $PARTITION2 $MOUNT_POINT2
sleep 2

echo "Copying files to FAT16 partition..."
sudo cp -r $DIR1/* $MOUNT_POINT1 2>/dev/null || echo -e "\e[1;33mWarning:\e[0m No files found in $DIR1."

echo "Copying files to FAT32 partition..."
sudo cp -r $DIR2/* $MOUNT_POINT2 2>/dev/null || echo -e "\e[1;33mWarning:\e[0m No files found in $DIR2."

echo -e "\e[1;34mPartitioning, formatting, and file copying completed successfully.\e[0m"

echo "Finalizing SD card - this can take a while. The SD card will be 'ejected' when device $DEVICE is ready"
sudo eject $DEVICE
sleep 2

echo -e "\e[1;32m=== Process Complete ===\e[0m"
echo "Your 2GB FAT16 ($PARTITION1) and remaining FAT32 ($PARTITION2) partitions are ready."
