#!/bin/bash
set -euo pipefail

LOGFILE=~/.lockhst
DELAY_SHUTDOWN_MINUTES_FILE=~/.delay_shutdown_after_lock
DEFAULT_TIME_TO_SHUTDOWN=75

while read line 
do
    case "$line" in
        *"{'LockedHint': <true>}"*) # screen locked
            TIME_TO_SHUTDOWN=$(cat $DELAY_SHUTDOWN_MINUTES_FILE 2>/dev/null && rm -f $DELAY_SHUTDOWN_MINUTES_FILE || echo $DEFAULT_TIME_TO_SHUTDOWN)
            [[ "$TIME_TO_SHUTDOWN" -gt 0 && "$TIME_TO_SHUTDOWN" -le 300 ]] || TIME_TO_SHUTDOWN=$DEFAULT_TIME_TO_SHUTDOWN
            shutdown --show || { echo "[$(date +%H:%M:%S)] Locking screen..." >> "$LOGFILE" && shutdown -h +${TIME_TO_SHUTDOWN} 2>>"$LOGFILE"; };
        ;;
        *"{'LockedHint': <false>}"*) # screen unlocked
            shutdown -c && echo "[$(date +%H:%M:%S)] Shutdown canceled!" >> "$LOGFILE";
        ;;
    esac
done < <(gdbus monitor -y -d org.freedesktop.login1)
