#!/bin/bash
# tuneup-nudge.sh — SessionStart nudge when the memory doctor hasn't run recently.
#
# memory-doctor.sh stamps ~/.claude/memory-doctor.last on every run. This script prints
# a one-line nudge when that stamp is missing or older than TUNEUP_DAYS (default 14 —
# a fortnightly tune-up) and prints nothing otherwise, so it is silent in a healthy cadence.
# Wire it as a SessionStart hook; the output lands in Claude's context and Claude relays it.

TUNEUP_DAYS="${TUNEUP_DAYS:-14}"
F="$HOME/.claude/memory-doctor.last"
NOW=$(date +%s)
LAST=$(cat "$F" 2>/dev/null || echo 0)
case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
AGE=$(( (NOW - LAST) / 86400 ))

if [ "$LAST" -eq 0 ]; then
    echo "MEMORY TUNE-UP DUE: the memory doctor has never been run on this machine. Tell the user, and offer to run: bash scripts/memory-doctor.sh"
elif [ "$AGE" -ge "$TUNEUP_DAYS" ]; then
    echo "MEMORY TUNE-UP DUE: last memory-doctor run was $AGE days ago (threshold ${TUNEUP_DAYS}d). Tell the user, and offer to run: bash scripts/memory-doctor.sh"
fi
