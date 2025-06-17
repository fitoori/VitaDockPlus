#!/bin/bash

# Aux Configuration Tool
# Provides a simple way to select the input (Source) and output (Sink) devices 
# to be used by the PulseAudio Loopback Module for Vita audio.
# The script uses `pactl list short sources` and `pactl list short sinks` 
# to populate menu items. The selected items are saved in vitadock.conf.
# If Aux is already enabled, running this will reload the loopback module 
# with the newly selected devices.

WELCOME_DESC="This tool is used to configure capturing the PS Vita's audio via AUX input.\n\nUse the arrow keys to navigate options and the Tab key to switch buttons.\n\nPress Enter to select the highlighted item."
whiptail --title "Aux Configuration Tool" --msgbox "$WELCOME_DESC" 20 80

# Introductory note for devices that lack native line-in (e.g., Pi 3 and 4)
INTRO_DESC="The Raspberry Pi 3 and 4 do NOT have a built-in line-in audio device."
INTRO_DESC+="\n\nA USB audio capture device with line-in capability is required for AUX input.\n\nPlease see the VitaDock+ README (Aux Audio section) for more information."
INTRO_DESC+="\n\nEnsure your USB audio input device is connected before continuing."
whiptail --title "Aux Configuration Tool" --msgbox "$INTRO_DESC" 20 80

# Initialize arrays for source (input) and sink (output) options
SRC_OPTIONS=()
SNK_OPTIONS=()

# Get list of sources and sinks via PulseAudio (pactl)
SOURCES=$(pactl list short sources)
SINKS=$(pactl list short sinks)

# Determine if any line-in (stereo input) device is present
lineInFound=false
echo "$SOURCES" | grep -qiE 'alsa_input.*stereo' && lineInFound=true

# Parse sources list and populate SRC_OPTIONS for menu
while read -r line; do
    ID=$(echo "$line" | cut -f1)
    NAME=$(echo "$line" | cut -f2)
    # Only consider actual input sources (skip monitors or non-alsa inputs)
    if [[ "$NAME" != "alsa_input"* ]]; then
        continue
    fi
    # If a line-in device exists, exclude sources with "mic" in the name (likely microphone inputs)
    if $lineInFound; then
        if [[ "$NAME" == *mic* || "$NAME" == *Mic* ]]; then
            continue
        fi
    fi
    # Add the source ID and a user-friendly name to the options array
    SRC_OPTIONS+=("$ID")
    # Remove the 'alsa_input.' prefix for display, if present
    SRC_OPTIONS+=("${NAME/alsa_input./}")
done <<< "$SOURCES"

# If no input devices were found after filtering, alert the user and exit
if [ ${#SRC_OPTIONS[@]} -eq 0 ]; then
    whiptail --title "Aux Configuration Tool" --msgbox "No audio input devices found.\nPlease connect a USB audio input device and try again." 20 80
    exit 1
fi

# Prompt user to select the input (source) device
SRC_TITLE="Select Input Device"
SRC_DESC="Select the device used to capture the PS Vita's audio.\n(For example, your USB line-in device or microphone.)"
SELECTED_SRC=$(whiptail --title "$SRC_TITLE" --menu "$SRC_DESC" 20 80 10 "${SRC_OPTIONS[@]}" 3>&1 1>&2 2>&3)
# If the user canceled the menu, exit
[ $? -ne 0 ] && exit 1

# Parse sinks list and populate SNK_OPTIONS for menu
INDX=0  # reuse index variable for sinks
while read -r line; do
    ID=$(echo "$line" | cut -f1)
    NAME=$(echo "$line" | cut -f2)
    # Only consider actual output sinks (could filter if needed, e.g., skip monitors)
    if [[ "$NAME" != "alsa_output"* ]]; then
        continue
    fi
    # Add sink ID and name (with prefix removed) to options array
    SNK_OPTIONS+=("$ID")
    SNK_OPTIONS+=("${NAME/alsa_output./}")
    # Set default selection to HDMI if available (for better UX, as Vita audio likely goes to TV)
    if [[ "$NAME" == *"hdmi"* ]]; then
        DEFAULT_SNK="$ID"
    fi
done <<< "$SINKS"

if [ ${#SNK_OPTIONS[@]} -eq 0 ]; then
    whiptail --title "Aux Configuration Tool" --msgbox "No audio output devices found (no sinks)." 20 80
    exit 1
fi

# Prompt user to select the output (sink) device, defaulting to HDMI if found
SNK_TITLE="Select Output Device"
SNK_DESC="Select the device that will play the PS Vita's audio (e.g. your TV via HDMI)."
SELECTED_SNK=$(whiptail --title "$SNK_TITLE" --menu "$SNK_DESC" --default-item "${DEFAULT_SNK:-0}" 20 80 10 "${SNK_OPTIONS[@]}" 3>&1 1>&2 2>&3)
[ $? -ne 0 ] && exit 1  # exit if user canceled

# If AUX is already active, reload the loopback with new devices; otherwise will be loaded on enable
AUDIO_MODE=$(/home/pi/getConfig.sh "AUDIO_MODE")
if [ "$AUDIO_MODE" == "AUX" ]; then
    pactl unload-module module-loopback 2>/dev/null
    pactl load-module module-loopback source="$SELECTED_SRC" sink="$SELECTED_SNK" 2>/dev/null
fi

# Save the selected source and sink to configuration for future use
/home/pi/updateConfig.sh "AUX_SOURCE" "$SELECTED_SRC"
/home/pi/updateConfig.sh "AUX_SINK"   "$SELECTED_SNK"

# Inform the user that configuration is complete
whiptail --title "Aux Configuration Tool" --msgbox "Aux audio input has been configured.\nSource: $SELECTED_SRC\nSink: $SELECTED_SNK" 10 60
