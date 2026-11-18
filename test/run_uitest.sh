#!/usr/bin/env bash
# Build uitest.prg + the bank libraries against uitest's own symbols, run it headless, print results.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
B="${BUILD:-$HERE/build/uitest}"
mkdir -p "$B/sd"
P8="${PROG8C:-java -jar $HOME/prog8c.jar} -target cx16 -srcdirs $HERE/lib/x16link -srcdirs $HERE"
$P8 -out "$B" "$HERE/test/uitest.p8" > "$B/uitest.log" 2>&1 || { cat "$B/uitest.log"; exit 1; }
for lb in shui:63 shops:57 shfile:62 shxw:59 shxr:58; do
  name="${lb%%:*}"; bank="${lb##*:}"
  python3 "$HERE/tools/gen_syms.py" "$B" "$bank" "$B/mainsyms_$bank.p8" uitest > /dev/null
  $P8 -srcdirs "$B" -out "$B" "$HERE/$name.p8" > "$B/$name.log" 2>&1 || { cat "$B/$name.log"; exit 1; }
  cp "$B/$name.bin" "$B/sd/$(echo $name | tr a-z A-Z).BIN"
done
cp "$B/uitest.prg" "$B/sd/UITEST.PRG"
rm -f "$B/sd/UITEST.XLSX" "$B/shots.gif"
"$HERE/test/runemu.sh" "$B/sd/UITEST.PRG" "$B/uitest.out" 180 -gif "$B/shots.gif"
grep -a -E "PASS|FAIL|status|colw|missing|DONE" "$B/uitest.out.txt"
