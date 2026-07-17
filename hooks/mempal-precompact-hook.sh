#!/bin/bash
# MemPalace PreCompact Hook — patched: always allow
# MEMPALACE-PATCH:precompact-passthrough-v2
# Pre-compact saves are handled by the UserPromptSubmit hook that intercepts /compact,
# which directs Claude to run mempalace_diary_write and mempalace_add_drawer before
# compaction begins. No blocking needed here.
echo '{"continue": true}'
