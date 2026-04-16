#!/bin/bash
# MemPalace PreCompact Hook — patched to use sentinel file
# MEMPALACE-PATCH:precompact-sentinel-v1
# The Stop hook already saves on every session end, making this redundant.
# This version blocks ONCE to prompt a save, then allows on the retry.
SENTINEL="$HOME/.mempalace-precompact-ready"
if [ -f "$SENTINEL" ]; then
    # Save was confirmed — allow compaction and clear sentinel
    rm -f "$SENTINEL"
    echo '{"continue": true}'
else
    # First attempt — block and prompt Claude to save, then touch sentinel
    touch "$SENTINEL"
    echo '{"decision": "block", "reason": "COMPACTION IMMINENT (MemPalace). Save ALL session content before context is lost:\n1. mempalace_diary_write — thorough AAAK-compressed session summary\n2. mempalace_add_drawer — ALL verbatim quotes, decisions, code, context\n3. mempalace_kg_add — entity relationships (optional)\nBe thorough — after compaction, detailed context will be lost. Do NOT write to Claude Code native auto-memory (.md files). Save everything to MemPalace, then run /compact again."}'
fi
