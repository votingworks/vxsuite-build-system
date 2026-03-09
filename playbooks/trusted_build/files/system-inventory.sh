#!/bin/bash

set -euo pipefail

# Exit if not running as root
[[ $EUID -ne 0 ]] && echo "Please run as root." && exit 1

# File paths
LOG_FILE="/var/log/votingworks/system-inventory.log"
JSON_FILE="/var/log/votingworks/system-inventory.json"

# Storing data in an associative array
declare -A DATA

# SBC and TPM
DATA["sbc_bios_vendor"]=$(dmidecode -s bios-vendor 2>/dev/null || echo "NA")
DATA["sbc_bios_version"]=$(dmidecode -s bios-version 2>/dev/null || echo "NA")
DATA["sbc_bios_release_date"]=$(dmidecode -s bios-release-date 2>/dev/null || echo "NA")
DATA["sbc_bios_revision"]=$(dmidecode -s bios-revision 2>/dev/null || echo "NA")
DATA["tpm_version"]=$(cat /sys/class/tpm/tpm0/tpm_version_major || echo "NA")

# Disks
for disk in $(lsblk -o NAME,TYPE | grep disk | awk '{print $1}')
do
  size=$(lsblk -o NAME,TYPE,SIZE /dev/$disk | grep disk | awk '{print $3}')
  DATA["disk_${disk}_size"]=${size}
done

# Temperature
nvme_adapter=$(sensors | grep -i nvme) || nvme_adapter=""
if [[ ! -z "${nvme_adapter}" ]]; then
  DATA["temp_nvme_cpu"]=$(sensors -f -A ${nvme_adapter} | grep Composite | awk '{print $2}' || echo "NA")
fi

# Display
if ddcutil getvcp 10 --brief > /dev/null 2>&1; then
  DATA["screen_brightness"]=$(ddcutil getvcp 10 --brief | awk '{print $4}' || echo "NA")
fi

# Card Reader
vidpid=$(lsusb | grep -i "reader" | head -n 1 | awk '{print $6}') || vidpid=""
if [[ ! -z "${vidpid}" ]]; then
  DATA["card_reader_info"]=$(lsusb | grep -i "reader" | head -n 1 || echo "NA")
  DATA["card_reader_version"]=$(lsusb -v -d ${vidpid} | grep bcdDevice | awk '{print $2}' || echo "NA")
fi

# Scanner
scanner_match=$( sane-find-scanner -q | grep -m 1 "libusb" ) || scanner_match=""

if [[ -z "$scanner_match" ]]; then
  DATA["scanner_vendor"]="NA"
  DATA["scanner_model"]="NA"
else
  usb_path=$( echo "$scanner_match" | grep -oP "libusb:[0-9]+:[0-9]+" )

  bus=$( echo "$usb_path" | cut -d: -f2 )
  dev=$( echo "$usb_path" | cut -d: -f3 )
  dev_path="/dev/bus/usb/${bus}/${dev}"

  DATA["scanner_vendor"]=$( udevadm info --query=property --name="${dev_path}" | grep -m1 "ID_VENDOR=" | cut -d= -f2 || echo "NA" )
  DATA["scanner_model"]=$( udevadm info --query=property --name="${dev_path}" | grep -m1 "ID_MODEL=" | cut -d= -f2 || echo "NA" )
fi

# Printer
printer_dev=$( lsusb -v | awk '/^Bus/ {bus=$2; dev=$4} /bInterfaceClass +7 Printer/ { gsub(/:/,"",dev); print bus ":" dev; }') || printer_dev=""

if [[ -z "$printer_dev" ]]; then
  DATA["printer_vendor"]="NA"
  DATA["printer_model"]="NA"
else
  DATA["printer_vendor"]=$( lsusb -v -s "${printer_dev}" | grep idVendor | xargs | cut -d" " -f2- || echo "NA")
  DATA["printer_model"]=$( lsusb -v -s "${printer_dev}" | grep idProduct | xargs | cut -d" " -f2- || echo "NA")
fi

# Text based log
{
    echo "=========================================="
    echo " SYSTEM INVENTORY: $(date)"
    echo "=========================================="
    for key in "${!DATA[@]}"; do
        printf "%-30s : %s\n" "$key" "${DATA[$key]}"
    done
    echo "=========================================="
} > "$LOG_FILE"

# JSON log
echo "{" > "$JSON_FILE"
FIRST=true
for key in "${!DATA[@]}"; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$JSON_FILE"
    fi
    printf '  "%s": "%s"' "$key" "${DATA[$key]}" >> "$JSON_FILE"
done
echo -e "\n}" >> "$JSON_FILE"

# Change ownership and permissions to match votingworks logs
chown syslog:adm $LOG_FILE
chown syslog:adm $JSON_FILE
chmod 640 $LOG_FILE
chmod 640 $JSON_FILE

echo "Files created:"
echo "Log:  $LOG_FILE"
echo "JSON: $JSON_FILE"

exit 0
