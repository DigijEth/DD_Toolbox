# DD Toolbox

DD Toolbox is a versatile script designed for Linux systems to burn and create 1:1 copies of ISO files to USB drives. It also includes advanced disk operations such as zeroing out drives, writing random data, cloning drives, and managing MBR backups. The script supports progress monitoring using the `pv` tool and logs all operations for reference.

## Features

- Burn ISO images to USB drives
- Download ISO images from the internet and burn them
- Create 1:1 disk images from USB drives
- Create ISO images from directories
- Advanced disk operations:
  - Zero out a drive
  - Write random data to a drive
  - Clone one drive to another
  - Backup and restore MBR
- Dependency checking and installation
- Progress monitoring with `pv`
- Comprehensive logging

## Requirements

- Linux system
- `sudo` privileges
- `dd` and `pv` tools installed
- `wget` for downloading ISO images
- `mkisofs` or `genisoimage` for creating ISO images from directories
- `dosfstools` for formatting drives

## Installation

1. Clone the repository or download the script.
2. Ensure the required tools are installed on your system.
3. Place ISO files in the `../dd_bash/images/` folder.

## Usage

Run the script with `sudo` privileges:

```bash
sudo ./dd-toolbox.sh
```

### Main Menu Options

1. **Burn Image From File**: Select an ISO file from the `../dd_bash/images/` folder and burn it to a USB drive.
2. **Download Image And Burn**: Download an ISO image from the internet and burn it to a USB drive.
3. **Create A 1:1 Disk Image**: Create a disk image from a USB drive.
4. **Create Image from Directory**: Create an ISO image from a specified directory.
5. **Flash Bootable Image**: Flash a bootable or live Image
6. **Advanced**: Access advanced disk operations.
7. **Exit**: Exit the script.

### Advanced Menu Options

1. **Zero out a drive**: Write zeros to a drive, effectively erasing all data.
2. **Write random data to drive**: Write random data to a drive for security purposes.
3. **Clone drive to drive**: Clone one drive to another.
4. **Backup MBR**: Backup the Master Boot Record (MBR) of a drive.
5. **Restore MBR**: Restore the MBR from a backup file.
6. **Back to main menu**: Return to the main menu.

## Logging

All operations are logged to `../dd_bash/logs/burn-iso.log`. The log file includes timestamps and log levels for easy reference.

## Donations

If you find this script useful, please consider donating to the developer:

- **Solana**: Setec.sol
- **Ethereum**: Digij.eth

Thank you for your support!
