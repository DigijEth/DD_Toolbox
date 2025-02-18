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


# Import core functions from main script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/toolbox-cli.sh" >/dev/null 2>&1 || {
    zenity --error --text="Could not load core functions. Please ensure toolbox-cli.sh exists in the same directory."
    exit 1
}

# GUI specific variables
WINDOW_WIDTH=600
WINDOW_HEIGHT=400
PROGRESS_WIDTH=500
TITLE="DD Toolbox GUI"

# Check for Zenity
check_gui_dependencies() {
    if ! command -v zenity >/dev/null 2>&1; then
        echo "Zenity is required for the GUI version. Installing..."
        if command -v apt >/dev/null 2>&1; then
            sudo apt install -y zenity
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y zenity
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm zenity
        else
            echo "Could not install Zenity. Please install it manually."
            exit 1
        }
    fi
}

# GUI wrapper for list_devices
gui_list_devices() {
    local devices_list=""
    while IFS= read -r line; do
        devices_list+="$line\n"
    done < <(lsblk -d -o NAME,SIZE,MODEL,VENDOR,RM | grep -v "loop")
    
    zenity --list \
        --title="Select Device" \
        --width=$WINDOW_WIDTH \
        --height=$WINDOW_HEIGHT \
        --column="Device" \
        --column="Size" \
        --column="Model" \
        --column="Vendor" \
        --column="Removable" \
        $(echo -e "$devices_list") \
        --print-column=1
}

# GUI wrapper for list_iso_files
gui_list_iso_files() {
    local iso_list=""
    while IFS= read -r file; do
        name=$(basename "$file")
        size=$(du -h "$file" | cut -f1)
        iso_list+="$file|$name|$size\n"
    done < <(find "$ISO_DIR" -type f -regextype posix-extended -regex ".*($SUPPORTED_FORMATS|$COMPRESSED_FORMATS)")
    
    zenity --list \
        --title="Select ISO File" \
        --width=$WINDOW_WIDTH \
        --height=$WINDOW_HEIGHT \
        --column="Path" \
        --column="Filename" \
        --column="Size" \
        --hide-column=1 \
        $(echo -e "$iso_list") \
        --print-column=1
}

# GUI progress monitoring
gui_monitor_progress() {
    local input=$1
    local output=$2
    local size=$(stat -c %s "$input")
    
    (pv -n "$input" | sudo dd of="$output" bs=4M conv=fsync 2>/dev/null) 2>&1 | \
    zenity --progress \
        --title="Writing Image" \
        --text="Writing image to device..." \
        --percentage=0 \
        --auto-close \
        --auto-kill \
        --width=$PROGRESS_WIDTH
}

# Main GUI menu
gui_main_menu() {
    while true; do
        action=$(zenity --list \
            --title="$TITLE" \
            --width=$WINDOW_WIDTH \
            --height=$WINDOW_HEIGHT \
            --column="Operation" \
            "Flash Image From File" \
            "Download Image And Flash" \
            "Create Disk Image" \
            "Create Image from Directory" \
            "Flash Bootable Image" \
            "Advanced Operations" \
            "Exit")
        
        case "$action" in
            "Flash Image From File")
                iso_file=$(gui_list_iso_files)
                if [ -n "$iso_file" ]; then
                    device=$(gui_list_devices)
                    if [ -n "$device" ]; then
                        if zenity --question \
                            --title="Confirm Operation" \
                            --text="WARNING: This will erase all data on /dev/$device\nContinue?"; then
                            
                            if format_drive "$device"; then
                                gui_monitor_progress "$iso_file" "/dev/$device"
                                verify_iso "$device" && \
                                zenity --info --text="Operation completed successfully!"
                            fi
                        fi
                    fi
                fi
                ;;
                
            "Download Image And Flash")
                url=$(zenity --entry \
                    --title="Download ISO" \
                    --text="Enter ISO URL:" \
                    --width=$WINDOW_WIDTH)
                
                if [ -n "$url" ]; then
                    # Show download progress
                    wget "$url" -O "$ISO_DIR/$(basename "$url")" 2>&1 | \
                    sed -u 's/.* \([0-9]\+%\)\ \+\([0-9.]\+.\) \(.*\)/\1\n# Downloading: \2\/s, ETA: \3/' | \
                    zenity --progress \
                        --title="Downloading ISO" \
                        --text="Starting download..." \
                        --auto-close \
                        --width=$PROGRESS_WIDTH
                fi
                ;;
                
            "Create Disk Image")
                device=$(gui_list_devices)
                if [ -n "$device" ]; then
                    output_name=$(zenity --entry \
                        --title="Create Disk Image" \
                        --text="Enter image name:" \
                        --entry-text="disk_image_$(date +%Y%m%d_%H%M%S).img")
                    
                    if [ -n "$output_name" ]; then
                        create_disk_image "$device" "$output_name" | \
                        zenity --progress \
                            --title="Creating Disk Image" \
                            --text="Creating image..." \
                            --pulsate \
                            --auto-close \
                            --width=$PROGRESS_WIDTH
                    fi
                fi
                ;;
                
            "Create Image from Directory")
                dir=$(zenity --file-selection --directory \
                    --title="Select Directory")
                
                if [ -n "$dir" ]; then
                    output_name=$(zenity --entry \
                        --title="Create ISO" \
                        --text="Enter ISO name:" \
                        --entry-text="$(basename "$dir")_$(date +%Y%m%d_%H%M%S).iso")
                    
                    if [ -n "$output_name" ]; then
                        create_iso_from_dir "$dir" "$output_name" | \
                        zenity --progress \
                            --title="Creating ISO" \
                            --text="Creating ISO..." \
                            --pulsate \
                            --auto-close \
                            --width=$PROGRESS_WIDTH
                    fi
                fi
                ;;
                
            "Advanced Operations")
                advanced_action=$(zenity --list \
                    --title="Advanced Operations" \
                    --width=$WINDOW_WIDTH \
                    --height=$WINDOW_HEIGHT \
                    --column="Operation" \
                    "Zero Drive" \
                    "Write Random Data" \
                    "Clone Drive" \
                    "Backup MBR" \
                    "Restore MBR")
                
                case "$advanced_action" in
                    "Zero Drive"|"Write Random Data"|"Backup MBR")
                        device=$(gui_list_devices)
                        if [ -n "$device" ]; then
                            if zenity --question \
                                --title="Confirm Operation" \
                                --text="WARNING: This operation cannot be undone!\nContinue?"; then
                                case "$advanced_action" in
                                    "Zero Drive") zero_drive "$device" ;;
                                    "Write Random Data") random_data "$device" ;;
                                    "Backup MBR") backup_mbr "$device" ;;
                                esac
                            fi
                        fi
                        ;;
                    "Clone Drive")
                        source_dev=$(gui_list_devices)
                        if [ -n "$source_dev" ]; then
                            target_dev=$(gui_list_devices)
                            if [ -n "$target_dev" ]; then
                                if zenity --question \
                                    --title="Confirm Clone" \
                                    --text="Clone /dev/$source_dev to /dev/$target_dev?"; then
                                    clone_drive "$source_dev" "$target_dev"
                                fi
                            fi
                        fi
                        ;;
                    "Restore MBR")
                        device=$(gui_list_devices)
                        if [ -n "$device" ]; then
                            backup_file=$(zenity --file-selection \
                                --title="Select MBR Backup" \
                                --file-filter="MBR Backup files (mbr_backup_*.bin)")
                            if [ -n "$backup_file" ]; then
                                restore_mbr "$device" "$backup_file"
                            fi
                        fi
                        ;;
                esac
                ;;
                
            "Exit"|"")
                exit 0
                ;;
        esac
    done
}

# Check dependencies and start GUI
check_gui_dependencies
check_superuser
gui_main_menu
