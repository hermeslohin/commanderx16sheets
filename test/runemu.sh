#!/usr/bin/env bash
# runemu.sh <prg> <outfile> [timeout-s] [extra emu args...]: run a test PRG headless in x16emu (warp, -echo),
# stop when "DONE" is printed. Runs in the PRG's directory (host FS = SD card).
NOWARP="${NOWARP--warp}"; PRG="$1"; OUT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; T="${3:-120}"; shift 3 || true
cd "$(dirname "$PRG")"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy /usr/local/x16emu/x16emu -sound none $NOWARP -echo iso -prg "$(basename "$PRG")" -run "$@" > "$OUT" 2>&1 &
EMU=$!
for _ in $(seq $((T*5))); do grep -aq "DONE" "$OUT" 2>/dev/null && break; kill -0 $EMU 2>/dev/null || break; sleep 0.2; done
sleep 0.3; kill $EMU 2>/dev/null; wait $EMU 2>/dev/null
tr '\r' '\n' < "$OUT" | tr -d '\000' > "$OUT.txt"
