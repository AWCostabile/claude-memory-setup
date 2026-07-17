#!/bin/bash
# sync-hooks.sh — drift-repair loop for the MemPalace hook patches.
#
# The two patched hooks in this repo's hooks/ directory are canonical. Plugin updates
# overwrite the installed copies with stock versions; this script detects that drift
# and re-applies the patches.
#
#   bash scripts/sync-hooks.sh          # repair: copy canon over any drifted target
#   bash scripts/sync-hooks.sh --check  # report drift only, change nothing
#
# Targets, per hook file:
#   ~/.claude/plugins/marketplaces/mempalace/.claude-plugin/hooks/
#   ~/.claude/plugins/cache/mempalace/mempalace/<every-version>/hooks/
#
# Exit code = number of drifted targets (0 means everything in sync / repaired).
# Prints one line per target; prints nothing but the summary when all is in sync,
# so it is quiet enough to run from a SessionStart hook.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANON_DIR="$REPO_ROOT/hooks"
CHECK_ONLY=""
[ "$1" = "--check" ] && CHECK_ONLY=1

DRIFT=0
REPAIRED=0

sync_target() {
    canon="$1"
    target="$2"
    name="$(basename "$canon")"
    [ -d "$(dirname "$target")" ] || return 0   # location doesn't exist on this install
    if cmp -s "$canon" "$target" 2>/dev/null; then
        return 0
    fi
    DRIFT=$((DRIFT+1))
    if [ -n "$CHECK_ONLY" ]; then
        echo "DRIFT: $target differs from canon ($name)"
    else
        cp "$canon" "$target" && chmod +x "$target" \
            && { echo "REPAIRED: $target (re-applied $name)"; REPAIRED=$((REPAIRED+1)); } \
            || echo "ERROR: could not repair $target"
    fi
}

for canon in "$CANON_DIR"/*.sh; do
    [ -f "$canon" ] || continue
    name="$(basename "$canon")"
    sync_target "$canon" "$HOME/.claude/plugins/marketplaces/mempalace/.claude-plugin/hooks/$name"
    for vdir in "$HOME"/.claude/plugins/cache/mempalace/mempalace/*/; do
        [ -d "$vdir" ] && sync_target "$canon" "${vdir}hooks/$name"
    done
done

if [ "$DRIFT" -eq 0 ]; then
    echo "sync-hooks: all hook patches in sync"
elif [ -n "$CHECK_ONLY" ]; then
    echo "sync-hooks: $DRIFT target(s) drifted — run without --check to repair"
else
    echo "sync-hooks: repaired $REPAIRED of $DRIFT drifted target(s)"
fi
exit "$DRIFT"
