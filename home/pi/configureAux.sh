#!/usr/bin/env bash
# Aux Configuration Tool
#
# Provides a simple way to select the input (Source) and output (Sink) devices
# to be used by the Loop Back Module.
# Parses the output from `pactl list short sources` and `pactl list short sinks`
# to populate menu items. Selected items are then saved within the vitadock.conf
# If Aux is enabled when run the Loopback Module will be reloaded with the newly
# selected devices.

set -euo pipefail
IFS=$'\n\t'

# ───── Constants ───────────────────────────────────────────────────────────────
LOGFILE="/var/log/vitadock_aux_config.log"
GET_CFG="/home/pi/getConfig.sh"
UPDATE_CFG="/home/pi/updateConfig.sh"
REQUIRED_CMDS=(whiptail pactl awk cut grep sed)

# ───── Logging ─────────────────────────────────────────────────────────────────
log() { echo "$(date --iso-8601=seconds) [INFO]  $*" | tee -a "$LOGFILE"; }
err() { echo "$(date --iso-8601=seconds) [ERROR] $*" | tee -a "$LOGFILE" >&2; }

# Trap any error and report
trap 'err "Failed at line $LINENO (exit code $?)"; exit 1' ERR

# ───── Preflight Checks ────────────────────────────────────────────────────────
# Must run as root
if [[ $EUID -ne 0 ]]; then err "Must run as root"; exit 1; fi
# Check required commands
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null || { err "Missing command: $cmd"; exit 1; }
done
# Ensure config scripts exist and are executable
[[ -x "$GET_CFG" && -x "$UPDATE_CFG" ]] || { err "Config scripts missing/executable"; exit 1; }

# ───── Welcome & Intro Dialogs ─────────────────────────────────────────────────
whiptail --title "Aux Configuration Tool" --msgbox \
"This tool configures PSVita Aux input.\n\nUse arrows/Tab↹ to navigate, Enter⏎ to select." \
20 80 || { log "User cancelled"; exit 0; }

whiptail --title "Aux Configuration Tool" --msgbox \
"Raspberry Pi lacks line-in. Connect USB audio device first.\n\nSee README: https://github.com/SilentNightx/VitaDockPlus" \
20 80 || { log "User cancelled"; exit 0; }

# ───── Build Source List ───────────────────────────────────────────────────────
declare -a SRC_MENU
mapfile -t _src < <(pactl list short sources)
for line in "${_src[@]}"; do
    id=$(echo "$line" | cut -f1)
    name=$(echo "$line" | cut -f2)
    # Only include alsa_input sources
    [[ "$name" == alsa_input.* ]] || continue
    label=${name#alsa_input.}
    SRC_MENU+=("$id" "$label")
done

# Handle no sources found
if [[ ${#SRC_MENU[@]} -eq 0 ]]; then
    whiptail --title "Aux Configuration Tool" --msgbox \
    "No input devices found; plug in your USB audio device." 20 80
    exit 1
fi

# Prompt user to select source
SELECTED_SRC=$(whiptail --title "Select Input Device" --menu \
"Choose USB line-in:" 20 80 10 "${SRC_MENU[@]}" 3>&1 1>&2 2>&3) \
|| { log "Input selection cancelled"; exit 0; }
log "Selected source: $SELECTED_SRC"

# ───── Build Sink List ─────────────────────────────────────────────────────────
declare -a SNK_MENU
DEFAULT_SNK=""
mapfile -t _snk < <(pactl list short sinks)
for line in "${_snk[@]}"; do
    id=$(echo "$line" | cut -f1)
    name=$(echo "$line" | cut -f2)
    label=${name#alsa_output.}
    SNK_MENU+=("$id" "$label")
    # Default to HDMI for better UX
    [[ -z $DEFAULT_SNK && "$label" == *hdmi* ]] && DEFAULT_SNK="$id"
done

# Handle no sinks found
if [[ ${#SNK_MENU[@]} -eq 0 ]]; then
    whiptail --title "Aux Configuration Tool" --msgbox \
    "No output devices found." 20 80
    exit 1
fi

# Prompt user to select sink
SELECTED_SNK=$(whiptail --title "Select Output Device" --menu \
"Choose playback (e.g. HDMI):" 20 80 10 "${SNK_MENU[@]}" \
--default-item "${DEFAULT_SNK:-${SNK_MENU[0]}}" 3>&1 1>&2 2>&3) \
|| { log "Output selection cancelled"; exit 0; }
log "Selected sink:   $SELECTED_SNK"

# ───── Reload Loopback Module if AUX Active ───────────────────────────────────
AUDIO_MODE=$("$GET_CFG" AUDIO_MODE)
if [[ "$AUDIO_MODE" == "AUX" ]]; then
    log "Reloading loopback module"
    # Unload existing module-loopback instances
    mapfile -t mods < <(pactl list short modules | awk '$2=="module-loopback" {print $1}')
    for m in "${mods[@]}"; do
        pactl unload-module "$m"
        log "Unloaded module-loopback id=$m"
    done
    # Load new loopback
    mod_id=$(pactl load-module module-loopback source="$SELECTED_SRC" sink=\
"$SELECTED_SNK")
    log "Loaded module-loopback id=$mod_id (src=$SELECTED_SRC sink=$SELECTED_SNK)"
fi

# ───── Persist Configuration ──────────────────────────────────────────────────
"$UPDATE_CFG" AUX_SOURCE "$SELECTED_SRC"
log "Updated AUX_SOURCE to $SELECTED_SRC"

"$UPDATE_CFG" AUX_SINK   "$SELECTED_SNK"
log "Updated AUX_SINK   to $SELECTED_SNK"

log "Aux configuration complete."
