#!/bin/bash
set -euxo pipefail

LOGFILE=~/.lockhst
LOCKFILE=~/.lock.lock

# Function to clean up lock file and log exit.
cleanup() {
    rm -f "$LOCKFILE"
    echo -e "[$(date +%H:%M:%S)] Exiting...\n" >> "$LOGFILE"
}
trap cleanup EXIT # Ensuring cleanup on exit.

# Check if script is already running
if [ -f "$LOCKFILE" ]; then
    echo "Script is already running."
    exit 1
fi
touch "$LOCKFILE"
echo "[$(date +%H:%M:%S)] Starting..." >> "$LOGFILE"

# Shutdown in 35 minutes from now, but only if there is no current schedule for shutdown.
shutdown --show || { shutdown -h +35 2>>"$LOGFILE"; }

# Lock the screen. If swaylock crashes or returns a non-zero exit code this script will stop (because `set -e`) and the shutdown will not be canceled.
# Also, by design, crashing swaylock is not enough to unlock the screen.
pgrep swaylock || { echo "[$(date +%H:%M:%S)] Locking screen..." >> "$LOGFILE" && swaylock -Fe -c 000000 && echo "[$(date +%H:%M:%S)] Screen unlocked!" >> "$LOGFILE"; }

# Cancel shutdown if there is no running swaylock process.
pgrep swaylock || { shutdown -c && echo "[$(date +%H:%M:%S)] Shutdown canceled!" >> "$LOGFILE"; }
