#!/bin/bash

# Based on the tutorial from pgimeno
# https://www.msx.org/forum/msx-talk/hardware/emulating-msx-on-the-mister-fpga?page=1

clear

# Variables 
ContentDir="./FilesForOCMCore"
BIOSFileURL="https://github.com/MiSTer-devel/MSX_MiSTer/raw/master/Utils/sdcreate.zip"
BIOSFileName="sdcreate.zip"
UnZIPPath="sdbios/OCM-BIOS.DAT"

# Define color codes
bg='\033[44m'       	# Blue background
fw='\033[97m' 		# Bright White text
fc='\033[1;36m'		# Bright Cyan text
fg='\033[1;32m'		# Bright Green text
rt='\033[0m'         	# Reset to default colors

echo -e "${bg}${fw}███╗   ███╗███████╗██╗  ██╗    ██╗   ██╗██╗  ██╗██████╗      ██████╗██████╗ ███████╗ █████╗ ████████╗ ██████╗ ██████╗ "
echo -e "${bg}${fw}████╗ ████║██╔════╝╚██╗██╔╝    ██║   ██║██║  ██║██╔══██╗    ██╔════╝██╔══██╗██╔════╝██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗"
echo -e "${bg}${fw}██╔████╔██║███████╗ ╚███╔╝     ██║   ██║███████║██║  ██║    ██║     ██████╔╝█████╗  ███████║   ██║   ██║   ██║██████╔╝"
echo -e "${bg}${fw}██║╚██╔╝██║╚════██║ ██╔██╗     ╚██╗ ██╔╝██╔══██║██║  ██║    ██║     ██╔══██╗██╔══╝  ██╔══██║   ██║   ██║   ██║██╔══██╗"
echo -e "${bg}${fw}██║ ╚═╝ ██║███████║██╔╝ ██╗     ╚████╔╝ ██║  ██║██████╔╝    ╚██████╗██║  ██║███████╗██║  ██║   ██║   ╚██████╔╝██║  ██║"
echo -e "${bg}${fc}╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝      ╚═══╝  ╚═╝  ╚═╝╚═════╝      ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝"
echo -e "${bg}${fc}$ascii_logo"                                                                                           
echo -e "${rt}"

###### Begin of Functions

# Function to install a package if it's not found
	install_package() {
	    package=$1
	    if ! command -v "$package" &> /dev/null; then
		echo -e "$package not found. Installing $package..."
		sudo apt update
		sudo apt install -y "$package"
		if ! command -v "$package" &> /dev/null; then
		    echo -e "Failed to install $package. Please install it manually."
		    exit 1
		else
		    echo -e "$package installed successfully."
		fi
	    else
		echo -e "$package is already installed."
	    fi
	}

	copy_directories_to_image() {
		local source_dir="$1"
		local target_dir="$2"

		echo -e
		echo -e "${fw}Copying content of $source_dir to $target_dir"

		# Check if the directory exists
		if [ -d "$source_dir" ]; then
			# List directories in the root of the source directory
			for dir in "$source_dir"/*; do
				if [ -d "$dir" ]; then
					echo -e "${fc}Syncing ${fw}$(basename "$dir") ${fc}to ${fw}$target_dir"
					mcopy -i "${FileName}@@512" -s "$dir" "$target_dir"
				fi
			done
		fi
		echo -e "${rt} Dir sync complete"
	}
	
	copy_files_to_image() {
		local source_dir="$1"
		local target_dir="$3"

		local offset="512"  # Hardcoded offset value

		echo -e
		echo -e "${fw}Copying files from $source_dir to $FileName at offset $offset..."

		# Iterate over files in the root of SOURCE_DIR (ignoring subdirectories)
		for file in "$source_dir"/*; do
			if [ -f "$file" ]; then  # Check if it is a file
				echo -e "${fc}Syncing ${fw}$(basename "$file") ${fc}to ${fw}$target_dir"
				mcopy -i "${FileName}@@${offset}" -s "$file" "$target_dir"
			fi
		done
		echo -e "${rt} File sync complete"
	}

	
	check_and_override_file() {
	    local file="$1"

	    # Check if the file exists
	    if [ -e "$file" ]; then
		# Prompt the user for confirmation
		read -p "File '$file' exists. Do you want to override it? (y/n): " response
		
		case "$response" in
		    [Yy]* )
		        echo "Removing and creating a new $file"
		        rm $file
		        ;;
		    [Nn]* )
		        echo "File exists already"
		        exit 1
		        ;;
		    * )
		        echo "Invalid response. Please answer 'y' or 'n'."
		        ;;
		esac
	    else
		echo "File does not exist. Creating new file..."
		# Code to create a new file
		echo "New content" > "$file"
	    fi
	}

###### End of Functions


# Ensure mtools and wget are installed
	install_package "mtools"
	install_package "wget"


	if [ ! -d "$ContentDir" ]; then
	    echo -e "Directory $ContentDir does not exist. Creating it..."
	    mkdir -p "$ContentDir" || { echo -e "Failed to create directory $ContentDir"; exit 1; }
	    echo -e "$ContentDir created. Drop files for the OCM core there run this script again"
	fi

# Check if the correct number of arguments is passed
	if [ "$#" -ne 2 ]; then
	    echo -e "Usage: $0 [VHD size in MB] [File Name]"
	    exit 1
	fi

# VHD size in MB and file name from command-line arguments
	sizemb=$1
	FileName=$2

# Check if sizemb is a valid number
	if ! [[ "$sizemb" =~ ^[0-9]+$ ]]; then
	    echo -e "033[1;31m ERROR: VHD size must be a valid number."
	    exit 1
	fi

# Get the size of the directory and convert it to megabytes
dir_size=$(du -sh FilesForOCMCore/ | awk '{print $1}')
dir_size_mb=$(echo -e "$dir_size" | awk '
    /[0-9\.]+K/ { printf "%.2f\n", $1/1024 }
    /[0-9\.]+M/ { printf "%.2f\n", $1 }
    /[0-9\.]+G/ { printf "%.2f\n", $1*1024 }
')

# Destination file size check
	if (( $(echo -e "$dir_size_mb > $sizemb" | bc -l) )); then
	    echo -e "\033[1;31m ERROR: Directory $ContentDir with the size of [$dir_size_mb MiB] is greater than the requested size of the image [$sizemb MiB]."
	    exit 1
	fi

# Quit if file exists
	check_and_override_file $FileName

# Download BIOS

	# Check if the file exists
	if [ ! -f "$BIOSFileName" ]; then
	    echo -e "$BIOSFileName not found. Downloading..."
	    wget "$BIOSFileURL"
	else
	    echo -e "$BIOSFileName already exists. No need to download."
	fi

	# Unzip the specific file from the archive
	echo -e "Extracting $UnZIPPath from $BIOSFileName..."
	unzip -o -j "$BIOSFileName" "$UnZIPPath"


### Build the VHD files
	# From MB to bytes
	VHDFileSize=$(( sizemb * 1024 * 1024 ))

	# Sectors on VHD (512 bytes per sector)
	nsectors=$(( (VHDFileSize / 512) - 1 ))

	cylinders=$(( (nsectors / ( 63 * 255 ))))

	# Output the results
	echo -e
	echo -e "${fw}Calculating Disk Parameters"
	echo -e "${fg}Filesize in megabytes: ${fw}$sizemb"
	echo -e "${fg}Filesize in bytes: ${fw}$VHDFileSize"
	echo -e "${fg}Number of sectors: ${fw}$nsectors"
	echo -e "${fg}Number of cylinders: ${fw}$cylinders${rt}"
	echo -e "${rt}"

	truncate --size=$VHDFileSize $FileName
	echo -e 1 $nsectors | /sbin/sfdisk --force $FileName
	mformat -i $FileName@@512 -t $cylinders -h 255 -n 63 -H 1 -m 248 ::

### Add the BIOS files
	mcopy -i $FileName@@512 OCM-BIOS.DAT ::

	mattrib -i $FileName@@512 +h ::OCM-BIOS.DAT

	copy_directories_to_image "./FilesForOCMCore" "::/"

	copy_files_to_image "./FilesForOCMCore" "$FileName" "::/"


echo -e 
echo -e "${fg}all done!"
echo -e

exit 1
