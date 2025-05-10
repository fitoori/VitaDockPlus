#!/usr/bin/env bash
# Vitadock+ Imaging Prep Script
#
# Cleans personal data, erases swap, clears logs/history,
# and shuts down to prepare the device for imaging.

set -euo pipefail
IFS=$'\n\t'

# ───── Constants ───────────────────────────────────────────────────────────────
LOGFILE="/var/log/vitadock_imaging_prep.log"
NOTIFY_SCRIPT="/home/pi/notify.sh"
WPA_SRC="/home/pi/wpa_supplicant.conf"
WPA_DEST="/etc/wpa_supplicant/wpa_supplicant.conf"
BTCTL="bluetoothctl"
SWAP_OFF_CMD="swapoff"
SWAPON_CMD="swapon"
TRASH_EMPTY="trash-empty"
IFACE="wlan0"
HISTORY_FILE="/home/pi/.bash_history"
TMP_FILE="/home/pi/1.txt"
REQUIRED_CMDS=(cp ifconfig "$BTCTL" $SWAP_OFF_CMD $SWAPON_CMD rm $TRASH_EMPTY shutdown)

# ───── Logging Functions ───────────────────────────────────────────────────────
log() { echo "$(date --iso-8601=seconds) [INFO]  $*" | tee -a "$LOGFILE"; }
err() { echo "$(date --iso-8601=seconds) [ERROR] $*" | tee -a "$LOGFILE" >&2; }
trap 'err "Error at line $LINENO (exit code $?)"; exit 1' ERR

# ───── Check for Root ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root"
    exit 1
fi

# ───── Dependency Check ────────────────────────────────────────────────────────
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null || { err "Missing required command: $cmd"; exit 1; }
done
log "All required commands are available"

# ───── Step 1: Notify User ──────────────────────────────────────────────────────
log "Notifying user: Preparing for imaging"
"$NOTIFY_SCRIPT" "Preparing VitaDock+ for imaging..."

# ───── Step 2: Preserve Wi-Fi Config ────────────────────────────────────────────
if [[ -f "$WPA_SRC" ]]; then
    log "Copying Wi-Fi config to $WPA_DEST"
    cp "$WPA_SRC" "$WPA_DEST"
else
    err "Source WPA config not found: $WPA_SRC"
fi

# ───── Step 3: Disable Wi-Fi Interface ──────────────────────────────────────────
if ifconfig "$IFACE" &>/dev/null; then
    log "Bringing down interface $IFACE"
    ifconfig "$IFACE" down
else
    log "Interface $IFACE not present, skipping"
fi

# ───── Step 4: Remove Paired Bluetooth Devices ──────────────────────────────────
log "Removing all paired Bluetooth devices"
device_list=$($BTCTL devices | grep -oE "[[:xdigit:]:]{8,17}")
if [[ -z "$device_list" ]]; then
    log "No Bluetooth device addresses found"
else
    while read -r addr; do
        log "Removing Bluetooth device: $addr"
        echo "remove $addr" | $BTCTL
    done <<< "$device_list"
fi

# ───── Step 5: Reset Swap File ──────────────────────────────────────────────────
log "Disabling all swap"
$SWAP_OFF_CMD -a

SWAP_PATHS=("/var/swap" "/swapfile")
for path in "${SWAP_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
        log "Removing swap path: $path"
        rm -rf "$path"
    else
        log "No swap at $path, skipping"
    fi
done

# Clear Trash
log "Emptying trash"
$TRASH_EMPTY --yes || log "Trash empty failed or no trash" 

# Re-enable swap (per fstab)
log "Re-enabling swap as per fstab"
$SWAPON_CMD -a || log "No swap to enable or failed"

# ───── Step 6: Clear Logs and History ───────────────────────────────────────────
JOURNAL_PATHS=("/var/log/journal" "/var/journal")
for jpath in "${JOURNAL_PATHS[@]}"; do
    if [[ -d "$jpath" ]]; then
        log "Removing journal directory: $jpath"
        rm -rf "$jpath"
    fi
done

if [[ -f "$HISTORY_FILE" ]]; then
    log "Clearing bash history: $HISTORY_FILE"
    rm -f "$HISTORY_FILE"
fi

# Remove temporary files
if [[ -f "$TMP_FILE" ]]; then
    log "Removing temp file: $TMP_FILE"
    rm -f "$TMP_FILE"
fi

# ───── Step 7: Shutdown ─────────────────────────────────────────────────────────
log "Shutdown now to finalize imaging prep"
shutdown now
