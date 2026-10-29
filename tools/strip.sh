#!/bin/bash
# usage: strip.sh name WxH+X+Y [cols] -> strips/<name>.png from the last burst's frames, cropped, in reading order
D="$(dirname "${WYA_SNAPS:-$(dirname "$0")/snaps}")"; n=$(ls "$D/snaps" | grep -c '^b[0-9]*\.jpg$')
files=$(ls "$D/snaps" | grep '^b[0-9]*\.jpg$' | sort | head -n $(cut -d' ' -f1 "$D/snaps/burst.txt" | wc -l) | sed "s#^#$D/snaps/#; s#\$#[$2]#")
montage $files -tile ${3:-2}x -geometry +2+2 -background white "$D/strips/$1.png"
echo "$1: $(wc -l < "$D/snaps/burst.txt") frames"
