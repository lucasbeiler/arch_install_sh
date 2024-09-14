#!/bin/bash
set -euo pipefail

LOGFILE=~/.lockhst
DELAY_SHUTDOWN_FILE=~/.delay_shutdown_after_lock
TIME_TO_SHUTDOWN=75
  
while read line 
do
    case "$line" in
        *"{'LockedHint': <true>}"*) # screen locked
            [[ $(date +%_H) -ge 20 || $(date +%_H) -le 5 || -f "$DELAY_SHUTDOWN_FILE" ]] && TIME_TO_SHUTDOWN=100;
            shutdown --show || { echo "[$(date +%H:%M:%S)] Locking screen..." >> "$LOGFILE" && shutdown -h +${TIME_TO_SHUTDOWN} 2>>"$LOGFILE"; };
        ;;
        *"{'LockedHint': <false>}"*) # screen unlocked
            shutdown -c && echo "[$(date +%H:%M:%S)] Shutdown canceled!" >> "$LOGFILE";
        ;;
    esac
done < <(gdbus monitor -y -d org.freedesktop.login1)
