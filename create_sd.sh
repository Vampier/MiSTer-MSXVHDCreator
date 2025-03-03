#!/bin/bash

DEVICE="/dev/sdb"
PARTITION="${DEVICE}1"
MOUNT_POINT="/mnt/sdcard"
PARTITION_SIZE="2000MiB"  # 2GB in MiB

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Please run as root (use sudo)." 
   exit 1
fi

echo "🚀 Unmounting existing partitions..."
sudo umount ${DEVICE}* 2>/dev/null

echo "🧹 Wiping existing partition table..."
sudo wipefs --all $DEVICE
sleep 2  

echo "📝 Creating new partition table (MSDOS)..."
sudo parted $DEVICE --script mklabel msdos
sleep 2

echo "🛠 Creating a ${PARTITION_SIZE} FAT16 partition..."
sudo parted $DEVICE --script mkpart primary fat16 1MiB $PARTITION_SIZE
sleep 3  

echo "🔄 Refreshing partition table..."
sudo partprobe $DEVICE
sudo udevadm trigger
sleep 3

echo "⏳ Waiting for partition to appear..."
for i in {1..5}; do
    if [ -e "$PARTITION" ]; then
        echo "✅ Partition detected: $PARTITION"
        break
    fi
    echo "⏳ Still waiting... ($i/5)"
    sleep 2
done

if [ ! -e "$PARTITION" ]; then
    echo "❌ Partition creation failed. Exiting."
    exit 1
fi

echo "💾 Formatting ${PARTITION} as FAT16..."
sudo mkfs.vfat -F 16 -n "MYDISK" $PARTITION  # Default settings work for 2GB
sleep 2

echo "📂 Creating mount point at $MOUNT_POINT..."
sudo mkdir -p $MOUNT_POINT

echo "🔗 Mounting ${PARTITION} to $MOUNT_POINT..."
sudo mount $PARTITION $MOUNT_POINT
sleep 2

echo "✅ Partitioning and formatting complete!"
lsblk -f

echo "⏏️ Ejecting the device..."
sudo eject $DEVICE
sleep 2

echo "🎉 Done! Your 2GB FAT16 partition is ready to use."
