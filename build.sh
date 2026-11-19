#!/usr/bin/env bash
# Build X16 Sheets. Works from a fresh clone:
#   build/x16sheets.prg                  main program
#   build/shui.bin shops.bin shfile.bin shxw.bin shxr.bin   bank libraries (need mainsyms_<bank>.p8,
#                                        generated from the main build by tools/gen_syms.py)
#   build/shth.bin                       theme loader (bank 56 at $AA00, loaded when needed)
#   build/x16link.bin x16docs.bin        X16Link libraries (sources vendored in lib/x16link)
#   build/X16THEME1.BIN .. X16THEME6.BIN  the X16 Office themes (tools/mkthemes.py, shared by the apps)
# With an SD dir argument, copies them there as X16SHEETS.PRG, SHUI.BIN, ... X16LINK.BIN, X16DOCS.BIN,
# X16THEME1.BIN ...
# Env: PROG8C = Prog8 12.3.x compiler command (default: java -jar ~/prog8c.jar), BUILD = output dir.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${X16LINK_LIB:-$HERE/lib/x16link}"
B="${BUILD:-$HERE/build}"
mkdir -p "$B"
P8="${PROG8C:-java -jar $HOME/prog8c.jar} -target cx16 -srcdirs $LIB -srcdirs $HERE"
run() { local log="$1"; shift; "$@" > "$log" 2>&1 || { cat "$log"; exit 1; }; grep -E "^Data:|BSS_SLABS" "$log" | sed "s|^|  $(basename "$log" .log): |" || true; }
python3 "$HERE/tools/gen_icons.py" > /dev/null
run "$B/x16link.log" $P8 -out "$B" "$LIB/x16link.p8"
run "$B/x16docs.log" $P8 -out "$B" "$LIB/x16docs.p8"
run "$B/x16sheets.log" $P8 -out "$B" "$HERE/x16sheets.p8"
for lb in shui:63 shops:57 shfile:62 shxw:59 shxr:58 shsa:55; do
  name="${lb%%:*}"; bank="${lb##*:}"
  python3 "$HERE/tools/gen_syms.py" "$B" "$bank" "$B/mainsyms_$bank.p8" > /dev/null
  run "$B/$name.log" $P8 -srcdirs "$B" -out "$B" "$HERE/$name.p8"
done
run "$B/shth.log" $P8 -out "$B" "$HERE/shth.p8"          # theme loader (no bank symbols needed)
python3 "$HERE/tools/mkthemes.py" "$B" > /dev/null     # X16THEME1.BIN .. (shared by the X16 Office apps)
if [ $# -ge 1 ]; then
  SD="$1"; mkdir -p "$SD"
  cp "$B/x16sheets.prg" "$SD/X16SHEETS.PRG"
  for f in shui shops shfile shxw shxr shsa shth x16link x16docs; do cp "$B/$f.bin" "$SD/$(echo $f | tr a-z A-Z).BIN"; done
  cp "$B"/X16THEME*.BIN "$SD/"
  echo "copied to $SD"
fi
