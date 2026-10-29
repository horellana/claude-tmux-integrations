#!/bin/sh
# Run every tests/test_*.sh; exit non-zero if any fails.
dir=$(cd "$(dirname "$0")" && pwd)
status=0
for f in "$dir"/test_*.sh; do
    [ -e "$f" ] || continue
    printf '== %s\n' "$(basename "$f")"
    sh "$f" || status=1
done
exit "$status"
