#!/usr/bin/env bash
# Vitadock+ Bluetooth Dongle Switch Script
#
# Switches audio mode to Bluetooth (BT), disables AUX loopback if active,
# applies blacklist config, and reboots to enable the dongle.

set -euo pipefail
IFS=$'\n\t'

# ───── Constants ───────────────────────────────────────────────────────────────
LOGFILE="/var/log/vitadock_switch_bt.log"
GET_CFG="/home/pi/getConfig.sh"
UPDATE_CFG="/home/pi/updateConfig.sh"
NOTIFY="/home/pi/notify.sh"
PULSECTL="pactl"
BLACKLIST_CONF="blacklist-bluetooth.conf"
MODPROBE_DIR="/etc/modprobe.d"
REBOOT_CMD="reboot"

# ───── Logging Functions ───────────────────────────────────────────────────────
log() { echo "$(date --iso-8601=seconds) [INFO]  $*" | tee -a "$LOGFILE"; }
err() { echo "$(date --iso-8601=seconds) [ERROR] $*" | tee -a "$LOGFILE" >&2; }
trap 'err "Error at line $LINENO (exit code $?)"; exit 1' ERR

# ───── Preflight Checks ─────────────────────────────────────────────────────────
# Must run as root
if [[ $EUID -ne 0 ]]; then
    err "Script must be run as root"
    exit 1
fi
# Required commands and scripts
for cmd in "$PULSECTL" "$REBOOT_CMD"; do
    command -v "$cmd" >/dev/null || { err "Missing command: $cmd"; exit 1; }
done
for script in "$GET_CFG" "$UPDATE_CFG" "$NOTIFY"; do
    [[ -x "$script" ]] || { err "Script not executable: $script"; exit 1; }
done

# ───── Step 1: Notify User ──────────────────────────────────────────────────────
log "Notifying user: Switching to Bluetooth dongle mode"
"$NOTIFY" "Switching to Dongle Bluetooth..."

# ───── Step 2: Update Configuration ──────────────────────────────────────────────
CURRENT_MODE=$("$GET_CFG" AUDIO_MODE || echo "")
log "Current AUDIO_MODE: ${CURRENT_MODE:-undefined}"
log "Updating AUDIO_MODE to BT"
"$UPDATE_CFG" AUDIO_MODE BT

# ───── Step 3: Disable AUX Loopback ─────────────────────────────────────────────
if [[ "$CURRENT_MODE" == "AUX" ]]; then
    log "Unloading PulseAudio loopback modules"
    mapfile -t mods < <($PULSECTL list short modules | awk '$2=="module-loopback" {print $1}')
    for m in "${mods[@]}"; do
        $PULSECTL unload-module "$m"
        log "Unloaded module-loopback id=$m"
    done
else
    log "AUX mode not active; skipping loopback unload"
fi

# ───── Step 4: Apply Bluetooth Blacklist Config ──────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CONF="$SCRIPT_DIR/$BLACKLIST_CONF"
if [[ -f "$SRC_CONF" ]]; then
    log "Moving $BLACKLIST_CONF to $MODPROBE_DIR"
    mv "$SRC_CONF" "$MODPROBE_DIR/"
    log "Blacklist config applied"
else
    err "Blacklist config not found at $SRC_CONF"
fi

# ───── Step 5: Reboot ───────────────────────────────────────────────────────────
log "Rebooting system to apply Bluetooth dongle settings"
$REBOOT_CMD
