; uitest.p8 - drives X16 Sheets' real code (app + bank libraries, built against this program's
; symbols) with typed input and toolbar buttons, saves/reloads XLSX and prints PASS/FAIL; DONE at the end.
%import app
%zeropage basicsafe

main {
    ubyte fails
    sub typ(uword r, ubyte c, str s) {
        app.select(r, c, false)
        ubyte i = 0
        while s[i] != 0 {
            if sview.editing
                app.edit_key(s[i])
            else
                app.nav_key(s[i])
            i++
        }
        app.edit_key(13)
    }
    sub sel(uword r1, ubyte c1, uword r2, ubyte c2) {
        app.select(r1, c1, false)
        app.select(r2, c2, true)
    }
    sub val(uword r, ubyte c, float want, str what) {
        cells.lookup(r, c)
        txt.print(what)
        txt.print(iso:" = ")
        if cells.lv_err != 0
            txt.print(formula.err_text(cells.lv_err))
        else
            floats.print(cells.lv)
        float d = cells.lv - want
        if cells.lv_err == 0 and abs(d) < 0.0001
            txt.print(iso:"  PASS\r")
        else {
            txt.print(iso:"  FAIL\r")
            fails++
        }
    }
    sub src(uword r, ubyte c, str want, str what) {
        ubyte n = sview.cell_source(r, c, &sview.ebuf)
        sview.ebuf[n] = 0
        txt.print(what)
        txt.print(iso:" = ")
        txt.print(&sview.ebuf)
        if strings.compare(&sview.ebuf, want) == 0
            txt.print(iso:"  PASS\r")
        else {
            txt.print(iso:"  FAIL\r")
            fails++
        }
    }
    sub sty(uword r, ubyte c, ubyte want, str what) {
        void cells.get(r, c)
        txt.print(what)
        txt.print(iso:" style ")
        txt.print_ub(cells.R[cells.R_STY])
        if cells.R[cells.R_STY] == want
            txt.print(iso:"  PASS\r")
        else {
            txt.print(iso:"  FAIL\r")
            fails++
        }
    }

    sub keys(str k) {
        ubyte i = 0
        while k[i] != 0 {
            cx16.kbdbuf_put(k[i])
            i++
        }
    }

    sub start() {
        if app.never
            app.keep()
        txt.iso()
        if not app.load_libs() {
            txt.print(iso:"DONE\r")
            return
        }
        vid.load_fonts()
        vid.gfx_init()
        shl.upload_icons()
        void app.themes(0)
        cells.init()
        sview.set_filename(iso:"untitled.xlsx")
        sview.redraw_everything()
        typ(1, 0, iso:"Item")
        typ(1, 1, iso:"Cost")
        typ(1, 2, iso:"Qty")
        typ(1, 3, iso:"Total")
        typ(2, 0, iso:"Paper")
        typ(2, 1, iso:"2.5")
        typ(2, 2, iso:"10")
        typ(2, 3, iso:"=b2*c2")
        typ(3, 0, iso:"Ink")
        typ(3, 1, iso:"$12.99")
        typ(3, 2, iso:"2")
        typ(4, 0, iso:"Stamps \xe9\xa4")
        typ(4, 1, iso:"0.68")
        typ(4, 2, iso:"50")
        ; copy D2, paste into D3:D4 (fill down, references follow)
        app.select(2, 3, false)
        app.do_button(sview.B_COPY)
        sel(3, 3, 4, 3)
        app.do_button(sview.B_PASTE)
        src(4, 3, iso:"=B4*C4", iso:"filled D4")
        val(4, 3, 34.0, iso:"D4")
        ; AutoSum under D2:D4
        sel(2, 3, 4, 3)
        app.do_button(sview.B_SUM)
        src(5, 3, iso:"=SUM(D2:D4)", iso:"autosum D5")
        val(5, 3, 84.98, iso:"D5")
        typ(2, 4, iso:"=d2/d$5")
        app.select(2, 4, false)
        app.do_button(sview.B_COPY)
        sel(3, 4, 4, 4)
        app.do_button(sview.B_PASTE)
        sel(2, 4, 4, 4)
        app.do_button(sview.B_PCT)
        src(4, 4, iso:"=D4/D$5", iso:"E4")
        ; formats
        sel(1, 0, 1, 4)
        app.do_button(sview.B_BOLD)
        app.do_button(sview.B_AC)
        sty(1, 1, 1 + 4, iso:"B1 bold+center")
        sty(3, 1, 24, iso:"B3 currency from $ input")
        sty(3, 4, 16, iso:"E3 percent")
        ; percent input, function menu style entry
        typ(7, 0, iso:"=ROUND(AVERAGE(B2:B4),1)")
        val(7, 0, 5.4, iso:"A7")
        typ(8, 0, iso:"=IF(D5>50,1,0)+COUNT(A1:E5)")
        val(8, 0, 14.0, iso:"A8")
        typ(9, 1, iso:"Caf\xe9 \xa4")
        typ(9, 2, iso:"=B6+$A$2")
        ; insert a row above row 3: formulas follow
        app.select(3, 0, false)
        app.do_button(sview.B_INSROW)
        src(6, 3, iso:"=SUM(D2:D5)", iso:"D6 after insert")
        src(5, 3, iso:"=B5*C5", iso:"D5 after insert")
        val(6, 3, 84.98, iso:"D6")
        typ(3, 0, iso:"Pens")
        typ(3, 1, iso:"1.5")
        typ(3, 2, iso:"4")
        app.select(2, 3, false)
        app.do_button(sview.B_COPY)
        app.select(3, 3, false)
        app.do_button(sview.B_PASTE)
        val(6, 3, 90.98, iso:"D6 with new row")
        ; delete column A: everything moves left
        app.select(1, 0, false)
        app.do_button(sview.B_DELCOL)
        src(6, 2, iso:"=SUM(C2:C5)", iso:"C6 after delete col")
        src(10, 1, iso:"=A7+#REF!", iso:"B10 lost $A$2")
        ; widths
        app.select(1, 1, false)
        app.do_button(sview.B_WIDER)
        app.do_button(sview.B_WIDER)
        ; save, wipe, reload
        if shl.xlsx_save(iso:"UITEST.XLSX")
            txt.print(iso:"save PASS\r")
        else {
            txt.print(iso:"save FAIL\r")
            fails++
        }
        cells.clear_all()
        ubyte st = shl.xlsx_load(iso:"UITEST.XLSX")
        txt.print(iso:"load status ")
        txt.print_ub(st)
        txt.nl()
        if st != 0
            fails++
        app.reset_view()
        app.changed()
        val(6, 2, 90.98, iso:"reloaded C6")
        src(5, 2, iso:"=A5*B5", iso:"reloaded C5")
        src(5, 3, iso:"=C5/C$6", iso:"reloaded D5")
        sty(5, 3, 16, iso:"reloaded D5 style")
        src(10, 0, iso:"Caf\xe9 \xa4", iso:"reloaded A10 latin")
        txt.print(iso:"colw B ")
        txt.print_ub(cells.colw[1])
        txt.nl()
        ; Save As on the SD card through the real dialog (keys pushed into the keyboard buffer)
        sview.modified = true
        sview.set_filename(iso:"C")
        keys(iso:"\x14COPY2\r")
        shl.save_sheet(1)
        txt.print(iso:"save as -> ")
        txt.print(sview.filename)
        if strings.compare(sview.filename, iso:"COPY2.xlsx") == 0 and not sview.modified
            txt.print(iso:"  PASS\r")
        else {
            txt.print(iso:"  FAIL\r")
            fails++
        }
        ; New (discard? yes), then Open from the SD picker: COPY2.xlsx is first in the list
        sview.modified = true
        keys(iso:"y")
        shl.new_sheet()
        val(6, 2, 0.0, iso:"after New C6")
        keys(iso:"\r")
        shl.open_sheet()
        txt.print(iso:"opened ")
        txt.print(sview.filename)
        txt.nl()
        val(6, 2, 90.98, iso:"picker-opened C6")
        ; Save As with folders: F7 = new folder SUBDIR (the only folder: row 0), Up + Enter opens it,
        ; replace the name, Enter. The sheet then lives in /SUBDIR (the DOS current directory)
        sview.modified = true
        sview.keyscript = iso:"\x88SUBDIR\r\x91\r\x14\x14\x14\x14\x14\x14\x14\x14\x14\x14\x14INSUB\r"
        shl.save_sheet(1)
        txt.print(iso:"save as in a new folder -> ")
        txt.print(sview.filename)
        txt.print(iso:" in ")
        txt.print(diskio.curdir())
        if strings.compare(sview.filename, iso:"INSUB.xlsx") == 0 and not sview.modified and strings.compare(diskio.curdir(), iso:"/SUBDIR") == 0
            txt.print(iso:"  PASS\r")
        else {
            txt.print(iso:"  FAIL\r")
            fails++
        }
        diskio.chdir(iso:"/")
        app.select(2, 0, false)
        app.select(6, 3, true)
        sview.redraw_everything()
        if fails == 0
            txt.print(iso:"ALL PASS\r")
        else {
            txt.print_ub(fails)
            txt.print(iso:" FAILED\r")
        }
        repeat 120
            sys.waitvsync()
        txt.print(iso:"DONE\r")
        repeat {
        }
    }
}
