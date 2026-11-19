# X16 Sheets - a mouse-driven spreadsheet for the Commander X16 (Prog8)

A companion to [X16 Write](../commanderx16wp): same look, same icons, same ownCloud link through
the X16 Office hub. Sheets are saved as real `.xlsx` files, on the SD card or in ownCloud.

Build: `make` (needs Prog8 12.3.x as `~/prog8c.jar` or `PROG8C=...`, 64tass, Java 11+).
Everything lands in `build/`. `make sd SD=<dir>` copies what goes on the SD card:

| File | What |
|---|---|
| `X16SHEETS.PRG` | the program (main RAM) |
| `SHUI.BIN` `SHOPS.BIN` `SHFILE.BIN` `SHXW.BIN` `SHXR.BIN` `SHSA.BIN` | its code libraries (RAM banks 63, 57, 62, 59, 58, 55) - required |
| `X16LINK.BIN` `X16DOCS.BIN` | X16Link libraries (banks 60/61) - only for ownCloud |
| `SHTH.BIN` `X16THEME1.BIN` .. `X16THEME6.BIN` | the theme loader and the X16 Office themes - optional (without them: the built-in Sunset Arcade colours, no Quill) |
| `X16THEME.CFG` | written when you pick a theme (one byte, the theme number) |
| `X16LINK.KEY` | this X16's hub key - only for ownCloud (same file X16 Write uses) |

Run: `make run`. Needs a mouse and 512 KB of RAM (2 MB gives more cells).

## Screen

Row 0 title/quit - rows 1-2 icon toolbars - row 3 formula bar - column letters - 23 rows of grid
with grid lines - horizontal scroll bar - status bar (tool tips on hover; Sum and Count of the
selection, like a desktop spreadsheet).

Colours: the X16 Office themes (`theme.p8` and `tools/mkthemes.py`, the same files in X16 Write,
Files and Calendar). Six theme files come with it: Sunset Arcade (the default: striped title bar with
black chips, violet toolbars with coloured icon faces, cream cells with lavender grid lines, black
status bar), Crayon Desk, Comic Book, Beach Hut, Chalkboard and Winter Cabin. Quill, a little pencil
(a sprite) at the left end of the status bar, blinks and hops after a successful open or save.
**Click Quill for the next theme** (hover over it for the tip). The choice is saved in
`X16THEME.CFG`, which every X16 Office app reads at start, so a theme picked in one app is used by
all of them. A theme changes only the screen: colour indexes keep their meaning (the selection is
still pink-red, errors red), and saved `.xlsx` files carry no colours from it. Without `SHTH.BIN`
and the `X16THEME*.BIN` files X16 Sheets uses the built-in Sunset Arcade colours, without Quill.

Toolbar 1: New, Open, Save, Save As | Cut, Copy, Paste, Select All | Clear | Bold | Align left,
Center, Align right (the X16 Write icons). Toolbar 2: AutoSum, Insert function | Number format
General, 0.00, Percent, Currency | Insert rows, Delete rows, Insert columns, Delete columns |
Narrower, Wider. Formula bar: cell name, Cancel (X), Enter (tick), Insert function (fx), contents.

## Using it

* **Click** a cell to select it, **drag** to select a range, click a column letter / row number to
  select columns / rows, click the corner for everything. Scroll with the wheel or the scroll bars.
* **Type** to replace a cell, **double-click** (or F2, or click the formula bar) to edit it.
  Return = enter and move down, Tab = enter and move right, Esc = cancel, arrows move.
  Delete / Backspace clear the selection (formats stay); the Clear icon removes formats too.
* Numbers: `12`, `-3.5`, `1e6`, `$1,234.50` (sets Currency), `12%` (0.12, sets Percent). A leading
  `'` makes anything text.
* **Formulas** start with `=`. While typing one, **click or drag over cells** to insert `B2` or
  `B2:D9` (Excel-style pointing). Missing `)` are added for you.
  * Operators: `+ - * / ^ %`, comparisons `= <> < > <= >=` (give 1 or 0), parentheses.
  * Functions: `SUM AVERAGE MIN MAX COUNT PRODUCT ABS SQRT INT ROUND IF` (fx menu).
    Difference is plain subtraction: `=B2-C2`.
  * References: `A1`, `$A$1`, `A$1`, ranges `A1:C9`; errors `#DIV/0! #VALUE! #REF! #NAME? #NUM!`.
* **AutoSum**: on a range, puts a SUM under each column (or right of a row); on a cell, proposes
  the numbers above (or to the left) - press Return to accept, or drag a different range.
* **Copy / Paste** adjust relative references (`$` keeps them). Copy one cell, select a range,
  Paste = fill down / right. Cut + Paste moves without changing references.
* **Insert / delete rows and columns** (as many as are selected): formulas everywhere follow,
  references into deleted cells become `#REF!`, ranges shrink.
* **Column width**: drag the right edge of a column letter, or the Narrower / Wider icons.

## Files

* **Open / Save As** ask first: **1** = SD card, **2** = ownCloud (the menu only appears when the
  X16Link files are on the SD card). The SD card Open shows a picker of `*.xlsx` in the current
  directory (double-click or Enter).
* **Save As** (SD card and ownCloud) is a folder browser: double-click a folder (or arrows + Enter)
  to open it, `..` / [ Up ] to go up, [New folder] or **F7** to make one, click a file to take its
  name, type a name, Enter. On the SD card opening a folder changes the DOS current directory, so the
  sheet (and the SD Open picker) then work there; an existing file is replaced only after a question.
  On ownCloud it shows one folder of `Documents/` at a time. `X16LINK.KEY` is always read from the
  program's own folder. (SHSA.BIN, the same dialog as X16 Write's.)
* Files are `.xlsx`: stored (uncompressed) ZIP, one worksheet, inline strings, 32 fixed styles -
  see [SHEETFMT.md](SHEETFMT.md). Excel, LibreOffice and ownCloud open them as they are.
  `.xlsx` files written by other programs are compressed: open those **through ownCloud**, where
  the hub converts them (an X16 can't inflate them itself; the SD Open says so).
* **ownCloud**: Open lists the hub account's `Documents/`; `.xlsx` and `.csv` can be opened (other
  types are greyed). The hub converts any xlsx (shared strings, other styles, shared formulas,
  booleans) or csv into the simple form. **Save** writes back to the file it came from, only if
  nobody changed it meanwhile; **Save As** asks for a name - `.xlsx` (stored as a normal, compressed
  xlsx) or `.csv` (values, UTF-8). Conflicts ask Overwrite / New name / Cancel, as in X16 Write.
  Setup is the same as X16 Write's (hub running, `X16LINK.KEY` on the SD card, ESP32 modem).

## Memory (high RAM)

The cells live in banked RAM, so main RAM only holds code:

| RAM banks | |
|---|---|
| 1-4 | hash index (16384 slots) |
| 5-54 | cell records, 64 bytes each: **6400 cells** on a 512 KB X16 |
| 64-255 | more records on bigger machines, up to **12288 cells** (2 MB) |
| 56 | used-row bitmap (saving), SD file names (picker); theme file + SHTH.BIN while a theme is read |
| 55, 57-59, 62, 63 | X16 Sheets code libraries (55 = SHSA.BIN, the Save As browser) |
| 60, 61 | X16Link libraries |

Sheet size: columns A-IV (256), rows 1-9999. Texts up to 50 characters, formulas up to 46.
Clipboard cells use free records too.

Recalculation is incremental: each formula keeps the box of cells it refers to, so after an edit only
the formulas that depend on it are evaluated again (until nothing changes; 25 rounds = circular
reference, reported in the status bar). Opening a file recalculates everything once.

## Code

| File | |
|---|---|
| `x16sheets.p8`, `app.p8` | start-up (loads the libraries), mouse/keyboard loop, editing, selection |
| `sview.p8` | grid, headers, formula bar, status bar, scroll bars |
| `cells.p8` | the banked cell store (hash + records, clipboard) |
| `formula.p8` | evaluator (iterative shunting-yard), reference rewriting, recalculation |
| `numfmt.p8` | number display formats |
| `vid.p8` | X16 Write's 80x30 bitmap text renderer + grid lines |
| `theme.p8` | X16 Office themes: role table (which colour each part of the screen uses, built-in = Sunset Arcade), title fill, pills, Quill; reads `X16THEME<n>.BIN` / `X16THEME.CFG` (shared with the other X16 Office apps: keep identical) |
| `shth.p8` | `SHTH.BIN`: runs theme.p8's file reading (`theme.init` / `theme.next`) from bank 56, so main RAM keeps only the drawing (like X16 Write's `X16WPTH.BIN`) |
| `shui.p8` `shops.p8` `shfile.p8` `shxw.p8` `shxr.p8` `shsa.p8` | the bank libraries (see `shlibs.p8`) |
| `tools/gen_syms.py` | generates each library's view of the main program (like X16 Write's `gen_wpsyms.py`) |
| `tools/gen_icons.py` | toolbar icons (the first 13 are X16 Write's) |
| `tools/mkthemes.py` | writes `X16THEME1.BIN` .. `X16THEME6.BIN` (shared with the other X16 Office apps: keep identical) |
| `lib/x16link/` | vendored X16Link client library (from x16-office-hub) |

## Tests

* `make test`: `test/ftest.p8` (formula engine, 48 checks) and `test/run_uitest.sh` (drives the real
  app + libraries: typing, fill, AutoSum, formats, insert/delete rows and columns, Save As / New /
  Open through the dialogs, XLSX round trip) headless in x16emu, and `test/run_themetest.sh`.
* `make themetest` (`test/run_themetest.sh`): reads the themes the way X16 Sheets does at start
  (no `X16THEME.CFG` = theme 1, which must equal the built-in colours), clicks Quill through all six
  and back to the first, and checks that `X16THEME.CFG` brings the chosen theme back. Screenshots:
  `build/themetest/theme-0.png` (built-in), `theme-1.png` .. `theme-6.png`, plus each theme's Save As
  browser and a warning dialog (`PY=` a python3 with Pillow splits the GIF).
* `make cloudtest` (`test/run_cloudtest.sh`): the whole ownCloud path in the emulator
  (`-uart1 ximodem`) against the real hub link server with an in-memory ownCloud
  (`test/fakehub.py`, needs `../x16-office-hub`): opens a desktop-style xlsx, saves back, Save As
  CSV, a save conflict, reopens the CSV, and checks what landed in "ownCloud".
* `test/perftest.p8`: recalculation timing on a 3000-cell sheet.

## Limits

* One worksheet per file; no charts, merged cells, dates (they arrive as numbers or text), text
  functions or cross-sheet references. No undo.
* Formatted empty cells are kept on the SD card, but the hub drops them when it converts.

## License

Copyright (C) 2026 hermeslohin

X16 Sheets is free software: you can redistribute it and/or modify it under the terms of the GNU General
Public License as published by the Free Software Foundation, either version 3 of the License, or (at
your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See [LICENSE](LICENSE) for the full text of the GNU General Public License v3.
