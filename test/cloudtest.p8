; cloudtest.p8 - X16 Sheets' ownCloud path end to end: the real app + bank libraries + X16Link
; libraries, through the emulator's virtual modem (-uart1 ximodem) to the real hub link server
; (test/fakehub.py, in-memory ownCloud). Dialog keys come from sview.keyscript. DONE at the end.
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
    sub ok(bool b, str what) {
        txt.print(what)
        if b
            txt.print(iso:"  PASS\r")
        else {
            txt.print(iso:"  FAIL\r")
            fails++
        }
    }
    sub val(uword r, ubyte c, float want, str what) {
        cells.lookup(r, c)
        floats.print(cells.lv)
        txt.print(iso:" ")
        float d = cells.lv - want
        ok(cells.lv_err == 0 and abs(d) < 0.0001, what)
    }
    sub src(uword r, ubyte c, str want, str what) {
        ubyte n = sview.cell_source(r, c, &sview.ebuf)
        sview.ebuf[n] = 0
        txt.print(&sview.ebuf)
        txt.print(iso:" ")
        ok(strings.compare(&sview.ebuf, want) == 0, what)
    }
    sub status() {
        txt.print(iso:"  status: ")
        txt.print(sview.status_msg)
        txt.nl()
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
        cells.init()
        sview.set_filename(iso:"untitled.xlsx")
        sview.redraw_everything()
        ok(app.cloud_ok, iso:"X16Link libraries loaded")
        ; open A-budget.xlsx (first entry) from ownCloud
        sview.keyscript = iso:"2\r"
        shl.open_sheet()
        status()
        txt.print(sview.filename)
        txt.print(iso:" ")
        ok(sview.cloud_doc and strings.compare(sview.filename, iso:"A-budget.xlsx") == 0, iso:"opened from ownCloud")
        src(1, 0, iso:"Month", iso:"A1")
        void cells.get(1, 0)
        ok(cells.R[cells.R_STY] == 1, iso:"A1 bold")
        val(2, 1, 1200.5, iso:"B2")
        void cells.get(2, 1)
        ok(cells.R[cells.R_STY] == 8, iso:"B2 0.00 format")
        src(4, 1, iso:"=SUM(B2:B3)", iso:"B4 formula")
        src(4, 0, iso:"Caf\xe9 \xa4", iso:"A4 shared string")
        ; edit and Save back (overwrite the version we opened)
        typ(3, 1, iso:"1400")
        val(4, 1, 2600.5, iso:"B4 recalculated")
        shl.save_sheet(0)
        status()
        ok(not sview.modified, iso:"saved back to ownCloud")
        ; Save As OUT.csv
        sview.keyscript = iso:"2\x14\x14\x14\x14\x14\x14\x14\x14\x14\x14\x14\x14\x14OUT.csv\r"
        shl.save_sheet(1)
        status()
        ok(strings.compare(sview.filename, iso:"OUT.csv") == 0, iso:"saved as OUT.csv")
        ; Save As over an existing file: conflict dialog -> Overwrite
        sview.keyscript = iso:"2\x14\x14\x14\x14\x14\x14\x14B-data.csv\ro"
        shl.save_sheet(1)
        status()
        ok(strings.compare(sview.filename, iso:"B-data.csv") == 0, iso:"conflict -> overwrite")
        ; open the CSV back (second entry): the hub converts it to XLSX for us
        sview.modified = false
        sview.keyscript = iso:"2\x11\r"
        shl.open_sheet()
        status()
        val(3, 1, 1400.0, iso:"CSV reopened B3")
        val(4, 1, 2600.5, iso:"CSV reopened B4 (value)")
        repeat 60
            sys.waitvsync()
        if fails == 0
            txt.print(iso:"ALL PASS\r")
        else {
            txt.print_ub(fails)
            txt.print(iso:" FAILED\r")
        }
        txt.print(iso:"DONE\r")
        repeat {
        }
    }
}
