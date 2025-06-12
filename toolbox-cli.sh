#!/bin/bash


# DD Burner V1.04  
# Please Donate to the Developer if you find this script useful
# On Solana: Setec.sol 
# On Ethereum: Digij.eth 
# Place ISO files in the ../burn-iso/images/ folder
# This script is designed to be used on Linux systems to burn and create 1:1 copies of ISO files to USB drives.    
# 
# The progress of the write operation can be monitored using the 'pv' tool if available.
# The script logs all operations to a log file for reference.
# The script requires 'sudo' privileges to run certain commands.
# Ensure that the 'dd' and 'pv' tools are installed on the system for the script to work correctly.


# Superuser check to make sure people dont forget to run as sudo
check_superuser() {
    if [ $EUID -ne 0 ] && ! sudo -v >/dev/null 2>&1; then
        echo -e "${RED}Error: This script requires superuser privileges${NC}"
        echo "Please run with sudo or as root"
        exit 1
    fi
    
    # If user has sudo access but didn't use it, restart with sudo
    if [ $EUID -ne 0 ] && sudo -v >/dev/null 2>&1; then
        echo -e "${YELLOW}Restarting script with sudo...${NC}"
        exec sudo "$0" "$@"
    fi
    
    log "INFO" "Superuser check passed"
}


# error handling
set -o errexit  # Exit on error
set -o pipefail # Exit on pipe error
trap cleanup EXIT SIGINT SIGTERM

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Directory configuration - single source of truth 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_DIR="$SCRIPT_DIR/images"
LOG_DIR="$SCRIPT_DIR/logs"
MAKE_DIR="$SCRIPT_DIR/make"
LOG_FILE="$LOG_DIR/dd-toolbox.log"
TMP_DEVICES="/tmp/devices.txt"

# Create required directories in script folder
for dir in "$ISO_DIR" "$LOG_DIR" "$MAKE_DIR"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || {
            echo -e "${RED}Failed to create directory: $dir${NC}"
            exit 1
        }
    fi
done

# supported formats, if you need to add other, do it here
SUPPORTED_FORMATS="\.iso$|\.img$|\.bin$"
COMPRESSED_FORMATS="\.gz$|\.xz$|\.zip$|\.7z$"

# log configuration.
 LOG_DIR="../dd_bash/logs"
 LOG_FILE="$LOG_DIR/burn-iso.log"
 mkdir -p "$LOG_DIR"

# logging and error handling functions
log() {
    local level=$1
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo -e "$message" >> "$LOG_FILE"
    [ "$level" = "ERROR" ] && echo -e "${RED}$message${NC}" || echo -e "$message"
}

error_handler() {
    local line_no=$1
    local error_code=$2
    local cmd="${BASH_COMMAND}"
    
    log "ERROR" "Command '$cmd' failed at line ${line_no} with exit code: ${error_code}"
    
    # Attempt to restore system to safe state
    if [ -n "$device" ]; then
        log "INFO" "Attempting to sync device: /dev/$device"
        sync
    fi
}

# This function handles operation failures gracefully
fail() {
    local message="$1"
    log "ERROR" "$message"
    # Return false instead of explicit return 1
    false
}

cleanup() {
    local exit_code=$?
    log "INFO" "Starting cleanup process..."
    
    # Cleanup temporary files with error checking
    if [ -f "$TMP_DEVICES" ]; then
        if ! rm -f "$TMP_DEVICES"; then
            log "ERROR" "Failed to remove temporary devices file"
        fi
    fi
    
    # Cleanup extracted files if they exist
    if [ -n "$extracted_file" ] && [ -f "$extracted_file" ]; then
        if ! rm -f "$extracted_file"; then
            log "ERROR" "Failed to remove temporary extracted file"
        fi
    fi
    
    # Sync to ensure all writes are complete
    sync
    
    # Log final status
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Script terminated with error code: $exit_code"
    else
        log "INFO" "Cleanup completed successfully"
    fi
    
    exit $exit_code
}

trap 'cleanup' EXIT
trap 'error_handler ${LINENO} $?' ERR SIGINT SIGTERM

# dependency checking, this is for the .deb conversion
check_dependencies() {
    local missing_deps=()
    local pkg_manager=""
    local install_cmd=""
    
    # Detect package manager
    if command -v apt >/dev/null 2>&1; then
        pkg_manager="apt"
        install_cmd="sudo apt install -y"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_manager="dnf"
        install_cmd="sudo dnf install -y"
    elif command -v pacman >/dev/null 2>&1; then
        pkg_manager="pacman"
        install_cmd="sudo pacman -S --noconfirm"
    elif command -v zypper >/dev/null 2>&1; then
        pkg_manager="zypper"
        install_cmd="sudo zypper install -y"
    else
        echo -e "${RED}No supported package manager found${NC}"
        return 1
    fi
    
    # Check for required tools
    local dependencies=(
        "dd:coreutils"
        "pv:pv"
        "mkfs.vfat:dosfstools"
        "wget:wget"
        "mkisofs:mkisofs" 
        "genisoimage:genisoimage"
        "sync:coreutils"
        "lsblk:util-linux"
    )
    
    for dep in "${dependencies[@]}"; do
        IFS=':' read -r cmd pkg <<< "$dep"
        if [[ $cmd == *"|"* ]]; then
            # Handle alternative commands (e.g., mkisofs|genisoimage)
            local found=0
            IFS='|' read -r cmd1 cmd2 <<< "$cmd"
            IFS='|' read -r pkg1 pkg2 <<< "$pkg"
            if command -v "${cmd1%:*}" >/dev/null 2>&1; then
                found=1
            elif command -v "${cmd2%:*}" >/dev/null 2>&1; then
                found=1
            else
                missing_deps+=("$pkg1")
            fi
        elif ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$pkg")
        fi
    done
    
    # If dependencies are missing, prompt for installation
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}Missing required dependencies:${NC}"
        printf '%s\n' "${missing_deps[@]}"
        echo
        read -p "Would you like to install them now? (y/n): " install_choice
        if [[ "${install_choice,,}" =~ ^(yes|y)$ ]]; then
            echo -e "${GREEN}Installing dependencies...${NC}"
            if ! $install_cmd "${missing_deps[@]}"; then
                echo -e "${RED}Failed to install dependencies${NC}"
                return 1
            fi
            echo -e "${GREEN}Dependencies installed successfully${NC}"
        else
            echo -e "${RED}Required dependencies must be installed to continue${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}All required dependencies are installed${NC}"
    fi
    
    return 0
}

# Dependency check right after function definition
if ! check_dependencies; then
    log "ERROR" "Dependency check failed. Please install required packages."
    exit 1
fi

# Function to list available ISO files
list_iso_files() {
    if [ ! -d "$ISO_DIR" ]; then
        echo -e "${RED}Error: ISO directory not found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Available image files:${NC}"
    find "$ISO_DIR" -type f -regextype posix-extended \
        -regex ".*($SUPPORTED_FORMATS|$COMPRESSED_FORMATS)" | nl || echo "No image files found"
    show_image_menu
}

# Function to list only removable devices
list_removable_devices() {
    echo -e "${GREEN}Available removable devices:${NC}"
    lsblk -d -o NAME,SIZE,MODEL,VENDOR,RM | grep "1$" | sed 's/ 1$//' > "$TMP_DEVICES"
    awk '{printf "%s (%s) - %s %s\n", $1, $2, $3, $4}' "$TMP_DEVICES" | nl
    show_device_menu
}

# Modify list_devices function to accept a parameter
list_devices() {
    local show_all=${1:-false}
    echo -e "${GREEN}Available storage devices:${NC}"
    if [ "$show_all" = true ]; then
        lsblk -d -o NAME,SIZE,MODEL,VENDOR | grep -v "loop" > "$TMP_DEVICES"
    else
        lsblk -d -o NAME,SIZE,MODEL,VENDOR,RM | grep "1$" | sed 's/ 1$//' > "$TMP_DEVICES"
    fi
    awk '{printf "%s (%s) - %s %s\n", $1, $2, $3, $4}' "$TMP_DEVICES" | nl
    show_device_menu
}

# Function to get device selection
select_device() {
    local device_count=$(wc -l < "$TMP_DEVICES")
    read -p "Select device number (1-$device_count): " device_num
    
    if [ "$device_num" -ge 1 ] && [ "$device_num" -le "$device_count" ]; then
        echo $(sed -n "${device_num}p" "$TMP_DEVICES" | awk '{print $1}')
    else
        echo ""
    fi
}

#  download functions 
download_iso() {
    read -p "Enter ISO URL: " iso_url
    log "INFO" "Downloading ISO from: $iso_url"
    
    if ! command -v wget >/dev/null 2>&1; then
        log "ERROR" "wget not found. Please install wget"
        return 1
    fi
    
    local filename=$(basename "$iso_url")
    local target_file="$ISO_DIR/$filename"
    
    echo -e "${GREEN}Downloading ISO...${NC}"
    wget --progress=bar:force "$iso_url" -O "$target_file"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Download complete!${NC}"
        return 0
    else
        echo -e "${RED}Download failed!${NC}"
        return 1
    fi
}

# helper function to check if device is mounted
is_device_mounted() {
    local device=$1
    if mount | grep -q "^/dev/${device}"; then
        return 0  # device is mounted
    fi
    return 1  # device is not mounted
}

format_drive() {
    local device=$1
    log "INFO" "Formatting device: /dev/$device"
    
    if ! command -v mkfs.vfat >/dev/null 2>&1; then
        fail "mkfs.vfat not found. Please install dosfstools"
        return 1
    fi
    
    # Check if device is mounted
    if lsblk -n -o MOUNTPOINT "/dev/$device"* 2>/dev/null | grep -q '^/'; then
        echo -e "${YELLOW}Device /dev/$device has mounted partitions${NC}"
        read -p "Would you like to unmount them? (y/n): " unmount_choice
        if [[ "${unmount_choice,,}" =~ ^(yes|y)$ ]]; then
            echo -e "${YELLOW}Unmounting partitions...${NC}"
            # Unmount all partitions of the device
            if ! sudo umount "/dev/$device"* 2>/dev/null; then
                # Try force unmounting if regular unmount fails
                if ! sudo umount -f "/dev/$device"* 2>/dev/null; then
                    echo -e "${RED}Failed to unmount all partitions. Continuing anyway...${NC}"
                    log "WARN" "Failed to unmount some partitions of /dev/$device"
                    sleep 2
                fi
            fi
        else
            fail "Device must be unmounted before formatting"
            return 1
        fi
    fi
    
    echo -e "${YELLOW}Formatting /dev/$device...${NC}"
    if ! sudo mkfs.vfat -I "/dev/$device"; then
        fail "Failed to format device /dev/$device. Check if device is in use by another process"
        return 1
    fi
    
    log "INFO" "Successfully formatted /dev/$device"
    sync
    return 0
}

verify_iso() {
    local device=$1
    log "INFO" "Verifying ISO on device: /dev/$device"
    
    if ! [ -f "$iso_file" ]; then
        log "ERROR" "ISO file not found: $iso_file"
        return 1
    fi
    
    local iso_size=$(stat -c %s "$iso_file")
    local device_size=$(sudo blockdev --getsize64 "/dev/$device")
    
    echo -e "${YELLOW}Verifying ISO...${NC}"
    local verify_size=$((iso_size < device_size ? iso_size : device_size))
    sudo dd if="/dev/$device" bs=4M count=$((verify_size/4194304)) | diff - "$iso_file"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Verification successful!${NC}"
        return 0
    else
        echo -e "${RED}Verification failed!${NC}"
        return 1
    fi
}

# this handles compressed files
extract_file() {
    local compressed_file=$1
    local output_dir="$ISO_DIR"
    local ext="${compressed_file##*.}"
    
    log "INFO" "Extracting file: $compressed_file"
    echo -e "${YELLOW}Extracting compressed file...${NC}"
    
    case "$ext" in
        gz|xz|zip|7z)
            if ! command -v "${ext}cat" >/dev/null 2>&1; then
                log "ERROR" "Required tool for $ext extraction not found"
                return 1
            fi
            case "$ext" in
                gz)  gunzip -c "$compressed_file" > "${compressed_file%.*}" ;;
                xz)  xz -d -c "$compressed_file" > "${compressed_file%.*}" ;;
                zip) unzip -p "$compressed_file" > "${compressed_file%.*}" ;;
                7z)  7z e "$compressed_file" -o"$output_dir" ;;
            esac
        ;;
        *)   
            log "ERROR" "Unsupported compression format: $ext"
            return 1 
        ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Extraction complete!${NC}"
        echo "${compressed_file%.*}"
        return 0
    else
        echo -e "${RED}Extraction failed!${NC}"
        return 1
    fi
}

# just a helper functions for menus
show_image_menu() {
    echo -e "\n${YELLOW}Image Selection Menu:${NC}"
    echo "r) Rescan for images"
    echo "b) Back to main menu"
    echo "q) Exit program"
    echo
}

show_device_menu() {
    echo -e "\n${YELLOW}Device Selection Menu:${NC}"
    echo "r) Rescan devices"
    echo "b) Back to image selection"
    echo "q) Exit program"
    echo
}

# helper function for progress monitoring
monitor_progress() {
    local input=$1
    local output=$2
    local size=$(stat -c %s "$input")
    
    if check_pv; then
        log "INFO" "Starting burn process with progress monitoring"
        sudo pv -s "$size" "$input" | sudo dd of="$output" bs=4M conv=fsync
    else
        log "INFO" "Using dd without progress bar"
        sudo dd if="$input" of="$output" bs=4M status=progress conv=fsync
    fi
}

# function to check for pv
check_pv() {
    if ! command -v pv >/dev/null 2>&1; then
        echo -e "${YELLOW}Note: Installing 'pv' is recommended for better progress monitoring${NC}"
        echo "Install with: sudo apt install pv  # Debian/Ubuntu"
        echo "             sudo dnf install pv   # Fedora/RHEL"
        echo "             sudo pacman -S pv     # Arch Linux"
        read -p "Press Enter to continue without pv..."
        return 1
    fi
    return 0
}

# completion dialog function
show_completion_dialog() {
    echo -e "\n${GREEN}ISO successfully written to device!${NC}"
    echo -e "\nWhat would you like to do?"
    echo "1) Burn another image"
    echo "2) Exit"
    
    while true; do
        read -p "Select option (1-2): " choice
        case "$choice" in
            1) return 0 ;;
            2) log "INFO" "User chose to exit after successful burn"
               exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
    done
}

# new function to create disk image
create_disk_image() {
    local device=$1
    local image_name
    
    # Create images directory if it doesn't exist
    mkdir -p "$ISO_DIR"
    
    # Generate default image name
    image_name="disk_image_$(date +%Y%m%d_%H%M%S).img"
    
    # Ask for custom image name
    read -p "Enter image name [$image_name]: " custom_name
    image_name="${custom_name:-$image_name}"
    
    # Ensure .img extension
    [[ $image_name != *.img ]] && image_name="${image_name}.img"
    
    local output_path="$ISO_DIR/$image_name"
    
    echo -e "${YELLOW}Creating disk image from /dev/$device${NC}"
    log "INFO" "Creating disk image: $output_path from device: /dev/$device"
    
    # Get device size
    local device_size=$(sudo blockdev --getsize64 "/dev/$device")
    
    if check_pv; then
        sudo dd if="/dev/$device" bs=4M | pv -s "$device_size" | dd of="$output_path" bs=4M
    else
        sudo dd if="/dev/$device" of="$output_path" bs=4M status=progress
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Disk image created successfully: $output_path${NC}"
        log "INFO" "Disk image created successfully"
        return 0
    else
        echo -e "${RED}Failed to create disk image${NC}"
        log "ERROR" "Failed to create disk image"
        return 1
    fi
}

# execute advanced DD operations functions here
zero_drive() {
    local device=$1
    echo -e "${YELLOW}Zeroing out device /dev/$device${NC}"
    log "INFO" "Zeroing out device: /dev/$device"
    
    local device_size=$(sudo blockdev --getsize64 "/dev/$device")
    if check_pv; then
        sudo dd if=/dev/zero bs=4M | pv -s "$device_size" | sudo dd of="/dev/$device" bs=4M
    else
        sudo dd if=/dev/zero of="/dev/$device" bs=4M status=progress
    fi
}

random_data() {
    local device=$1
    echo -e "${YELLOW}Writing random data to /dev/$device${NC}"
    log "INFO" "Writing random data to device: /dev/$device"
    
    local device_size=$(sudo blockdev --getsize64 "/dev/$device")
    if check_pv; then
        sudo dd if=/dev/urandom bs=4M | pv -s "$device_size" | sudo dd of="/dev/$device" bs=4M
    else
        sudo dd if=/dev/urandom of="/dev/$device" bs=4M status=progress
    fi
}

clone_drive() {
    local source=$1
    local target=$2
    echo -e "${YELLOW}Cloning /dev/$source to /dev/$target${NC}"
    log "INFO" "Cloning drive: /dev/$source to /dev/$target"
    
    local device_size=$(sudo blockdev --getsize64 "/dev/$source")
    if check_pv; then
        sudo dd if="/dev/$source" bs=4M | pv -s "$device_size" | sudo dd of="/dev/$target" bs=4M
    else
        sudo dd if="/dev/$source" of="/dev/$target" bs=4M status=progress
    fi
}

backup_mbr() {
    local device=$1
    local backup_file="$ISO_DIR/mbr_backup_${device}_$(date +%Y%m%d_%H%M%S).bin"
    echo -e "${YELLOW}Backing up MBR from /dev/$device${NC}"
    log "INFO" "Backing up MBR from device: /dev/$device"
    
    sudo dd if="/dev/$device" of="$backup_file" bs=512 count=1
    echo -e "${GREEN}MBR backup saved to: $backup_file${NC}"
}

restore_mbr() {
    local device=$1
    local backup_file
    
    echo -e "${GREEN}Available MBR backups:${NC}"
    local mbr_files=($(find "$ISO_DIR" -name "mbr_backup_*.bin"))
    if [ ${#mbr_files[@]} -eq 0 ]; then
        echo -e "${RED}No MBR backups found!${NC}"
        return 1
    fi
    
    select backup_file in "${mbr_files[@]}"; do
        if [ -n "$backup_file" ]; then
            echo -e "${YELLOW}Restoring MBR to /dev/$device${NC}"
            log "INFO" "Restoring MBR to device: /dev/$device from $backup_file"
            sudo dd if="$backup_file" of="/dev/$device" bs=512 count=1
            break
        fi
    done
}

show_advanced_menu() {
    while true; do
        clear
        echo -e "${YELLOW}=== Advanced DD Operations ===${NC}\n"
        echo "1. Zero out a drive"
        echo "2. Write random data to drive"
        echo "3. Clone drive to drive"
        echo "4. Backup MBR"
        echo "5. Restore MBR"
        echo "6. Back to main menu"
        echo
        
        read -p "Select an option (1-6): " advanced_option
        
        case $advanced_option in
            1|2|3|4|5)
                list_devices
                read -p "Select source device number: " src_num
                device=$(select_device)
                if [ -n "$device" ]; then
                    case $advanced_option in
                        1)
                            echo -e "${RED}WARNING: This will erase all data on /dev/$device${NC}"
                            read -p "Are you sure? (yes/no): " confirm
                            [[ "${confirm,,}" =~ ^(yes|y)$ ]] && zero_drive "$device"
                            ;;
                        2)
                            echo -e "${RED}WARNING: This will overwrite all data on /dev/$device${NC}"
                            read -p "Are you sure? (yes/no): " confirm
                            [[ "${confirm,,}" =~ ^(yes|y)$ ]] && random_data "$device"
                            ;;
                        3)
                            echo -e "${GREEN}Select target device:${NC}"
                            list_devices
                            read -p "Select target device number: " tgt_num
                            target_device=$(select_device)
                            if [ -n "$target_device" ]; then
                                echo -e "${RED}WARNING: This will clone /dev/$device to /dev/$target_device${NC}"
                                read -p "Are you sure? (yes/no): " confirm
                                [[ "${confirm,,}" =~ ^(yes|y)$ ]] && clone_drive "$device" "$target_device"
                            fi
                            ;;
                        4)
                            backup_mbr "$device"
                            ;;
                        5)
                            restore_mbr "$device"
                            ;;
                    esac
                    read -p "Press Enter to continue..."
                fi
                ;;
            6)
                return
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                read -p "Press Enter..."
                ;;
        esac
    done
}

# Add after other function definitions, before main menu
create_iso_from_dir() {
    local source_dir
    local default_dir="../make"
    local output_name
    
    # Check for required tools
    if ! command -v mkisofs >/dev/null 2>&1 && ! command -v genisoimage >/dev/null 2>&1; then
        fail "Neither mkisofs nor genisoimage found. Please install one of them"
        return
    fi
    
    # Ask for source directory
    echo -e "${YELLOW}Select source directory:${NC}"
    echo "1) Use default directory ($default_dir)"
    echo "2) Specify custom directory"
    read -p "Select option (1-2): " dir_choice
    
    case "$dir_choice" in
        1)
            source_dir="$default_dir"
            if [ ! -d "$source_dir" ]; then
                if ! mkdir -p "$source_dir"; then
                    fail "Failed to create default directory"
                    return
                fi
                echo -e "${GREEN}Created default directory: $source_dir${NC}"
            fi
            ;;
        2)
            read -p "Enter absolute path to source directory: " source_dir
            ;;
        *)
            fail "Invalid option"
            return
            ;;
    esac
    
    # Validate directory
    if [ ! -d "$source_dir" ]; then
        fail "Directory does not exist: $source_dir"
        return
    fi
    
    # Generate default ISO name from directory name
    local default_name="$(basename "$source_dir")_$(date +%Y%m%d_%H%M%S).iso"
    read -p "Enter ISO name [$default_name]: " custom_name
    output_name="${custom_name:-$default_name}"
    
    # Ensure .iso extension
    [[ $output_name != *.iso ]] && output_name="${output_name}.iso"
    
    local output_path="$ISO_DIR/$output_name"
    
    echo -e "${YELLOW}Creating ISO from directory: $source_dir${NC}"
    log "INFO" "Creating ISO from directory: $source_dir to $output_path"
    
    # Create ISO using available tool
    if command -v mkisofs >/dev/null 2>&1; then
        if ! mkisofs -r -J -o "$output_path" "$source_dir"; then
            fail "Failed to create ISO using mkisofs"
            return
        fi
    else
        if ! genisoimage -r -J -o "$output_path" "$source_dir"; then
            fail "Failed to create ISO using genisoimage"
            return
        fi
    fi
    
    if [ -f "$output_path" ]; then
        echo -e "${GREEN}ISO created successfully: $output_path${NC}"
        log "INFO" "ISO created successfully"
        return 0
    else
        fail "Failed to create ISO"
        return
    fi
}

# Main menu
while true; do
    clear
    echo -e "${YELLOW}=== DD Toolbox ===${NC}\n"
    echo "1. Flash Image From File"
    echo "2. Download Image And Flash" 
    echo "3. Create A 1:1 Disk Image"
    echo "4. Create Image from Directory"
    echo "5. Flash Bootable Image"  # New option
    echo "6. Advanced"
    echo "7. Exit"
    echo
    
    read -p "Select an option (1-7): " option
    
    case $option in
        1)
            while true; do
                if ! list_iso_files; then
                    log "ERROR" "Failed to list ISO files"
                    read -p "Press Enter..."
                    continue
                fi
                read -p "Select image number or option: " iso_num
                case "$iso_num" in
                    q) exit 0 ;;
                    b) break ;;
                    r) continue ;;
                    *)
                        selected_file=$(find "$ISO_DIR" -type f -regextype posix-extended \
                            -regex ".*($SUPPORTED_FORMATS|$COMPRESSED_FORMATS)" | sed -n "${iso_num}p")
                        
                        if [ -z "$selected_file" ]; then
                            echo -e "${RED}Invalid selection${NC}"
                            read -p "Press Enter..."
                            continue
                        fi
                        
                        # Handle compressed files
                        if echo "$selected_file" | grep -qE "$COMPRESSED_FORMATS"; then
                            extracted_file=$(extract_file "$selected_file")
                            [ $? -ne 0 ] && { read -p "Press Enter..."; continue; }
                            iso_file="$extracted_file"
                        else
                            iso_file="$selected_file"
                        fi
                        
                        # Add device listing prompt
                        echo -e "\n${YELLOW}Device Selection:${NC}"
                        echo "1) Show all devices"
                        echo "2) Show only removable devices (USB/SD)"
                        read -p "Select option (1-2): " dev_choice
                        
                        case "$dev_choice" in
                            1) show_all=true ;;
                            2) show_all=false ;;
                            *) 
                                echo -e "${RED}Invalid option${NC}"
                                read -p "Press Enter..."
                                continue ;;
                        esac
                        
                        while true; do
                            list_devices "$show_all"
                            # ...rest of the device selection code...
                            break
                        done
                        break
                        ;;
                esac
            done
            [ "$iso_num" = "b" ] && continue
            ;;
        2)
            if ! download_iso; then
                log "ERROR" "ISO download failed"
                read -p "Press Enter..."
                continue
            fi
            iso_file="$target_file"
            ;;
        3)
            while true; do
                list_devices
                read -p "Select device number or option: " device_num
                case "$device_num" in
                    q) exit 0 ;;
                    b) break ;;
                    r) continue ;;
                    *)
                        device=$(select_device)
                        if [ -n "$device" ]; then
                            if create_disk_image "$device"; then
                                read -p "Press Enter to continue..."
                            fi
                            break
                        else
                            echo -e "${RED}Invalid device${NC}"
                            read -p "Press Enter..."
                        fi
                        ;;
                esac
            done
            ;;
        4)
            create_iso_from_dir
            read -p "Press Enter to continue..."
            ;;
         5) # Flash Bootable Image
            while true; do
                if ! list_iso_files; then
                    log "ERROR" "Failed to list ISO files"
                    read -p "Press Enter..."
                    continue
                fi
                read -p "Select image number or option: " iso_num
                case "$iso_num" in
                    q) exit 0 ;;
                    b) break ;;
                    r) continue ;;
                    *)
                        selected_file=$(find "$ISO_DIR" -type f -regextype posix-extended \
                            -regex ".*($SUPPORTED_FORMATS|$COMPRESSED_FORMATS)" | sed -n "${iso_num}p")
                        
                        if [ -z "$selected_file" ]; then
                            echo -e "${RED}Invalid selection${NC}"
                            read -p "Press Enter..."
                            continue
                        fi
                        
                        iso_file="$selected_file"
                        
                        echo -e "\n${YELLOW}Device Selection:${NC}"
                        echo "1) Show all devices"
                        echo "2) Show only removable devices (USB/SD)"
                        read -p "Select option (1-2): " dev_choice
                        
                        case "$dev_choice" in
                            1) show_all=true ;;
                            2) show_all=false ;;
                            *) 
                                echo -e "${RED}Invalid option${NC}"
                                read -p "Press Enter..."
                                continue ;;
                        esac
                        
                        while true; do
                            list_devices "$show_all"
                            device=$(select_device)
                            if [ -n "$device" ]; then
                                if format_drive "$device" && \
                                   monitor_progress "$iso_file" "/dev/$device" && \
                                   verify_iso "$device"; then
                                    show_completion_dialog
                                fi
                            fi
                            break
                        done
                        break
                        ;;
                esac
            done
            ;;
        6)
            show_advanced_menu
            ;;
        7)
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            read -p "Press Enter..."
            continue
            ;;
    esac
    
    while true; do
        list_devices
        read -p "Select device number or option: " device_num
        case "$device_num" in
            q) exit 0 ;;
            b) break ;;  # Changed from continue 2 to break
            r) continue ;;
            *)
                device=$(select_device)
                if [ -n "$device" ]; then
                    # Confirmation and writing process
                    echo -e "\n${RED}WARNING: This will erase all data on /dev/$device${NC}"
                    read -p "Are you sure you want to continue? (yes/no): " confirm
                    if [[ "${confirm,,}" =~ ^(yes|y)$ ]]; then
                        format_drive "$device"
                        
                        echo -e "\n${GREEN}Writing ISO to device...${NC}"
                        log "INFO" "Writing ISO to device: /dev/$device"
                        if ! monitor_progress "$iso_file" "/dev/$device"; then
                            log "ERROR" "Failed to write ISO to device"
                            read -p "Press Enter to continue..."
                            break
                        fi
                        
                        if verify_iso "$device"; then
                            show_completion_dialog
                        else
                            echo -e "\n${RED}Verification failed! The written image might be corrupted.${NC}"
                            read -p "Press Enter to continue..."
                        fi
                        
                        echo -e "\n${GREEN}Operation completed!${NC}"
                        read -p "Press Enter to continue..."
                        break
                    else
                        echo "Operation cancelled."
                        read -p "Press Enter to continue..."
                        break
                    fi
                else
                    echo -e "${RED}Invalid device${NC}"
                    read -p "Press Enter..."
                fi
                ;;
        esac
    done
    [ "$device_num" = "b" ] && continue

done
