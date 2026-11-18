#!/usr/bin/env bash
# X16 Sheets <-> hub <-> (in-memory) ownCloud, end to end in the emulator. Needs the x16-office-hub
# checkout (HUB=..., default ../x16-office-hub/hub) and a Python with its requirements (HUBPY=...).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HUB="${HUB:-$HERE/../x16-office-hub/hub}"
HUBPY="${HUBPY:-python3}"
B="${BUILD:-$HERE/build/cloudtest}"
rm -rf "$B/sd" "$B/out"; mkdir -p "$B/sd" "$B/out" "$B/ximodem"
P8="${PROG8C:-java -jar $HOME/prog8c.jar} -target cx16 -srcdirs $HERE/lib/x16link -srcdirs $HERE"
$P8 -out "$B" "$HERE/test/cloudtest.p8" > "$B/cloudtest.log" 2>&1 || { cat "$B/cloudtest.log"; exit 1; }
for lb in shui:63 shops:57 shfile:62 shxw:59 shxr:58; do
  name="${lb%%:*}"; bank="${lb##*:}"
  python3 "$HERE/tools/gen_syms.py" "$B" "$bank" "$B/mainsyms_$bank.p8" cloudtest > /dev/null
  $P8 -srcdirs "$B" -out "$B" "$HERE/$name.p8" > "$B/$name.log" 2>&1 || { cat "$B/$name.log"; exit 1; }
  cp "$B/$name.bin" "$B/sd/$(echo $name | tr a-z A-Z).BIN"
done
$P8 -out "$B" "$HERE/lib/x16link/x16link.p8" > /dev/null 2>&1
$P8 -out "$B" "$HERE/lib/x16link/x16docs.p8" > /dev/null 2>&1
cp "$B/x16link.bin" "$B/sd/X16LINK.BIN"; cp "$B/x16docs.bin" "$B/sd/X16DOCS.BIN"
cp "$B/cloudtest.prg" "$B/sd/CLOUDTEST.PRG"
"$HUBPY" "$HERE/test/fakehub.py" "$HUB" "$B/sd" "$B/out" 6502 > "$B/hub.log" 2>&1 &
HUBPID=$!
for _ in $(seq 50); do grep -q "hub up" "$B/hub.log" 2>/dev/null && break; sleep 0.2; done
"$HERE/test/runemu.sh" "$B/sd/CLOUDTEST.PRG" "$B/cloudtest.out" 300 -uart1 "ximodem:$B/ximodem" || true
touch "$B/out/STOP"; wait $HUBPID || cat "$B/hub.log"
grep -a -E "PASS|FAIL|status|DONE|missing" "$B/cloudtest.out.txt"
"$HUBPY" - "$HUB" "$B/out" <<'PY'
import sys, zipfile, io
sys.path.insert(0, sys.argv[1])
from pathlib import Path
from x16hub.link.sheetconv import read_sheet
o = Path(sys.argv[2]); bad = 0
def chk(c, what):
    global bad
    print(("PASS " if c else "FAIL ") + what); bad += 0 if c else 1
z = zipfile.ZipFile(io.BytesIO((o / "A-budget.xlsx").read_bytes()))
chk(all(i.compress_type == zipfile.ZIP_DEFLATED for i in z.infolist()), "A-budget.xlsx stored deflated (a normal xlsx)")
sh, _ = read_sheet((o / "A-budget.xlsx").read_bytes())
chk(sh.cells[(3, 2)].v == 1400 and sh.cells[(4, 2)].f == "SUM(B2:B3)" and abs(sh.cells[(4, 2)].v - 2600.5) < 1e-6, "A-budget.xlsx has the edit and the formula")
chk(sh.cells[(4, 1)].v == "Café €", "A-budget.xlsx text round trip")
out = (o / "OUT.csv").read_text("utf-8")
print(repr(out)); chk("1400" in out and "2600.5" in out and "Café €" in out, "OUT.csv values (UTF-8)")
chk((o / "B-data.csv").read_text("utf-8") == out, "B-data.csv overwritten after the conflict")
sys.exit(1 if bad else 0)
PY
