#!/bin/bash

# This script creates a virtual device allowing to use two Ultimate Ears
# HyperBoom in stereo mode. It mimicks the "Party Up" features of the
# Ultimate Ears mobile application.
#
# It requires:
# - pipewire
# - pipewire-pulse
#
# The two Bluetooth speakers must be paired and connected. The virtual device
# cannot be created if this is not the case. They are identified by their human
# name (which can be set as desired by their owner).
#
# You can change the following variables to adapt the script to your settings:
#
# - VIRTUAL_SINK_NAME: the virtual sink name.
# - VIRTUAL_SINK_DESCRIPTION: the name which will be shown in GUIs.
# - LEFT_SPEAKER: the human Bluetooth name for the left speaker.
# - RIGHT_SPEAKER: the human Bluetooth name for the right speaker.
#
# The following diagram shows the routes this script creates:
# ```
#                                             .------------------------.
#                                             |      HyperBoom #1      |
#                                             |------------------------|
#                                  .--------> = playback_FL            |
#                                  |          |                        |
#                                  |  .-----> = playback_FR            |
#                                  |  |       `------------------------'
#     .------------------------.   |  |
#     |   HyperBoom_Party_Up   |   |  |
#     |------------------------|   |  |
# --> = playback_1   capture_1 = --'--'
#     |                        |
# --> = playback_2   capture_2 = --.--.
#     `------------------------'   |  |
#                                  |  |       .------------------------.
#                                  |  |       |      HyperBoom #2      |
#                                  |  |       |------------------------|
#                                  |  `-----> = playback_FL            |
#                                  |          |                        |
#                                  `--------> = playback_FR            |
#                                             `------------------------'
# ```

# Virtual device name.
VIRTUAL_SINK_NAME="HyperBoom_Party_Up"

# Virtual device friendly name.
# Use non-breaking spaces because pactl does not parse regular spaces well.
VIRTUAL_SINK_DESCRIPTION="HyperBoom Party Up"

# Left and right speakers.
LEFT_SPEAKER="HyperBoom Noire"
RIGHT_SPEAKER="HyperBoom blanche"

# Checks if a required command is available on the system.
#
# Parameters:
#
# 1. command: The name of the command to check (e.g., pw-link or pactl).
# 2. package: The name of the package that provides the command, for user
#    instructions if missing.
#
# It prints a message indicating whether the command is found. If the command
# is missing, it exits the script with an error and suggests the package to
# install.
function require-command() {
    local command="$1"
    local package="$2"

    printf 'Looking for %s command... ' "$command"

    if ! command -v "$command" 2>&1 >/dev/null
    then
        printf 'not found (please install %s package)\n' "$package"
        exit 2
    else
        printf 'found\n'
    fi
}

# Checks if the specified speaker is available in the system audio device list.
#
# Parameters:
#
# 1. speaker: The name of the speaker to check (e.g., HyperBoom Noire or
#    HyperBoom White).
#
# It uses `pactl list` to look for the speaker's alias or ALSA name in the
# system's audio devices. It then prints a message indicating whether the
# speaker is found. If the speaker is missing, it exits the script with an
# error.
function require-speaker() {
    local speaker="$1"

    printf 'Looking for %s speaker... ' "$speaker"

    pactl list \
        | grep --extended --quiet "(device\.alias|alsa\.name) = \"$speaker\""

    if [ "$?" -ne 0 ]
    then
        printf 'not found\n'
        exit 1
    else
        printf 'found\n'
    fi
}

# Unloads any existing virtual sink modules with the same name as the one to be
# created.
#
# Parameters:
#
# 1. module_name: The name of the virtual sink module to unload (e.g.,
#    HyperBoom_Party_Up).
#
# It lists all currently loaded PulseAudio modules using
# `pactl list short modules`, filters the list for modules matching the given
# sink name and unloads each matching module by its ID to ensure no conflicts.
function unload-module() {
    local module_name="$1"
    
    pactl list short modules \
        | grep "sink_name=$VIRTUAL_SINK_NAME" \
        | while read module_id remain
        do
            printf 'Removing module %d\n' "$module_id"
            pactl unload-module "$module_id"
        done
}

# Creates a virtual audio sink to route audio between devices.
#
# Parameters:
#
# 1. module_name: The internal name of the virtual sink (e.g.,
#    HyperBoom_Party_Up).
# 2. module_description: The user-friendly description of the virtual sink
#    (e.g., HyperBoom Party Up).
#
# It uses `pactl` to load a `module-null-sink` (a virtual audio sink) with the
# given name and description, sets the channel map to FL,FR (stereo left and
# right) and waits 1 second to ensure the module is fully loaded.
function create-module() {
    local module_name="$1"
    local module_description="$2"

    printf 'Creating module %s\n' "$module_name"
    pactl \
        load-module module-null-sink \
        media.class=Audio/Duplex \
        sink_name="$module_name" \
        sink_properties=device.description="$module_description" \
        channel_map="[FL,FR]" \
        > /dev/null

    # Give the module some time to load.
    sleep 1
}

# Establishes links between the virtual sink and the physical speakers using
# `pw-link`.
#
# Parameters:
#
# 1. source: The name of the virtual sink (e.g., HyperBoom_Party_Up).
# 2. left_speaker: The name of the left speaker (e.g., HyperBoom Noire).
# 3. right_speaker: The name of the right speaker (e.g., HyperBoom White).
#
# It links the left channel (capture_1) of the virtual sink to both playback
# channels (playback_FL and playback_FR) of the left speaker, and links the
# right channel (capture_2) of the virtual sink to both playback channels of
# the right speaker.
function create-links() {
    local source="$1"
    local left_speaker="$2"
    local right_speaker="$3"

    printf 'Wiring %s to %s and %s\n' \
        "$source" \
        "$left_speaker" \
        "$right_speaker"

    pw-link "$source:capture_1" "$left_speaker:playback_FL"
    pw-link "$source:capture_1" "$left_speaker:playback_FR"

    pw-link "$source:capture_2" "$right_speaker:playback_FL"
    pw-link "$source:capture_2" "$right_speaker:playback_FR"
}

# Run the script.
function run-script() {
    # Ensure dependencies are present.
    require-command "pw-link" "pipewire-bin"
    require-command "pactl" "pulseaudio-utils"

    # Ensure devices are present.
    require-speaker "$LEFT_SPEAKER"
    require-speaker "$RIGHT_SPEAKER"

    # Create the virtual device and links.
    unload-module "$VIRTUAL_SINK_NAME"
    create-module "$VIRTUAL_SINK_NAME" "$VIRTUAL_SINK_DESCRIPTION"
    create-links "$VIRTUAL_SINK_NAME" "$LEFT_SPEAKER" "$RIGHT_SPEAKER"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && run-script

