; X16 SHEETS - a mouse driven spreadsheet for the Commander X16, written in Prog8.
; Main RAM: the cell store (cells.p8, data in banked RAM), formulas (formula.p8), the grid (sview.p8),
; editing and the mouse/keyboard loop (app.p8). The rest is in bank libraries loaded at start:
; SHUI.BIN (toolbars, dialogs), SHOPS.BIN (editing operations), SHFILE.BIN (files, ownCloud),
; SHXW.BIN / SHXR.BIN (XLSX writer / reader). See README.md and shlibs.p8.

%import app
%zeropage basicsafe

main {
    sub start() {
        app.run()
    }
}
