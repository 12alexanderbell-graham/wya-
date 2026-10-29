#!/bin/bash
# usage: snapcmd.sh name wait_seconds "cmd1" "cmd2" ... -> runs commands in the app, waits, saves snaps/<name>.jpg
D="${WYA_SNAPS:-$(dirname "$0")/snaps}"; name=$1; w=$2; shift 2
{ echo "id-$(date +%s%N)"; for c in "$@"; do echo "$c"; done; } > "$D/cmd.txt"
sleep "$w"
for i in 1 2 3 4 5; do cp "$D/latest.jpg" "$D/$name.jpg" 2>/dev/null && break; sleep 0.1; done
echo saved $name
