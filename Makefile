# X16 Sheets - build with Prog8 12.3.x (https://prog8.readthedocs.io) + 64tass + Java 11+.
# PROG8C = compiler command (default: the jar in your home dir). Output goes to build/.
# `make sd SD=/path/to/sdcard` also copies the files there.
PROG8C ?= java -jar $(HOME)/prog8c.jar
export PROG8C
EMU ?= x16emu

.PHONY: all sd run run-modem test cloudtest clean
all:
	./build.sh

sd:
	./build.sh $(SD)

run: all
	mkdir -p build/run && ./build.sh build/run > /dev/null
	cd build/run && $(EMU) -scale 2 -prg X16SHEETS.PRG -run

# same, with the emulator's virtual modem for ownCloud; copies the hub key in (KEY=path to override)
KEY ?= $(HOME)/Downloads/X16LINK.KEY
run-modem: all
	mkdir -p build/run && ./build.sh build/run > /dev/null
	@if [ -f "$(KEY)" ]; then cp "$(KEY)" build/run/X16LINK.KEY; \
	 elif [ ! -f build/run/X16LINK.KEY ]; then echo "warning: no X16LINK.KEY (set KEY=...)"; fi
	cd build/run && $(EMU) -scale 2 -uart1 ximodem -prg X16SHEETS.PRG -run

# formula engine (headless) + the whole UI (headless) ; `make cloudtest` needs ../x16-office-hub
test:
	java -jar $(HOME)/prog8c.jar -target cx16 -srcdirs . -out build/ftest test/ftest.p8 > /dev/null
	test/runemu.sh build/ftest/ftest.prg build/ftest/ftest.out 120 && grep -a -E "FAIL|ALL PASS" build/ftest/ftest.out.txt
	test/run_uitest.sh | grep -a -E "FAIL|ALL PASS"

cloudtest:
	test/run_cloudtest.sh

clean:
	rm -rf build
