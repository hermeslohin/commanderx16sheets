#!/usr/bin/env bash
# Themes, headless: themetest.prg + the bank libraries (built against its symbols) + SHTH.BIN +
# X16THEME1..6.BIN in x16emu on the host file system. Checks the PASS lines and writes screenshots:
#   build/themetest/theme-0.png         the built-in colours (no theme file read)
#   build/themetest/theme-<n>.png       the sheet in theme n (1 Sunset Arcade .. 6 Winter Cabin)
#   build/themetest/theme-<n>-saveas.png, theme-<n>-dialog.png   the Save As browser, a warning
# (the GIF's first frame, gif-first-frame.png, is the built-in colours again, quantized by x16emu)
# Env: PROG8C (default java -jar ~/prog8c.jar), EMU (default /usr/local/x16emu/x16emu), PY (a python3
# with Pillow to split the screenshots; without it only the first one).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
B="${BUILD:-$HERE/build/themetest}"
EMU="${EMU:-/usr/local/x16emu/x16emu}"
rm -rf "$B"; mkdir -p "$B/sd"
P8="${PROG8C:-java -jar $HOME/prog8c.jar} -target cx16 -srcdirs $HERE/lib/x16link -srcdirs $HERE"
$P8 -out "$B" "$HERE/test/themetest.p8" > "$B/themetest.log" 2>&1 || { cat "$B/themetest.log"; exit 1; }
for lb in shui:63 shops:57 shfile:62 shxw:59 shxr:58 shsa:55; do
  name="${lb%%:*}"; bank="${lb##*:}"
  python3 "$HERE/tools/gen_syms.py" "$B" "$bank" "$B/mainsyms_$bank.p8" themetest > /dev/null
  $P8 -srcdirs "$B" -out "$B" "$HERE/$name.p8" > "$B/$name.log" 2>&1 || { cat "$B/$name.log"; exit 1; }
  cp "$B/$name.bin" "$B/sd/$(echo $name | tr a-z A-Z).BIN"
done
$P8 -out "$B" "$HERE/shth.p8" > "$B/shth.log" 2>&1 || { cat "$B/shth.log"; exit 1; }
cp "$B/shth.bin" "$B/sd/SHTH.BIN"
cp "$B/themetest.prg" "$B/sd/THEMETEST.PRG"
python3 "$HERE/tools/mkthemes.py" "$B/sd" > /dev/null
cd "$B/sd"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$EMU" -sound none -echo iso -gif ../snap.gif,wait \
  -prg THEMETEST.PRG -run > ../out.txt 2>&1 &
P=$!
for _ in $(seq 600); do grep -aq "DONE" ../out.txt 2>/dev/null && break; kill -0 $P 2>/dev/null || break; sleep 0.2; done
sleep 0.5; kill $P 2>/dev/null; wait $P 2>/dev/null || true
cd "$B"
tr '\r' '\n' < out.txt | tr -d '\000' | grep -a -E "PASS|FAIL|DONE|missing" || tail -20 out.txt
ok=1
grep -aq "ALL PASS" out.txt || ok=0
if [ -f snap.gif ]; then
  # one PNG per frame (sips only converts the first)
  "${PY:-python3}" - <<'PY' 2>/dev/null || sips -s format png snap.gif --out theme-0.png > /dev/null 2>&1
from PIL import Image
im = Image.open("snap.gif")
names = ["gif-first-frame", "theme-0"] + [f"theme-{n}{s}" for n in range(1, 7) for s in ("", "-saveas", "-dialog")]
i = 0
while True:
    im.convert("RGB").save((names[i] if i < len(names) else f"extra-{i}") + ".png")
    i += 1
    try:
        im.seek(im.tell() + 1)
    except EOFError:
        break
PY
  echo "screenshots: $B/theme-*.png"
fi
[ $ok = 1 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; exit 1; }
