#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ───── Constants ────────────────────────────────────────────────────────────────
LOGFILE="/var/log/vitadock_init.log"
CONFIG_SCRIPT="/home/pi/getConfig.sh"
GPIO_SCRIPT="/home/pi/gpioBTDiscovery.py"
SCREENSAVER_SCRIPT="/home/pi/screensaveron.sh"
RUN_SCRIPT="/home/pi/run.sh"
NOTIF_DAEMON="/usr/lib/notification-daemon/notification-daemon"
REQUIRED_CMDS=(udevadm bluetoothctl pactl python3 dtoverlay)

# ───── Logging ─────────────────────────────────────────────────────────────────
log() { echo "$(date --iso-8601=seconds) [INFO]  $*" | tee -a "$LOGFILE"; }
err() { echo "$(date --iso-8601=seconds) [ERROR] $*" | tee -a "$LOGFILE" >&2; }

trap 'err "Failed at line $LINENO (exit code $?)"; exit 1' ERR

# ───── Prep ───────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then err "Must run as root"; exit 1; fi
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null || { err "Missing command: $cmd"; exit 1; }
done

log "Triggering udev rules"
udevadm trigger --action=change

# ───── Notification Daemon ────────────────────────────────────────────────────
if pgrep -f "$(basename "$NOTIF_DAEMON")" >/dev/null; then
    log "Notification daemon already running"
elif [[ -x "$NOTIF_DAEMON" ]]; then
    log "Starting notification daemon"
    "$NOTIF_DAEMON" &>>"$LOGFILE" &
else
    err "Notification daemon not executable"
fi

# ───── Audio Setup ─────────────────────────────────────────────────────────────
log "Loading audio mode from config"
AUDIO_MODE=$("$CONFIG_SCRIPT" AUDIO_MODE)
case "$AUDIO_MODE" in
    BT)
        log "Powering on Bluetooth audio"
        bluetoothctl power on &>>"$LOGFILE"
        ;;
    AUX)
        AUX_SRC=$("$CONFIG_SCRIPT" AUX_SOURCE)
        AUX_SNK=$("$CONFIG_SCRIPT" AUX_SINK)
        [[ -n "$AUX_SRC" && -n "$AUX_SNK" ]] || { err "AUX_SOURCE/AUX_SINK empty"; exit 1; }
        if pactl list short modules | grep -q "module-loopback source=$AUX_SRC sink=$AUX_SNK"; then
            log "Loopback already loaded"
        else
            log "Loading loopback ($AUX_SRC → $AUX_SNK)"
            pactl load-module module-loopback source="$AUX_SRC" sink="$AUX_SNK" &>>"$LOGFILE"
        fi
        ;;
    *)
        err "Invalid AUDIO_MODE: $AUDIO_MODE"
        exit 1
        ;;
esac

# ───── GPIO BT Discovery ──────────────────────────────────────────────────────
if pgrep -f "$(basename "$GPIO_SCRIPT")" >/dev/null; then
    log "GPIO BT discovery already running"
else
    log "Starting GPIO BT discovery"
    nohup python3 "$GPIO_SCRIPT" >>"$LOGFILE" 2>&1 &
fi

# ───── GPIO Key Registration ──────────────────────────────────────────────────
register_gpio_key() {
    local key_conf=$1 keycode=$2 gpio=$("$CONFIG_SCRIPT" "$key_conf")
    [[ -n "$gpio" ]] || { log "No $key_conf"; return; }
    log "Registering GPIO $gpio → keycode $keycode"
    dtoverlay gpio-key gpio="$gpio" keycode="$keycode" label="GPIO${gpio}" &>>"$LOGFILE"
}

declare -A KEY_MAP=(
    [LEFT_KEY_GPIO]=105 [RIGHT_KEY_GPIO]=106
    [UP_KEY_GPIO]=103   [DOWN_KEY_GPIO]=108
    [WINDOWS_KEY_GPIO]=125 [ESCAPE_KEY_GPIO]=1
    [ENTER_KEY_GPIO]=28 [TAB_KEY_GPIO]=15
)
for k in "${!KEY_MAP[@]}"; do
    register_gpio_key "$k" "${KEY_MAP[$k]}"
done

# ───── Screensaver ────────────────────────────────────────────────────────────
if pgrep -f "$(basename "$SCREENSAVER_SCRIPT")" >/dev/null; then
    log "Screensaver already active"
elif [[ -x "$SCREENSAVER_SCRIPT" ]]; then
    log "Enabling screensaver"
    bash "$SCREENSAVER_SCRIPT" &>>"$LOGFILE" &
else
    err "Screensaver script missing or not executable"
fi

# ───── Viewer (disabled: screen-tearing) ────────────────────────────────────────
# if bash "$RUN_SCRIPT"; then
#     log "Viewer launched"
# else
#     log "Viewer failed; re-enabling screensaver"
#     bash "$SCREENSAVER_SCRIPT" &>>"$LOGFILE" &
# fi

log "VitaDock+ init complete"
