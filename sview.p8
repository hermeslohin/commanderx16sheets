; sview.p8 - X16 Sheets screen, main-RAM part: formula bar, column/row headers, the cell grid (with
; grid lines), scroll bars, status bar, mouse. The title bar, toolbars, tool tips and dialogs are in
; the SHUI.BIN bank library (shui.p8).
;
;  row 0      title bar                                   (quit icon at the right)
;  rows 1-2   icon toolbars
;  row 3      formula bar: cell name | cancel | accept | fx | contents
;  row 4      column headers
;  rows 5-27  grid (23 rows), column 79 = vertical scroll bar
;  row 28     horizontal scroll bar
;  row 29     status bar

%import syslib
%import conv
%import vid
%import icons
%import shlibs
%import cells
%import formula
%import numfmt
%import theme

sview {
    %option ignore_unused

    const ubyte FBAR = 3
    const ubyte HDR = 4
    const ubyte GRID0 = 5
    const ubyte GROWS = 23
    const ubyte HSCROLL = 28
    const ubyte STATUS_ROW = 29
    const ubyte RHW = 5                 ; row header width
    const ubyte GX1 = 79                ; first column after the grid (scroll bar)
    const ubyte EDITX = 17              ; formula bar text field

    ; button ids
    const ubyte B_NEW = 1
    const ubyte B_OPEN = 2
    const ubyte B_SAVE = 3
    const ubyte B_SAVEAS = 4
    const ubyte B_CUT = 5
    const ubyte B_COPY = 6
    const ubyte B_PASTE = 7
    const ubyte B_ALL = 8
    const ubyte B_BOLD = 9
    const ubyte B_AL = 10
    const ubyte B_AC = 11
    const ubyte B_AR = 12
    const ubyte B_CLEAR = 13
    const ubyte B_QUIT = 14
    const ubyte B_SUM = 15
    const ubyte B_FX = 16
    const ubyte B_GEN = 17
    const ubyte B_DEC = 18
    const ubyte B_PCT = 19
    const ubyte B_CUR = 20
    const ubyte B_INSROW = 21
    const ubyte B_DELROW = 22
    const ubyte B_INSCOL = 23
    const ubyte B_DELCOL = 24
    const ubyte B_NARROW = 25
    const ubyte B_WIDER = 26
    const ubyte B_ECANCEL = 27
    const ubyte B_EOK = 28
    const ubyte B_EFX = 29

    ubyte[48] bt_x
    ubyte[48] bt_y
    ubyte[48] bt_id
    ubyte bt_n

    ; ---------------- sheet view state ----------------
    uword toprow = 1
    ubyte leftcol = 0
    uword cur_r = 1                     ; active cell
    ubyte cur_c = 0
    uword anc_r = 1                     ; selection = anchor .. active corner (oth)
    ubyte anc_c = 0
    uword oth_r = 1
    ubyte oth_c = 0
    ; normalized selection
    uword s_r1
    uword s_r2
    ubyte s_c1
    ubyte s_c2
    ; formula "point" range (while typing a formula and clicking cells)
    bool pt_on
    uword pt_r1
    uword pt_r2
    ubyte pt_c1
    ubyte pt_c2

    ; visible columns
    ubyte vis_n
    ubyte[40] vis_col
    ubyte[40] vis_x
    ubyte[40] vis_w

    ; editing
    bool editing
    ubyte[64] ebuf
    ubyte elen
    ubyte ecur

    str filename = iso:"untitled.xlsx                   "
    str status_msg = iso:"                                              "
    str @shared nbuf = iso:"                                "
    bool modified
    bool @shared cloud_doc
    ubyte[20] tmp
    uword vmax = 100                    ; scroll range for the vertical bar

    sub sel_norm() {
        s_r1 = anc_r
        s_r2 = oth_r
        if s_r1 > s_r2 {
            s_r1 = oth_r
            s_r2 = anc_r
        }
        s_c1 = anc_c
        s_c2 = oth_c
        if s_c1 > s_c2 {
            s_c1 = oth_c
            s_c2 = anc_c
        }
    }

    sub single() -> bool {
        return anc_r == oth_r and anc_c == oth_c
    }

    sub copy_str(uword src, uword dst, ubyte maxn) {
        ubyte i = 0
        while @(src + i) != 0 and i < maxn {
            @(dst + i) = @(src + i)
            i++
        }
        @(dst + i) = 0
    }

    sub set_filename(uword s) {
        copy_str(s, filename, 30)
    }

    sub set_status(uword s) {
        ubyte i = 0
        while @(s + i) != 0 and i < 45 {
            status_msg[i] = @(s + i)
            i++
        }
        while i < 46 {
            status_msg[i] = 32
            i++
        }
        status_msg[46] = 0
    }

    sub put(ubyte col, ubyte row, uword s, ubyte fg, ubyte bg) {
        vid.text(col, row, s, 0, fg, bg)
    }

    sub num(ubyte col, ubyte row, uword n, ubyte fg, ubyte bg) {
        copy_str(conv.str_uw(n), &tmp, 8)
        vid.text(col, row, &tmp, 0, fg, bg)
    }

    ; ---------------- buttons ----------------
    sub add_btn(ubyte x, ubyte y, ubyte id) {
        if bt_n < 48 {
            bt_x[bt_n] = x
            bt_y[bt_n] = y
            bt_id[bt_n] = id
            bt_n++
        }
    }

    ; icon cell pair with a coloured face (Sunset: violet faces get cream glyphs, the others black)
    sub icon(ubyte col, ubyte row, ubyte k, ubyte id, ubyte face) {
        ubyte k2 = face << 4
        if face == vid.C_GRAY
            k2 |= vid.C_WHITE
        vid.r_ch[0] = k * 2
        vid.r_ch[1] = k * 2 + 1
        vid.r_sty[0] = vid.S_RAW | $30
        vid.r_sty[1] = vid.S_RAW | $30
        vid.r_col[0] = k2
        vid.r_col[1] = k2
        vid.render_run(row, col, 2)
        add_btn(col, row, id)
    }

    sub find_button(ubyte cx, ubyte cy) -> ubyte {
        ubyte i
        if bt_n == 0
            return 0
        for i in 0 to bt_n - 1 {
            if bt_y[i] == cy and (cx == bt_x[i] or cx == bt_x[i] + 1)
                return bt_id[i]
        }
        return 0
    }

    ; ---------------- formula bar ----------------
    sub draw_fbar() {
        ubyte i
        vid.fill(0, FBAR, 80, 0, vid.C_DGRAY)
        ; cell name chip
        for i in 0 to 6 {
            vid.r_ch[i] = 32
            vid.r_sty[i] = vid.S_BOLD
            vid.r_col[i] = vid.C_RED << 4
        }
        ubyte n = formula.cell_name(cur_r, cur_c, &tmp)
        for i in 0 to n - 1
            vid.r_ch[i + 1] = tmp[i]
        vid.render_run(FBAR, 0, 7)
        icon(8, FBAR, icons.I_QUIT, B_ECANCEL, vid.C_GRAY)
        icon(11, FBAR, icons.I_OK, B_EOK, vid.C_GRAY)
        icon(14, FBAR, icons.I_FX, B_EFX, vid.C_PURPLE)
        ; contents: cream on black, yellow while editing
        ubyte k = (vid.C_BLACK << 4) | vid.C_WHITE
        if editing
            k = (vid.C_BLACK << 4) | vid.C_YELLOW
        for i in 0 to 79 - EDITX {
            vid.r_ch[i] = 32
            vid.r_sty[i] = 0
            vid.r_col[i] = k
        }
        if editing {
            for i in 0 to elen - 1 {
                if i < elen
                    vid.r_ch[i + 1] = ebuf[i]
            }
            if elen == 0
                vid.r_ch[1] = 32
            vid.r_col[ecur + 1] = vid.C_YELLOW << 4   ; cursor: yellow block
        } else {
            n = cell_source(cur_r, cur_c, &ebuf)
            for i in 0 to n - 1 {
                if i < n
                    vid.r_ch[i + 1] = ebuf[i]
            }
        }
        vid.render_run(FBAR, EDITX, 80 - EDITX)
    }

    ; what you would edit for a cell: "=FORMULA", the text, or the number in General format
    sub cell_source(uword r, ubyte c, uword dst) -> ubyte {
        ubyte n = 0
        @(dst) = 0
        if not cells.get(r, c)
            return 0
        ubyte t = cells.R[cells.R_TYPE]
        ubyte l = cells.R[cells.R_LEN]
        if t == cells.T_FORM {
            @(dst) = iso:'='
            sys.memcopy(&cells.R + cells.R_TXT, dst + 1, l)
            n = l + 1
        } else if t == cells.T_TEXT {
            sys.memcopy(&cells.R + cells.R_TXT, dst, l)
            n = l
        } else if t == cells.T_NUM {
            float v
            sys.memcopy(&cells.R + cells.R_VAL, &v, 5)
            numfmt.general(v)
            n = numfmt.olen
            sys.memcopy(&numfmt.out, dst, n)
        }
        @(dst + n) = 0
        return n
    }

    ; ---------------- grid ----------------
    sub layout() {
        ubyte x = RHW
        ubyte c = leftcol
        vis_n = 0
        repeat {
            ubyte w = cells.colw[c]
            vis_col[vis_n] = c
            vis_x[vis_n] = x
            if x + w > GX1
                w = GX1 - x
            vis_w[vis_n] = w
            vis_n++
            x += w
            if x >= GX1 or c == 255 or vis_n == 40
                break
            c++
        }
    }

    ; visible index of a column, 255 if not visible
    sub vis_of(ubyte c) -> ubyte {
        ubyte i
        for i in 0 to vis_n - 1 {
            if vis_col[i] == c
                return i
        }
        return 255
    }

    ; screen x -> visible column index (255 = none)
    sub vis_at(ubyte x) -> ubyte {
        ubyte i
        for i in 0 to vis_n - 1 {
            if x >= vis_x[i] and x < vis_x[i] + vis_w[i]
                return i
        }
        return 255
    }

    sub in_sel(uword r, ubyte c) -> bool {
        return r >= s_r1 and r <= s_r2 and c >= s_c1 and c <= s_c2
    }

    sub draw_headers() {
        ubyte i
        ubyte x
        sel_norm()
        for x in 0 to 79 {
            vid.r_ch[x] = 32
            vid.r_sty[x] = 0
            vid.r_col[x] = vid.C_DGRAY << 4
        }
        vid.r_col[GX1] = vid.C_BLACK << 4
        for i in 0 to vis_n - 1 {
            ubyte c = vis_col[i]
            ubyte w = vis_w[i]
            ubyte k = (vid.C_DGRAY << 4) | vid.C_WHITE
            if c >= s_c1 and c <= s_c2
                k = vid.C_RED << 4
            for x in vis_x[i] to vis_x[i] + w - 1
                vid.r_col[x] = k
            vid.r_sty[vis_x[i] + w - 1] = vid.S_GRIDR
            ubyte n = formula.col_name(c, &tmp)
            x = vis_x[i] + (w - n) / 2
            vid.r_ch[x] = tmp[0]
            if n == 2 and x + 1 < GX1
                vid.r_ch[x + 1] = tmp[1]
        }
        vid.render_run(HDR, 0, 80)
    }

    ; draw one grid row (screen row sr)
    sub draw_row(ubyte sr) {
        uword r = toprow + sr
        ubyte x
        ubyte i
        ubyte k
        for x in 0 to 78 {
            vid.r_ch[x] = 32
            vid.r_sty[x] = vid.S_GRIDB
            vid.r_col[x] = (vid.C_WHITE << 4) | vid.C_BLACK
        }
        ; row header
        k = (vid.C_BLACK << 4) | vid.C_GRAY
        if r >= s_r1 and r <= s_r2
            k = vid.C_RED << 4
        for x in 0 to RHW - 1 {
            vid.r_col[x] = k
            vid.r_sty[x] = 0
        }
        if r <= cells.MAXROW {
            uword s = conv.str_uw(r)
            ubyte n = strings.length(s)
            for i in 0 to n - 1
                vid.r_ch[RHW - 1 - n + i] = @(s + i)
        }
        ; cell backgrounds (selection, point range) and column edges
        for i in 0 to vis_n - 1 {
            ubyte c = vis_col[i]
            ubyte bg = vid.C_WHITE
            if in_sel(r, c)
                bg = vid.C_LRED
            if pt_on and r >= pt_r1 and r <= pt_r2 and c >= pt_c1 and c <= pt_c2
                bg = vid.C_LGREEN
            if r == cur_r and c == cur_c
                bg = vid.C_RED
            for x in vis_x[i] to vis_x[i] + vis_w[i] - 1
                vid.r_col[x] = (bg << 4) | vid.C_BLACK
            vid.r_sty[vis_x[i] + vis_w[i] - 1] = vid.S_GRIDB | vid.S_GRIDR
        }
        if r <= cells.MAXROW {
            for i in 0 to vis_n - 1
                draw_cell(r, i)
        }
        draw_vscroll_cell(sr)
        vid.render_run(GRID0 + sr, 0, 80)
    }

    ubyte[64] dtext
    sub draw_cell(uword r, ubyte i) {
        ubyte c = vis_col[i]
        ubyte n = 0
        ubyte al = 1                    ; 1 left 2 center 3 right
        ubyte st = 0
        ubyte w = cells.colw[c]
        bool overflow = false
        if editing and r == cur_r and c == cur_c {
            sys.memcopy(&ebuf, &dtext, elen)
            n = elen
            overflow = true
        } else {
            if not cells.get(r, c)
                return
            ubyte t = cells.R[cells.R_TYPE]
            st = cells.R[cells.R_STY]
            if t == cells.T_TEXT {
                n = cells.R[cells.R_LEN]
                sys.memcopy(&cells.R + cells.R_TXT, &dtext, n)
                overflow = true
            } else if t == cells.T_NUM or t == cells.T_FORM {
                if t == cells.T_FORM and cells.R[cells.R_ERR] != 0 {
                    copy_str(formula.err_text(cells.R[cells.R_ERR]), &dtext, 10)
                    n = strings.length(&dtext)
                    al = 2
                } else {
                    float v
                    sys.memcopy(&cells.R + cells.R_VAL, &v, 5)
                    numfmt.format(v, (st >> 3) & 3, w - 1)
                    n = numfmt.olen
                    sys.memcopy(&numfmt.out, &dtext, n)
                    al = 3
                }
            } else
                return
            if (st >> 1) & 3 != 0
                al = (st >> 1) & 3
        }
        if n == 0
            return
        ubyte x0 = vis_x[i]
        ubyte sx
        if al == 3 and n < w
            sx = x0 + w - 1 - n
        else if al == 2 and n < w
            sx = x0 + (w - n) / 2
        else
            sx = x0
        ubyte lim = x0 + vis_w[i]
        if overflow and al == 1 {
            ; text spills into the empty cells to the right
            lim = x0 + w
            ubyte j = i + 1
            while j < vis_n and lim < sx + n {
                if cells.find(r, vis_col[j]) != $ffff
                    break
                lim = vis_x[j] + vis_w[j]
                j++
            }
            if lim > GX1
                lim = GX1
        }
        ubyte sty = 0
        if (st & 1) != 0
            sty = vid.S_BOLD
        ubyte k
        for k in 0 to n - 1 {
            ubyte x = sx + k
            if x >= lim
                break
            vid.r_ch[x] = dtext[k]
            vid.r_sty[x] = sty | vid.S_GRIDB
            if x == lim - 1
                vid.r_sty[x] |= vid.S_GRIDR
            if x >= x0 + w
                vid.r_col[x] = (vid.r_col[x0] & $f0) | vid.C_BLACK
        }
    }

    sub draw_vscroll_cell(ubyte sr) {
        vid.r_ch[79] = 32
        vid.r_sty[79] = 0
        vid.r_col[79] = vid.C_BLACK << 4
        if sr == 0 {
            vid.r_ch[79] = iso:'^'
            vid.r_col[79] = vid.C_RED
        } else if sr == GROWS - 1 {
            vid.r_ch[79] = iso:'v'
            vid.r_col[79] = vid.C_RED
        } else if sr == vthumb()
            vid.r_col[79] = vid.C_RED << 4
    }

    sub vthumb() -> ubyte {
        uword span = vmax
        if span < toprow + GROWS
            span = toprow + GROWS
        return 1 + lsb(((toprow - 1) / (span / 20 + 1)))
    }

    sub draw_hscroll() {
        ubyte x
        for x in 0 to 79 {
            vid.r_ch[x] = 32
            vid.r_sty[x] = 0
            vid.r_col[x] = vid.C_BLACK << 4
        }
        vid.r_ch[RHW] = iso:'<'
        vid.r_col[RHW] = vid.C_RED
        vid.r_ch[78] = iso:'>'
        vid.r_col[78] = vid.C_RED
        ; thumb over 72 cells for columns 0..255
        ubyte t = RHW + 1 + lsb((leftcol as uword * 71) / 255)
        vid.r_col[t] = vid.C_RED << 4
        vid.render_run(HSCROLL, 0, 80)
    }

    sub draw_grid() {
        ubyte sr
        layout()
        sel_norm()
        draw_headers()
        for sr in 0 to GROWS - 1
            draw_row(sr)
        draw_hscroll()
    }

    ; redraw only the grid rows showing sheet rows a..b
    sub draw_rows(uword a, uword b) {
        uword t
        if a > b {
            t = a
            a = b
            b = t
        }
        sel_norm()
        if b < toprow or a >= toprow + GROWS
            return
        if a < toprow
            a = toprow
        if b >= toprow + GROWS
            b = toprow + GROWS - 1
        for t in a to b
            draw_row(lsb(t - toprow))
    }

    ; ---------------- status bar ----------------
    str stat = iso:"                                 "
    sub draw_status() {
        ; Sunset: cream on black; Quill (theme sprite) sits in columns 0-1
        ; Work out the selection SUM first, then compose the whole row in vid's r_ buffers and render
        ; it in one pass: blanking the row first and drawing each piece on top made it flash.
        bool show_sum = not single() and not editing
        float sum = 0.0
        ubyte e = 0
        uword cnt = 0
        if show_sum {
            ; SUM / COUNT of the selection, like the status bar of a desktop spreadsheet
            sel_norm()
            ubyte n = 0
            n = add_s(n, iso:"SUM(")
            n += formula.cell_name(s_r1, s_c1, &formula.ob + n)
            formula.ob[n] = iso:':'
            n++
            n += formula.cell_name(s_r2, s_c2, &formula.ob + n)
            formula.ob[n] = iso:')'
            n++
            formula.eval(&formula.ob, n)
            sum = formula.result
            e = formula.everr
            cnt = formula.fcnt[0]
            if e == 0
                numfmt.format(sum, 0, 14)
        }
        ubyte i
        for i in 0 to 79 {
            vid.r_ch[i] = 32
            vid.r_sty[i] = 0
            vid.r_col[i] = (vid.C_BLACK << 4) | vid.C_WHITE
        }
        st_put(3, status_msg, vid.C_WHITE)
        if show_sum {
            st_put(49, iso:"Sum", vid.C_LGRAY)
            if e != 0
                st_put(53, formula.err_text(e), vid.C_RED)
            else
                st_put(53, &numfmt.out, vid.C_YELLOW)
            st_put(68, iso:"Count", vid.C_LGRAY)
            st_put(74, conv.str_uw(cnt), vid.C_YELLOW)
        }
        vid.render_run(STATUS_ROW, 0, 80)
    }

    sub st_put(ubyte col, uword s, ubyte fg) {
        ubyte n = 0
        while @(s + n) != 0 and col < 80 {
            vid.r_ch[col] = @(s + n)
            vid.r_col[col] = (vid.C_BLACK << 4) | fg
            col++
            n++
        }
    }

    sub add_s(ubyte n, str s) -> ubyte {
        ubyte i = 0
        while s[i] != 0 {
            formula.ob[n] = s[i]
            n++
            i++
        }
        return n
    }

    sub redraw_everything() {
        shl.draw_toolbar()
        draw_grid()
        draw_status()
    }

    ; ---------------- mouse ----------------
    ubyte mouse_btn
    ubyte mouse_cx
    ubyte mouse_cy
    byte mouse_wheel

    sub poll_mouse() {
        ubyte b
        uword mx
        uword my
        byte wh
        b, mx, my, wh = cx16.mouse_pos()
        mouse_btn = b
        mouse_wheel = wh
        mouse_cx = lsb(mx >> 3)
        mouse_cy = lsb(my >> 3)
        if mx >= 640
            mouse_cx = 79
        if my >= 240
            mouse_cy = 29
    }

    ; wait for a fresh left click; returns false on Esc
    bool prev_btn
    sub click() -> ubyte {
        ; 0 = nothing, 1 = click (mouse_cx/cy), 2 = Esc, other = key code + 2 (in last_key)
        sys.waitvsync()
        theme.tick()                    ; Quill keeps blinking in dialogs
        if keyscript != 0 and @(keyscript) != 0 {
            ; scripted keys for the automated tests
            last_key = @(keyscript)
            keyscript++
            if last_key == 27
                return 2
            return 3
        }
        last_key = cbm.GETIN2()
        if last_key == 27 or last_key == 3
            return 2
        if last_key != 0
            return 3
        poll_mouse()
        if mouse_btn & 1 != 0 {
            if not prev_btn {
                prev_btn = true
                return 1
            }
        } else
            prev_btn = false
        return 0
    }
    ubyte last_key
    uword @shared keyscript             ; test hook: keys for dialogs (0 = keyboard)
}
