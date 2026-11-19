; themetest.p8 - themes, headless (test/run_themetest.sh): X16 Sheets' real code (app + bank libraries
; built against this program's symbols, SHTH.BIN, X16THEME1..6.BIN). Reads X16THEME.CFG and the theme
; files the way X16 Sheets does at start (app.themes(0)), then clicks Quill (app.press on row 29) through
; all six themes and back to the first. Screenshots go into snap.gif: first the built-in colours, then
; for every theme the sheet, the Save As browser and a warning dialog over a cell being edited.
; Prints PASS/FAIL lines and DONE.
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

    sub check(bool ok, str what) {
        if ok
            txt.print(iso:"PASS ")
        else {
            txt.print(iso:"FAIL ")
            fails++
        }
        txt.print(what)
        txt.nl()
    }

    sub frame() {
        repeat 30 {
            sys.waitvsync()
            theme.tick()
        }
        @($9fb5) = 1                    ; x16emu: one frame into snap.gif
        sys.wait(4)
    }

    ; the sheet with a selection (Sum / Count on the status bar)
    sub sheet() {
        app.select(2, 1, false)
        app.select(5, 1, true)
        sview.set_status(theme.msg)
        sview.redraw_everything()
        frame()
    }

    ; the sheet, then the Save As browser (cancelled by a scripted Esc; it stays on screen) and a
    ; cell being edited under a warning (answered "n")
    sub shots() {
        sheet()
        sview.keyscript = iso:"\x1b"
        void shl.sa_browse(0)
        frame()
        sview.redraw_everything()
        app.select(7, 2, false)
        app.start_edit(iso:"=SUM(C2:C5", false)
        sview.keyscript = iso:"n"
        void shl.yesno(shl.M_QUIT)
        frame()
        app.cancel_edit()
        sview.keyscript = 0
    }

    ubyte[64] builtin
    ubyte[6] seen

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
        void diskio.delete(iso:"X16THEME.CFG")
        sys.memcopy(&theme.rl, &builtin, 64)
        cells.init()
        sview.set_filename(iso:"budget.xlsx")
        typ(1, 0, iso:"Item")
        typ(1, 1, iso:"Cost")
        typ(1, 2, iso:"Qty")
        typ(1, 3, iso:"Total")
        typ(2, 0, iso:"Paper")
        typ(2, 1, iso:"2.5")
        typ(2, 2, iso:"10")
        typ(2, 3, iso:"=B2*C2")
        typ(3, 0, iso:"Pens")
        typ(3, 1, iso:"1.25")
        typ(3, 2, iso:"8")
        typ(3, 3, iso:"=B3*C3")
        typ(4, 0, iso:"Stamps")
        typ(4, 1, iso:"0.6")
        typ(4, 2, iso:"20")
        typ(4, 3, iso:"=B4*C4")
        typ(5, 0, iso:"Ink")
        typ(5, 1, iso:"7")
        typ(5, 2, iso:"1")
        typ(5, 3, iso:"=B5*C5")
        typ(7, 0, iso:"Sum")
        typ(7, 3, iso:"=SUM(D2:D5)")
        typ(8, 0, iso:"Error")
        typ(8, 3, iso:"=1/0")
        sview.modified = true
        sview.cloud_doc = true

        ; frame 1: the built-in colours (no theme read yet, Quill hidden). x16emu's GIF writer
        ; quantizes the colours of the first frame, so it is taken twice (the second one is exact)
        sheet()
        sheet()

        check(app.themes(0) and theme.cur == 1, iso:"no X16THEME.CFG: theme 1")
        bool same = true
        ubyte i
        for i in 0 to 63 {
            if theme.rl[i] != builtin[i]
                same = false
        }
        check(same, iso:"theme 1 (Sunset Arcade) = the built-in roles")
        check(theme.msg[7] == iso:'S' and theme.msg[14] == iso:'A', iso:"its name for the status bar")
        app.last_tip = 0
        app.hover(0, 29)
        check(sview.status_msg[0] == iso:'C' and sview.status_msg[6] == iso:'Q', iso:"Quill's tool tip")
        app.hover(40, 15)
        seen[0] = theme.rl[theme.R_DESK]
        shots()
        for i in 2 to 6 {
            app.press(0, 29)            ; click Quill
            check(theme.cur == i and theme.hop != 0, iso:"Quill: next theme")
            seen[i - 1] = theme.rl[theme.R_DESK]
            shots()
        }
        check(theme.dk[26] == $15 and theme.dk[0] == $91, iso:"the desk pattern (Winter Cabin)")
        check(seen[1] == vid.C_ORANGE and seen[2] == vid.C_LGRAY and seen[4] == vid.C_DGRAY, iso:"each theme's desk colour")
        app.press(0, 29)
        check(theme.cur == 1, iso:"after the last theme the first again")
        ; restart: the saved choice
        void app.themes(1)
        void app.themes(1)
        theme.cur = 0
        theme.rl[theme.R_DESK] = 99
        check(app.themes(0) and theme.cur == 3 and theme.rl[theme.R_DESK] == vid.C_LGRAY, iso:"X16THEME.CFG brings back theme 3 (Comic Book)")
        check(theme.msg[7] == iso:'C' and theme.msg[13] == iso:'B', iso:"its name for the status bar")

        if fails == 0
            txt.print(iso:"ALL PASS\r")
        else
            txt.print(iso:"SOME FAILED\r")
        txt.print(iso:"DONE\r")
    }
}
