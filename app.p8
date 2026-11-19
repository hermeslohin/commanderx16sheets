; app.p8 - X16 Sheets' main-RAM application: start-up (loading the bank libraries), the
; mouse/keyboard loop, cell editing, selection and scrolling. x16sheets.p8 just calls app.run().

%import syslib
%import diskio
%import textio
%import sview
%import cells
%import formula
%import shlibs
%import theme
%import x16link_api

app {
    bool running = true
    ubyte prev_btn
    ubyte drag_mode                 ; 0 none, 1 select, 2 point (formula), 3 column resize, 4 vscroll, 5 hscroll, 6 column headers, 7 row headers
    ubyte resize_col
    ubyte last_tip
    ubyte last_click_time
    uword last_click_r
    ubyte last_click_c
    ubyte scroll_timer
    ubyte pt_pos                    ; where the pointed-at reference starts in the edit buffer
    uword pt_ar                     ; point anchor
    ubyte pt_ac

    str @shared tmpname = iso:"X16SHEET.TMP"
    bool @shared cloud_ok
    bool @shared clip_cut
    bool @shared never
    str pcttxt = iso:"Transferring    %  "

    ; load the bank libraries; false (with a message on the text screen) if one is missing
    str[] libnames = [iso:"SHUI.BIN", iso:"SHOPS.BIN", iso:"SHFILE.BIN", iso:"SHXW.BIN", iso:"SHXR.BIN", iso:"SHSA.BIN"]
    ubyte[] libbanks = [shl.UI, shl.OPS, shl.FILE, shl.XW, shl.XR, shl.SA]
    sub load_libs() -> bool {
        ubyte i
        for i in 0 to 5 {
            cx16.rambank(libbanks[i])
            if diskio.load_raw(libnames[i], $a000) == 0 {
                txt.print(iso:"missing ")
                txt.print(libnames[i])
                txt.print(iso:" (copy all .BIN files next to X16SHEETS.PRG)\r")
                return false
            }
        }
        shl.ui_init()
        shl.ops_init()
        shl.file_init()
        shl.xw_init()
        shl.xr_init()
        shl.sa_init()
        uword chk = &vid.render_run
        if not (shl.ui_setup(chk) and shl.ops_setup(chk) and shl.file_setup(chk) and shl.xw_setup(chk) and shl.xr_setup(chk) and shl.sa_setup(chk)) {
            txt.print(iso:"the .BIN files don't match X16SHEETS.PRG\r")
            return false
        }
        ; ownCloud is optional: X16LINK.BIN + X16DOCS.BIN (+ X16LINK.KEY)
        if lkload.load() {
            lkapi.set_progress(&progress)
            cloud_ok = true
        }
        return true
    }

    ; what = 0: the saved theme (X16THEME.CFG), 1: the next one (Quill). SHTH.BIN reads the theme
    ; files (theme.init / theme.next, no room for them in main RAM); it is loaded each time into RAM
    ; bank 56 at $AA00 (the SD picker's names, idle then). false: no theme files (or no SHTH.BIN)
    sub themes(ubyte what) -> bool {
        ubyte b = cx16.getrambank()
        cx16.rambank(shl.TH)
        uword e = diskio.load_raw(iso:"SHTH.BIN", $aa00)
        cx16.rambank(b)
        if e == 0
            return false
        shl.th_init()
        return shl.th_run(&theme.rl, &theme.dk, &theme.msg, &theme.cur, what)
    }

    ; the bank libraries call these main-RAM routines; this (never taken) path keeps the compiler
    ; from removing the ones the main program doesn't use itself
    sub keep() {
        vid.compose_begin()
        vid.compose_end()
        void cells.rd(0)
        cells.mark_rows()
        void cells.row_has(1)
        cells.name_put(0)
        cells.name_get(0)
        cells.erase_range(1, 0, 1, 0)
        cells.release(0)
        cells.rehash()
        void cells.clip_copy(1, 0, 1, 0)
        cells.clip_clear()
        cells.clear_all()
        void cells.free_count()
        cells.save(0)
        void formula.adjust(0, 0)
        void formula.err_code(0)
        void formula.parse_ref(0)
        numfmt.fout_rec()
        void is_num(1, 0)
        append_range(1, 0, 1, 0)
        reset_view()
        changed()
        void sview.click()
        sview.add_btn(0, 0, 0)
        sview.set_filename(0)
        diskio.delete(tmpname)
        clip_cut = false
        sview.put(0, 0, 0, 0, 0)
        sview.num(0, 0, 0, 0, 0)
        vid.fill(0, 0, 0, 0, 0)
        theme.pill(0, 0, 0, 0, 0, 0)
        theme.stripes(0, 0, 0)
    }

    sub run() {
        if never
            keep()
        txt.iso()
        if not load_libs()
            return
        vid.load_fonts()
        vid.gfx_init()
        shl.upload_icons()
        void themes(0)                  ; after the icons: the theme (X16THEME.CFG / X16THEMEn.BIN), Quill on
        cells.init()
        sview.set_filename(iso:"untitled.xlsx")
        sview.set_status(iso:"Welcome! Click a cell and type. Formulas start with =")
        sview.redraw_everything()
        while running {
            sys.waitvsync()
            theme.tick()
            handle_keys()
            handle_mouse()
        }
        theme.off()
        vid.gfx_off()
    }

    ; ======================= editing =======================
    sub start_edit(uword text, bool keep) {
        sview.pt_on = false
        if keep
            sview.elen = sview.cell_source(sview.cur_r, sview.cur_c, &sview.ebuf)
        else {
            sview.elen = strings.length(text)
            sys.memcopy(text, &sview.ebuf, sview.elen)
        }
        sview.ecur = sview.elen
        sview.editing = true
        sview.draw_fbar()
        sview.draw_rows(sview.cur_r, sview.cur_r)
    }

    sub cancel_edit() {
        sview.editing = false
        sview.pt_on = false
        sview.draw_grid()
        sview.draw_fbar()
        sview.set_status(iso:"")
        sview.draw_status()
    }

    sub e_insert(ubyte c) {
        if sview.elen >= cells.MAXLEN + 1          ; '=' + 50
            return
        ubyte i = sview.elen
        while i > sview.ecur {
            sview.ebuf[i] = sview.ebuf[i - 1]
            i--
        }
        sview.ebuf[sview.ecur] = c
        sview.elen++
        sview.ecur++
    }

    sub e_delete(ubyte at) {
        if at >= sview.elen
            return
        ubyte i = at
        while i < sview.elen - 1 {
            sview.ebuf[i] = sview.ebuf[i + 1]
            i++
        }
        sview.elen--
    }

    ; store the edit buffer into the active cell (keeps its format). false = sheet full
    sub commit() -> bool {
        sview.editing = false
        bool had = sview.pt_on
        sview.pt_on = false
        sview.ebuf[sview.elen] = 0
        ; trim trailing blanks
        while sview.elen != 0 and sview.ebuf[sview.elen - 1] == 32 {
            sview.elen--
            sview.ebuf[sview.elen] = 0
        }
        uword r = sview.cur_r
        ubyte c = sview.cur_c
        bool exists = cells.get(r, c)
        ubyte sty = cells.R[cells.R_STY]
        if sview.elen == 0 {
            if exists {
                if sty != 0 {
                    cells.R[cells.R_TYPE] = cells.T_BLANK
                    cells.R[cells.R_LEN] = 0
                    void cells.put(r, c)
                } else
                    cells.erase(r, c)
            }
        } else {
            uword src = &sview.ebuf
            ubyte n = sview.elen
            float v = 0.0
            ubyte t = cells.T_TEXT
            if sview.ebuf[0] == iso:'=' and n > 1 {
                formula.tidy(&sview.ebuf)
                src++
                n = strings.length(src)
                t = cells.T_FORM
                if n > formula.MAXFLEN {
                    sview.elen = strings.length(&sview.ebuf)
                    sview.ecur = sview.elen
                    sview.editing = true
                    sview.set_status(iso:"Formula too long (46 characters at most)")
                    sview.draw_status()
                    sview.draw_fbar()
                    return false
                }
            } else if sview.ebuf[0] == 39 {
                src++                   ; leading apostrophe: always text
                n--
            } else if number_input() {
                t = cells.T_NUM
                v = formula.result
                if num_fmt != 0 and (sty & cells.ST_FMT) == 0
                    sty |= num_fmt << 3
                n = 0
            }
            if n > cells.MAXLEN
                n = cells.MAXLEN
            sys.memset(&cells.R, 64, 0)
            cells.R[cells.R_TYPE] = t
            cells.R[cells.R_STY] = sty
            cells.R[cells.R_LEN] = n
            sys.memcopy(src, &cells.R + cells.R_TXT, n)
            sys.memcopy(&v, &cells.R + cells.R_VAL, 5)
            if not cells.put(r, c) {
                shl.message(shl.T_SHEETFULL, shl.M_FULL)
                sview.redraw_everything()
                return false
            }
        }
        changed_area(r, c, r, c)
        return true
    }

    ; "12", "-3.5", "1e3", "$1,234.50" (currency), "12%" (percent) -> formula.result, num_fmt
    ubyte num_fmt
    ubyte[56] nb2
    sub number_input() -> bool {
        ubyte i = 0
        ubyte n = 0
        num_fmt = 0
        bool pct = false
        while sview.ebuf[i] != 0 {
            ubyte ch = sview.ebuf[i]
            if ch == iso:'$' {
                num_fmt = 3
            } else if ch == iso:',' {
                if num_fmt != 3 and n == 0
                    return false
            } else if ch == iso:'%' and sview.ebuf[i + 1] == 0 {
                pct = true
            } else {
                nb2[n] = ch
                n++
            }
            i++
        }
        nb2[n] = 0
        if not formula.parse_number(&nb2)
            return false
        if pct {
            formula.result = formula.result / 100.0
            num_fmt = 2
        }
        return true
    }

    ; one area changed (typing into a cell): recalculate only what depends on it
    sub changed_area(uword r1, ubyte c1, uword r2, ubyte c2) {
        formula.recalc_area(r1, c1, r2, c2)
        after_change()
    }

    ; something in the sheet changed: recalculate everything and redraw
    sub changed() {
        formula.recalc()
        after_change()
    }

    sub after_change() {
        sview.modified = true
        if formula.circular
            sview.set_status(iso:"Circular reference: values may be wrong")
        else
            sview.set_status(iso:"")
        cells.extent()
        sview.vmax = cells.used_rows + 30
        shl.draw_toolbar()
        sview.draw_grid()
        sview.draw_status()
    }

    ; ======================= selection / navigation =======================
    sub select(uword r, ubyte c, bool extend) {
        uword o1 = sview.anc_r
        uword o2 = sview.oth_r
        uword oc = sview.cur_r
        sview.sel_norm()
        uword a1 = sview.s_r1
        uword a2 = sview.s_r2
        bool wasmulti = not sview.single()
        if r < 1
            r = 1
        if r > cells.MAXROW
            r = cells.MAXROW
        if extend {
            sview.oth_r = r
            sview.oth_c = c
        } else {
            sview.anc_r = r
            sview.anc_c = c
            sview.oth_r = r
            sview.oth_c = c
            sview.cur_r = r
            sview.cur_c = c
        }
        if ensure_visible(r, c) {
            sview.draw_grid()
        } else {
            sview.draw_headers()
            sview.draw_rows(a1, a2)
            sview.sel_norm()
            sview.draw_rows(sview.s_r1, sview.s_r2)
            sview.draw_rows(oc, oc)
        }
        shl.draw_toolbar()
        if wasmulti or not sview.single()
            sview.draw_status()
    }

    ; scroll so that (r, c) is visible; true if the view moved
    sub ensure_visible(uword r, ubyte c) -> bool {
        bool moved = false
        if r < sview.toprow {
            sview.toprow = r
            moved = true
        } else if r >= sview.toprow + sview.GROWS {
            sview.toprow = r - sview.GROWS + 1
            moved = true
        }
        if c < sview.leftcol {
            sview.leftcol = c
            moved = true
        } else {
            repeat {
                sview.layout()
                ubyte vi = sview.vis_of(c)
                if vi != 255 and (vi < sview.vis_n - 1 or sview.vis_w[vi] == cells.colw[c] or vi == 0)
                    break
                sview.leftcol++
                moved = true
            }
        }
        return moved
    }

    sub scroll_rows(word d) {
        word t = (sview.toprow as word) + d
        if t < 1
            t = 1
        if t > ((cells.MAXROW - sview.GROWS + 1) as word)
            t = (cells.MAXROW - sview.GROWS + 1) as word
        if t as uword != sview.toprow {
            sview.toprow = t as uword
            sview.draw_grid()
        }
    }

    sub scroll_cols(byte d) {
        word t = (sview.leftcol as word) + d
        if t < 0
            t = 0
        if t > 255
            t = 255
        if lsb(t) != sview.leftcol {
            sview.leftcol = lsb(t)
            sview.draw_grid()
        }
    }

    ; ======================= keyboard =======================
    sub handle_keys() {
        ubyte k
        repeat 8 {
            k = cbm.GETIN2()
            if k == 0
                return
            if sview.editing
                edit_key(k)
            else
                nav_key(k)
        }
    }

    sub move(word dr, word dc) {
        word r = (sview.cur_r as word) + dr
        word c = (sview.cur_c as word) + dc
        if r < 1
            r = 1
        if r > (cells.MAXROW as word)
            r = cells.MAXROW as word
        if c < 0
            c = 0
        if c > 255
            c = 255
        select(r as uword, lsb(c), false)
    }

    sub nav_key(ubyte k) {
        when k {
            $91 -> move(-1, 0)
            $11, 13 -> move(1, 0)
            $9d -> move(0, -1)
            $1d, 9 -> move(0, 1)
            $82 -> {
                scroll_rows(-20)
                move(-20, 0)
            }
            $02 -> {
                scroll_rows(20)
                move(20, 0)
            }
            $13 -> select(sview.cur_r, 0, false)        ; Home
            $04 -> select(1, 0, false)                  ; End -> A1 (Shift+Home on some keyboards)
            137 -> start_edit(0, true)                  ; F2: edit the cell
            8, 20, 25, 127 -> shl.clear_cells(0)        ; Backspace / Delete: clear contents
            else -> {
                if (k >= 32 and k < 127) or k >= 161 {
                    nb2[0] = k
                    nb2[1] = 0
                    start_edit(&nb2, false)
                }
            }
        }
    }

    sub edit_key(ubyte k) {
        when k {
            13 -> {
                if commit()
                    move(1, 0)
                return
            }
            9 -> {
                if commit()
                    move(0, 1)
                return
            }
            27, 3 -> {
                cancel_edit()
                return
            }
            $91, $11 -> {
                if commit() {
                    if k == $91
                        move(-1, 0)
                    else
                        move(1, 0)
                }
                return
            }
            $9d -> {
                if sview.ecur != 0
                    sview.ecur--
            }
            $1d -> {
                if sview.ecur < sview.elen
                    sview.ecur++
            }
            $13 -> sview.ecur = 0
            $04 -> sview.ecur = sview.elen
            8, 20 -> {
                if sview.ecur != 0 {
                    sview.ecur--
                    e_delete(sview.ecur)
                }
            }
            25, 127 -> e_delete(sview.ecur)
            else -> {
                if (k >= 32 and k < 127) or k >= 161
                    e_insert(k)
            }
        }
        if sview.pt_on {
            sview.pt_on = false
            sview.draw_grid()
        }
        sview.draw_fbar()
        sview.draw_rows(sview.cur_r, sview.cur_r)
    }

    ; ======================= mouse =======================
    sub handle_mouse() {
        sview.poll_mouse()
        ubyte left = sview.mouse_btn & 1
        ubyte cx = sview.mouse_cx
        ubyte cy = sview.mouse_cy
        if sview.mouse_wheel != 0 {
            if sview.mouse_wheel < 0
                scroll_rows(-3)
            else
                scroll_rows(3)
        }
        if left != 0 and prev_btn == 0
            press(cx, cy)
        else if left != 0
            drag(cx, cy)
        else {
            drag_mode = 0
            hover(cx, cy)
        }
        prev_btn = left
    }

    sub hover(ubyte cx, ubyte cy) {
        ubyte id = sview.find_button(cx, cy)
        if theme.cur != 0 and theme.on_quill(cx, cy)
            id = 30                         ; SHUI's tip for Quill
        if id != last_tip {
            last_tip = id
            shl.show_tip(id)
        }
    }

    ; sheet cell under a grid screen position -> hit_r, hit_c
    uword hit_r
    ubyte hit_c
    sub grid_hit(ubyte cx, ubyte cy) -> bool {
        if cy < sview.GRID0 or cy >= sview.GRID0 + sview.GROWS or cx < sview.RHW or cx >= sview.GX1
            return false
        ubyte vi = sview.vis_at(cx)
        if vi == 255
            return false
        hit_r = sview.toprow + cy - sview.GRID0
        hit_c = sview.vis_col[vi]
        return hit_r <= cells.MAXROW
    }

    ; may a click on a cell insert a reference into the formula being typed?
    sub point_ok() -> bool {
        if not sview.editing or sview.ebuf[0] != iso:'=' or sview.ecur != sview.elen
            return false
        if sview.pt_on
            return true
        ubyte c = sview.ebuf[sview.elen - 1]
        return c == iso:'=' or c == iso:'(' or c == iso:'+' or c == iso:'-' or c == iso:'*' or c == iso:'/' or c == iso:'^' or c == iso:',' or c == iso:':' or c == iso:'<' or c == iso:'>'
    }

    ; (re)write the pointed reference/range at pt_pos
    sub put_point() {
        sview.elen = pt_pos
        ubyte[8] t
        ubyte n = formula.cell_name(sview.pt_r1, sview.pt_c1, &t)
        ubyte i
        for i in 0 to n - 1
            sview.ebuf[sview.elen + i] = t[i]
        sview.elen += n
        if sview.pt_r1 != sview.pt_r2 or sview.pt_c1 != sview.pt_c2 {
            sview.ebuf[sview.elen] = iso:':'
            sview.elen++
            n = formula.cell_name(sview.pt_r2, sview.pt_c2, &t)
            for i in 0 to n - 1
                sview.ebuf[sview.elen + i] = t[i]
            sview.elen += n
        }
        sview.ecur = sview.elen
        sview.draw_fbar()
        sview.draw_grid()
    }

    sub set_point(uword r, ubyte c) {
        sview.pt_r1 = pt_ar
        sview.pt_c1 = pt_ac
        sview.pt_r2 = r
        sview.pt_c2 = c
        if sview.pt_r1 > sview.pt_r2 {
            sview.pt_r1 = r
            sview.pt_r2 = pt_ar
        }
        if sview.pt_c1 > sview.pt_c2 {
            sview.pt_c1 = c
            sview.pt_c2 = pt_ac
        }
        put_point()
    }

    sub press(ubyte cx, ubyte cy) {
        ubyte id = sview.find_button(cx, cy)
        if id != 0 {
            do_button(id)
            return
        }
        if theme.on_quill(cx, cy) {
            ; Quill: the next theme, for every X16 Office app (X16THEME.CFG)
            if themes(1) {
                sview.set_status(theme.msg)
                sview.redraw_everything()
                theme.cheer()
            }
            return
        }
        ; formula bar text: start editing / move the cursor
        if cy == sview.FBAR and cx > sview.EDITX {
            if not sview.editing
                start_edit(0, true)
            ubyte p = cx - sview.EDITX - 1
            if p > sview.elen
                p = sview.elen
            sview.ecur = p
            sview.draw_fbar()
            return
        }
        if grid_hit(cx, cy) {
            if point_ok() {
                if not sview.pt_on
                    pt_pos = sview.elen
                sview.pt_on = true
                pt_ar = hit_r
                pt_ac = hit_c
                set_point(hit_r, hit_c)
                drag_mode = 2
                return
            }
            if sview.editing {
                if not commit()
                    return
            }
            ubyte now = lsb(cbm.RDTIM16())
            bool dbl = hit_r == last_click_r and hit_c == last_click_c and (now - last_click_time) < 25
            last_click_time = now
            last_click_r = hit_r
            last_click_c = hit_c
            select(hit_r, hit_c, false)
            if dbl
                start_edit(0, true)
            else
                drag_mode = 1
            return
        }
        ; column header: resize at the right edge, else select columns
        if cy == sview.HDR and cx >= sview.RHW and cx < sview.GX1 {
            ubyte vi = sview.vis_at(cx)
            if vi == 255
                return
            if sview.editing and not commit()
                return
            if cx == sview.vis_x[vi] + sview.vis_w[vi] - 1 and sview.vis_w[vi] == cells.colw[sview.vis_col[vi]] {
                resize_col = sview.vis_col[vi]
                drag_mode = 3
                return
            }
            ubyte c = sview.vis_col[vi]
            sview.anc_r = 1
            sview.anc_c = c
            sview.cur_r = sview.toprow
            sview.cur_c = c
            select(cells.MAXROW, c, true)
            sview.cur_r = sview.toprow
            drag_mode = 6
            return
        }
        if cy == sview.HDR and cx < sview.RHW {
            do_button(sview.B_ALL)
            return
        }
        ; row header: select rows
        if cx < sview.RHW and cy >= sview.GRID0 and cy < sview.GRID0 + sview.GROWS {
            if sview.editing and not commit()
                return
            uword r = sview.toprow + cy - sview.GRID0
            sview.anc_r = r
            sview.anc_c = 0
            sview.cur_r = r
            sview.cur_c = 0
            select(r, 255, true)
            drag_mode = 7
            return
        }
        ; scroll bars
        if cx == 79 and cy >= sview.GRID0 and cy < sview.GRID0 + sview.GROWS {
            vscroll(cy - sview.GRID0, true)
            drag_mode = 4
            return
        }
        if cy == sview.HSCROLL and cx >= sview.RHW and cx <= 78 {
            hscroll(cx, true)
            drag_mode = 5
        }
    }

    sub vscroll(ubyte sr, bool click) {
        if sr == 0 {
            if click
                scroll_rows(-3)
        } else if sr >= sview.GROWS - 1 {
            if click
                scroll_rows(3)
        } else {
            uword span = sview.vmax
            if span < 100
                span = 100
            word t = 1 + (((sr - 1) as uword) * (span / 20)) as word
            scroll_rows(t - (sview.toprow as word))
        }
    }

    sub hscroll(ubyte cx, bool click) {
        if cx == sview.RHW {
            if click
                scroll_cols(-1)
        } else if cx == 78 {
            if click
                scroll_cols(1)
        } else {
            uword t = ((cx - sview.RHW - 1) as uword * 255) / 71
            scroll_cols((t as word - sview.leftcol as word) as byte)
        }
    }

    sub drag(ubyte cx, ubyte cy) {
        when drag_mode {
            1, 2 -> {
                ubyte qx = cx
                ubyte qy = cy
                scroll_timer++
                if cy < sview.GRID0 {
                    qy = sview.GRID0
                    if scroll_timer & 3 == 0
                        scroll_rows(-1)
                } else if cy >= sview.GRID0 + sview.GROWS {
                    qy = sview.GRID0 + sview.GROWS - 1
                    if scroll_timer & 3 == 0
                        scroll_rows(1)
                }
                if cx < sview.RHW {
                    qx = sview.RHW
                    if scroll_timer & 7 == 0
                        scroll_cols(-1)
                } else if cx >= sview.GX1 {
                    qx = sview.GX1 - 1
                    if scroll_timer & 7 == 0
                        scroll_cols(1)
                }
                if not grid_hit(qx, qy)
                    return
                if drag_mode == 2 {
                    if hit_r != sview.pt_r2 or hit_c != sview.pt_c2 or sview.pt_r1 != pt_ar or sview.pt_c1 != pt_ac {
                        if not (hit_r == sview.pt_r2 and hit_c == sview.pt_c2 and (sview.pt_r1 == pt_ar or sview.pt_r2 == pt_ar))
                            set_point(hit_r, hit_c)
                    }
                } else if hit_r != sview.oth_r or hit_c != sview.oth_c
                    select(hit_r, hit_c, true)
            }
            3 -> {
                ubyte vi = sview.vis_of(resize_col)
                if vi == 255
                    return
                word w = (cx as word) - (sview.vis_x[vi] as word) + 1
                if w < 3
                    w = 3
                if w > 40
                    w = 40
                if lsb(w) != cells.colw[resize_col] {
                    cells.colw[resize_col] = lsb(w)
                    sview.modified = true
                    sview.draw_grid()
                }
            }
            4 -> {
                if cy >= sview.GRID0 and cy < sview.GRID0 + sview.GROWS
                    vscroll(cy - sview.GRID0, false)
            }
            5 -> {
                if cx > sview.RHW and cx < 78
                    hscroll(cx, false)
            }
            6 -> {
                if cy == sview.HDR or cy >= sview.GRID0 {
                    ubyte v2 = sview.vis_at(cx)
                    if v2 != 255 and sview.vis_col[v2] != sview.oth_c
                        select(cells.MAXROW, sview.vis_col[v2], true)
                }
            }
            7 -> {
                if cy >= sview.GRID0 and cy < sview.GRID0 + sview.GROWS {
                    uword r = sview.toprow + cy - sview.GRID0
                    if r != sview.oth_r
                        select(r, 255, true)
                }
            }
        }
    }

    ; ======================= actions =======================
    sub do_button(ubyte id) {
        if sview.editing {
            when id {
                sview.B_ECANCEL -> {
                    cancel_edit()
                    return
                }
                sview.B_EOK -> {
                    void commit()
                    return
                }
                sview.B_FX, sview.B_EFX, sview.B_SUM -> {
                    ; functions can be added to the formula being typed
                }
                else -> {
                    if not commit()
                        return
                }
            }
        }
        when id {
            sview.B_NEW -> shl.new_sheet()
            sview.B_OPEN -> shl.open_sheet()
            sview.B_SAVE -> shl.save_sheet(0)
            sview.B_SAVEAS -> shl.save_sheet(1)
            sview.B_CUT -> shl.copy_cells(1)
            sview.B_COPY -> shl.copy_cells(0)
            sview.B_PASTE -> shl.paste_cells()
            sview.B_ALL -> shl.select_all()
            sview.B_CLEAR -> shl.clear_cells(1)
            sview.B_BOLD -> shl.style_op(0)
            sview.B_AL -> shl.style_op(1)
            sview.B_AC -> shl.style_op(2)
            sview.B_AR -> shl.style_op(3)
            sview.B_GEN -> shl.style_op(10)
            sview.B_DEC -> shl.style_op(11)
            sview.B_PCT -> shl.style_op(12)
            sview.B_CUR -> shl.style_op(13)
            sview.B_SUM -> shl.autosum()
            sview.B_FX, sview.B_EFX -> shl.fx_menu()
            sview.B_INSROW -> shl.rowcol_op(1, 1)
            sview.B_DELROW -> shl.rowcol_op(1, 0)
            sview.B_INSCOL -> shl.rowcol_op(0, 1)
            sview.B_DELCOL -> shl.rowcol_op(0, 0)
            sview.B_NARROW -> shl.width_op(-1)
            sview.B_WIDER -> shl.width_op(1)
            sview.B_QUIT -> {
                if sview.modified {
                    bool q = shl.yesno(shl.M_QUIT)
                    if not q {
                        sview.redraw_everything()
                        return
                    }
                }
                running = false
            }
        }
    }

    sub is_num(uword r, ubyte c) -> bool {
        cells.lookup(r, c)
        return cells.lv_type == cells.T_NUM or cells.lv_type == cells.T_FORM
    }

    sub append(uword s) {
        while @(s) != 0 and sview.elen < cells.MAXLEN {
            sview.ebuf[sview.elen] = @(s)
            sview.elen++
            s++
        }
        sview.ecur = sview.elen
    }

    sub append_range(uword r1, ubyte c1, uword r2, ubyte c2) {
        ubyte[8] t
        void formula.cell_name(r1, c1, &t)
        append(&t)
        append(iso:":")
        void formula.cell_name(r2, c2, &t)
        append(&t)
    }

    sub reset_view() {
        sview.toprow = 1
        sview.leftcol = 0
        sview.cur_r = 1
        sview.cur_c = 0
        sview.anc_r = 1
        sview.anc_c = 0
        sview.oth_r = 1
        sview.oth_c = 0
        cells.extent()
        sview.vmax = cells.used_rows + 30
    }

    ; transfer progress from X16DOCS.BIN: r0 = done >> 8, r1 = total >> 8.
    ; Runs with RAM bank 61 mapped: only draws (VERA), never touches banked RAM.
    sub progress() {
        uword d = cx16.r0
        uword t = cx16.r1
        while t >= 600 {
            t >>= 1
            d >>= 1
        }
        ubyte p = 100
        if t != 0 and d < t
            p = lsb((d * 100) / t)
        pcttxt[13] = iso:' '
        pcttxt[14] = iso:' '
        if p >= 100 {
            pcttxt[13] = iso:'1'
            pcttxt[14] = iso:'0'
            p = 0
        } else if p >= 10
            pcttxt[14] = iso:'0' + p / 10
        pcttxt[15] = iso:'0' + p % 10
        vid.text(3, sview.STATUS_ROW, pcttxt, 0, theme.rl[theme.R_STAT_HI], theme.rl[theme.R_STAT] >> 4)
    }
}
