#!/bin/bash
# MemPalace PreCompact Hook — upstream 3.6.0 wrapper + functional interpreter fallback
# MEMPALACE-PATCH:py-fallback-v3
# Upstream 3.6.0 retired the old unconditional-block behavior (hook logic now lives in
# mempalace.hooks_cli and allows compaction), so the passthrough patch is no longer
# needed. This patch only hardens interpreter resolution: the stock chain stops at
# python3/python, which on Windows can both be broken Store stubs while `py` works.
# Each candidate is probed with a real import — PATH presence alone proves nothing.
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

run_mempalace_hook --hook precompact --harness claude-code
