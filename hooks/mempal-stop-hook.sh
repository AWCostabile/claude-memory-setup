#!/bin/bash
# MemPalace Stop Hook — upstream 3.6.0 wrapper + functional interpreter fallback
# MEMPALACE-PATCH:py-fallback-v3
# Upstream 3.6.0 made the stop hook silent and self-saving (transcript ingestion and
# diary logic live in mempalace.hooks_cli), so the old suppress-and-heartbeat patch is
# retired. The claude-mem baseline heartbeat is retired with it: claude-mem >= 13.x
# captures session observations natively, and scripts/memory-doctor.sh monitors that
# capture instead of double-writing. This patch only hardens interpreter resolution:
# the stock chain stops at python3/python, which on Windows can both be broken Store
# stubs while `py` works. Each candidate is probed with a real import.
run_mempalace_hook() {
  if command -v mempalace >/dev/null 2>&1; then
    mempalace hook run "$@"
    return $?
  fi

  for c in python3 python py; do
    if "$c" -c "import mempalace" >/dev/null 2>&1; then
      "$c" -m mempalace hook run "$@"
      return $?
    fi
  done

  echo "MemPalace hook error: could not find a runnable mempalace command or module" >&2
  return 1
}

run_mempalace_hook --hook stop --harness claude-code
