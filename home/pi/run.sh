#!/usr/bin/env bash
# Vitadock+ Viewer Launcher Script
#
# Terminates existing MPV instances, disables the screensaver, configures UVC settings
# based on DISPLAY_MODE, and launches MPV with low-latency parameters.

set -euo pipefail
IFS=$'\n\t'

# ───── Constants ───────────────────────────────────────────────────────────────
LOGFILE="/var/log/vitadock_viewer.log"
SCREENSAVER_OFF="/home/pi/screensaveroff.sh"
GET_CFG="/home/pi/getConfig.sh"
REQUIRED_CMDS=(pkill bash v4l2-ctl mpv)

# ───── Logging Functions ───────────────────────────────────────────────────────
log() { echo "$(date --iso-8601=seconds) [INFO]  $*" | tee -a "$LOGFILE"; }
err() { echo "$(date --iso-8601=seconds) [ERROR] $*" | tee -a "$LOGFILE" >&2; }
trap 'err "Error at line $LINENO, exit code $?"; exit 1' ERR

# ───── Preflight Checks ─────────────────────────────────────────────────────────
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null || { err "Missing command: $cmd"; exit 1; }
done
[[ -x "$SCREENSAVER_OFF" ]] || { err "Screensaver-off script not found/executable: $SCREENSAVER_OFF"; exit 1; }

# ───── Step 1: Terminate MPV ────────────────────────────────────────────────────
log "Terminating any running MPV instances"
pkill -15 mpv && log "Sent SIGTERM to mpv" || log "No mpv processes to terminate"
sleep 1
pkill -9 mpv  && log "Sent SIGKILL to lingering mpv" || log "No lingering mpv to kill"

# ───── Step 2: Disable Screensaver ──────────────────────────────────────────────
log "Disabling screensaver"
bash "$SCREENSAVER_OFF" &>>"$LOGFILE" &

# ───── Step 3: Set Display Environment ─────────────────────────────────────────
export DISPLAY=:0
export XAUTHORITY="/home/pi/.Xauthority"
log "Environment set: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY"

# ───── Step 4: Configure UVC Based on DISPLAY_MODE ─────────────────────────────
DISPLAY_MODE=$("$GET_CFG" DISPLAY_MODE)
log "Configuring UVC for mode: $DISPLAY_MODE"
case "$DISPLAY_MODE" in
    fps)
        v4l2-ctl -d /dev/video0 -v width=864,height=488,pixelformat=NV12 -p 60 &>>"$LOGFILE" ;;
    res)
        v4l2-ctl -d /dev/video0 -v width=960,height=544,pixelformat=NV12 -p 30 &>>"$LOGFILE" ;;
    pc)
        v4l2-ctl -d /dev/video0 -v pixelformat=NV12 &>>"$LOGFILE" ;;
    sharp)
        v4l2-ctl -d /dev/video0 -v width=1280,height=720,pixelformat=NV12 -p 30 &>>"$LOGFILE" ;;
    *)
        err "Unknown DISPLAY_MODE: $DISPLAY_MODE" ;;
esac
log "UVC configuration applied"

# ───── Step 5: Launch MPV ───────────────────────────────────────────────────────
VIDEO_OUTPUT_LEVEL=$("$GET_CFG" VIDEO_OUTPUT_LEVEL)
log "Launching MPV with output level: $VIDEO_OUTPUT_LEVEL"
mpv av://v4l2:/dev/video0 \
    --profile=low-latency \
    --untimed \
    --no-audio \
    --opengl-glfinish=yes \
    --opengl-swapinterval=0 \
    --no-cache \
    --really-quiet \
    --fs \
    --force-window=immediate \
    --title=VitaDock+ \
    --no-border \
    --sws-scaler=lanczos \
    --sws-fast=yes \
    --scale=ewa_lanczossharp \
    --video-output-levels="$VIDEO_OUTPUT_LEVEL" \
    --osc=no &>>"$LOGFILE"

log "MPV exited successfully"
exit 0
