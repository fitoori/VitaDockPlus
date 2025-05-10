#!/usr/bin/env bash
# VitaDock+ AUX Switch Script
#
# Switches the audio mode to AUX:
# 1. Updates configuration
# 2. Notifies user of mode change
# 3. Ensures AUX_SOURCE and AUX_SINK are set (invokes config tool if not)
# 4. Reloads PulseAudio loopback module accordingly

set -euo pipefail
IFS=$'\n\t'

# ───── Constants ───────────────────────────────────────────────────────────────
LOGFILE="/var/log/vitadock_switch_aux.log"
GET_CFG="/home/pi/getConfig.sh"
UPDATE_CFG="/home/pi/updateConfig.sh"
NOTIFY="/home/pi/notify.sh"
CONFIG_TOOL="/home/pi/configureAux.sh"
REQUIRED_CMDS=(bash pactl)

# ───── Logging ─────────────────────────────────────────────────────────────────
log() { echo "$(date --iso-8601=seconds) [INFO]  $*" | tee -a "$LOGFILE"; }
err() { echo "$(date --iso-8601=seconds) [ERROR] $*" | tee -a "$LOGFILE" >&2; }
trap 'err "Failure at line $LINENO (exit $?)"; exit 1' ERR

# ───── Preflight Checks ────────────────────────────────────────────────────────
# Check scripts and commands
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null || { err "Missing command: $cmd"; exit 1; }
done
for script in "$GET_CFG" "$UPDATE_CFG" "$NOTIFY"; do
    [[ -x "$script" ]] || { err "Script not found or not executable: $script"; exit 1; }
done

# ───── Step 1: Notify and Update Mode ───────────────────────────────────────────
log "Setting AUDIO_MODE to AUX"
"$NOTIFY" "Switching to AUX Input..."
"$UPDATE_CFG" AUDIO_MODE AUX

# ───── Step 2: Fetch AUX Settings ──────────────────────────────────────────────
AUX_SOURCE=$("$GET_CFG" AUX_SOURCE)
AUX_SINK=$("$GET_CFG" AUX_SINK)

# If either is unset, launch configuration tool
if [[ -z "$AUX_SOURCE" || -z "$AUX_SINK" ]]; then
    log "AUX_SOURCE or AUX_SINK missing, launching config tool"
    if command -v x-terminal-emulator >/dev/null; then
        x-terminal-emulator -e bash "$CONFIG_TOOL"
    else
        err "x-terminal-emulator not found; run $CONFIG_TOOL manually"
        exit 1
    fi
    # Re-fetch after config
    AUX_SOURCE=$("$GET_CFG" AUX_SOURCE)
    AUX_SINK=$("$GET_CFG" AUX_SINK)
    [[ -n "$AUX_SOURCE" && -n "$AUX_SINK" ]] || { err "Configuration incomplete: AUX_SOURCE or AUX_SINK still unset"; exit 1; }
    log "Configuration set: source=$AUX_SOURCE sink=$AUX_SINK"
fi

# ───── Step 3: Reload Loopback Module ───────────────────────────────────────────
log "Reloading PulseAudio loopback"
# Unload existing instances
mapfile -t mods < <(pactl list short modules | awk '$2=="module-loopback" {print $1}')
for m in "${mods[@]}"; do
    pactl unload-module "$m"
    log "Unloaded module-loopback id=$m"
done
# Load new
mod_id=$(pactl load-module module-loopback source="$AUX_SOURCE" sink="$AUX_SINK")
log "Loaded module-loopback id=$mod_id (src=$AUX_SOURCE sink=$AUX_SINK)"

log "AUX mode enabled successfully"
exit 0

