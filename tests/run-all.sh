#!/bin/bash
# run-all.sh — run every continuity-layer test. Exit code = number of failing suites.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOTAL=0
for t in lifecycle-test.sh retention-test.sh; do
    echo "=== $t ==="
    bash "$HERE/$t"
    rc=$?
    [ "$rc" -ne 0 ] && TOTAL=$((TOTAL+1))
    echo
done
if [ "$TOTAL" -eq 0 ]; then echo "== ALL SUITES PASSED =="; else echo "== $TOTAL SUITE(S) FAILED =="; fi
exit "$TOTAL"
