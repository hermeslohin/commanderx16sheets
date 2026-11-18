; shops.p8 - SHOPS.BIN, RAM bank 57: X16 Sheets' editing operations: bold / alignment / number format,
; column widths, clear, cut / copy / paste (with relative reference adjustment and fill), insert and
; delete rows / columns (references follow), AutoSum, the function menu and Select All.
; Cell records are reached through main-RAM routines (mainsyms_57.p8): rd()/save() with mn.R.

%address  $A000
%memtop   $C000
%output   library
%zeropage dontuse

%import syslib
%import cellk
%import shlibs
%import mainsyms_57

main {
    %jmptable (
        ops.setup,          ; $A003
        ops.style_op,       ; $A006  r0L
        ops.width_op,       ; $A009  r0L (signed)
        ops.clear_cells,    ; $A00C  r0L = 1 all, 0 contents
        ops.copy_cells,     ; $A00F  r0L = 1 cut
        ops.paste_cells,    ; $A012
        ops.rowcol_op,      ; $A015  r0L = rows, r1L = insert
        ops.autosum,        ; $A018
        ops.fx_menu,        ; $A01B
        ops.select_all,     ; $A01E
    )
    sub start() {
    }
}

ops {
    sub setup() -> bool {
        return cx16.r0 == mn.CHECK
    }

    sub rtype() -> ubyte {
        return @(mn.R + cellk.R_TYPE)
    }
    sub rrow() -> uword {
        return peekw(mn.R)
    }
    sub rcol() -> ubyte {
        return @(mn.R + cellk.R_COL)
    }
    sub live(ubyte t) -> bool {
        return t != cellk.T_FREE and t < cellk.T_CLIP
    }

    ; ---------------- formatting ----------------
    ; op 0 bold toggle, 1..3 align (toggle), 10..13 number format
    sub style_op() {
        ubyte op = cx16.r0L
        mn.sel_norm()
        ubyte cur = 0
        if mn.get(mn.cur_r, mn.cur_c)
            cur = @(mn.R + cellk.R_STY)
        ubyte mask
        ubyte val
        if op == 0 {
            mask = cellk.ST_BOLD
            val = (cur & 1) ^ 1
        } else if op < 10 {
            mask = cellk.ST_ALIGN
            val = op << 1
            if (cur & mask) == val
                val = 0
        } else {
            mask = cellk.ST_FMT
            val = (op - 10) << 3
        }
        uword i
        uword top = mn.ntop
        if top != 0 {
            for i in 0 to top - 1 {
                if live(mn.rd(i)) and mn.in_sel(rrow(), rcol()) {
                    @(mn.R + cellk.R_STY) = (@(mn.R + cellk.R_STY) & ~mask) | val
                    mn.save(i)
                }
            }
        }
        ; empty cells get a formatted blank (typing there later keeps the format); small ranges only
        uword r
        ubyte c
        if val != 0 and (mn.s_r2 - mn.s_r1) < 200 and (mn.s_c2 - mn.s_c1) < 30 {
            for r in mn.s_r1 to mn.s_r2 {
                for c in mn.s_c1 to mn.s_c2 {
                    if mn.find(r, c) == $ffff {
                        sys.memset(mn.R, 64, 0)
                        @(mn.R + cellk.R_TYPE) = cellk.T_BLANK
                        @(mn.R + cellk.R_STY) = val
                        if not mn.cput(r, c)
                            break
                    }
                }
            }
        }
        mn.modified = true
        shl.draw_toolbar()
        mn.draw_grid()
    }

    sub width_op() {
        byte d = cx16.r0L as byte
        mn.sel_norm()
        ubyte c = mn.s_c1
        repeat {
            word w = (@(mn.colw + c) as word) + d
            if w >= 3 and w <= 40
                @(mn.colw + c) = lsb(w)
            if c == mn.s_c2
                break
            c++
        }
        mn.modified = true
        mn.draw_grid()
    }

    ; contents only (Delete key: formats stay) or everything (Clear icon)
    sub clear_cells() {
        bool all = cx16.r0L != 0
        mn.sel_norm()
        if all
            mn.erase_range(mn.s_r1, mn.s_c1, mn.s_r2, mn.s_c2)
        else {
            uword i
            uword top = mn.ntop
            if top != 0 {
                for i in 0 to top - 1 {
                    if live(mn.rd(i)) and mn.in_sel(rrow(), rcol()) {
                        if @(mn.R + cellk.R_STY) != 0 {
                            @(mn.R + cellk.R_TYPE) = cellk.T_BLANK
                            @(mn.R + cellk.R_LEN) = 0
                            mn.save(i)
                        } else
                            mn.erase(rrow(), rcol())
                    }
                }
            }
        }
        mn.changed()
    }

    ; ---------------- clipboard ----------------
    sub copy_cells() {
        bool cut = cx16.r0L != 0
        mn.sel_norm()
        if not mn.clip_copy(mn.s_r1, mn.s_c1, mn.s_r2, mn.s_c2) {
            mn.set_status(iso:"Not enough memory to copy that")
            mn.draw_status()
            return
        }
        mn.clip_cut = cut
        if cut {
            mn.erase_range(mn.s_r1, mn.s_c1, mn.s_r2, mn.s_c2)
            mn.changed()
            mn.set_status(iso:"Cut - click a cell and Paste")
        } else
            mn.set_status(iso:"Copied - click a cell and Paste")
        shl.draw_toolbar()
        mn.draw_status()
    }

    sub paste_cells() {
        if not mn.clip_any
            return
        mn.sel_norm()
        uword h = mn.clip_r2 - mn.clip_r1
        ubyte w = mn.clip_c2 - mn.clip_c1
        uword r
        ubyte c
        bool ok = true
        if h == 0 and w == 0 and not mn.single() and (mn.s_r2 - mn.s_r1 + 1) * (mn.s_c2 - mn.s_c1 + 1) <= 2000 {
            ; one cell fills the whole selection (fill down / fill right)
            for r in mn.s_r1 to mn.s_r2 {
                for c in mn.s_c1 to mn.s_c2 {
                    if ok
                        ok = paste_at(r, c)
                }
            }
        } else
            void paste_at(mn.s_r1, mn.s_c1)
        if mn.clip_cut {
            mn.clip_clear()
            mn.set_status(iso:"Moved")
        }
        mn.changed()
    }

    ; paste the clipboard with its top-left corner at (r, c)
    sub paste_at(uword r, ubyte c) -> bool {
        word dr = (r as word) - (mn.clip_r1 as word)
        word dc = (c as word) - (mn.clip_c1 as word)
        uword r2 = r + (mn.clip_r2 - mn.clip_r1)
        uword c2 = c as uword + (mn.clip_c2 - mn.clip_c1)
        if r2 > cellk.MAXROW
            r2 = cellk.MAXROW
        if c2 > 255
            c2 = 255
        mn.erase_range(r, c, r2, lsb(c2))
        uword i
        uword top = mn.ntop
        if top == 0
            return true
        for i in 0 to top - 1 {
            if mn.rd(i) >= cellk.T_CLIP {
                word nr = (rrow() as word) + dr
                word nc = (rcol() as word) + dc
                if nr < 1 or nr > (cellk.MAXROW as word) or nc < 0 or nc > 255
                    continue
                @(mn.R + cellk.R_TYPE) &= $7f
                if rtype() == cellk.T_FORM and not mn.clip_cut {
                    mn.adj_mode = cellk.ADJ_MOVE
                    mn.adj_dr = dr
                    mn.adj_dc = dc
                    fix_formula()
                }
                if not mn.cput(nr as uword, lsb(nc)) {
                    mn.set_status(iso:"Sheet full")
                    return false
                }
            }
        }
        return true
    }

    ; rewrite the references of the formula in mn.R (adj_* set by the caller)
    sub fix_formula() {
        if mn.adjust(mn.R + cellk.R_TXT, @(mn.R + cellk.R_LEN)) {
            @(mn.R + cellk.R_LEN) = mn.oblen
            sys.memcopy(mn.ob, mn.R + cellk.R_TXT, mn.oblen)
        } else
            @(mn.R + cellk.R_ERR) = cellk.E_REF
    }

    ; ---------------- rows / columns ----------------
    sub rowcol_op() {
        bool rows = cx16.r0L != 0
        bool insert = cx16.r1L != 0
        mn.sel_norm()
        uword at
        uword n
        if rows {
            at = mn.s_r1
            n = mn.s_r2 - mn.s_r1 + 1
            if n > 500
                n = 1
        } else {
            at = mn.s_c1
            n = (mn.s_c2 - mn.s_c1) as uword + 1
            if mn.s_c2 == 255 and mn.s_c1 == 0
                n = 1
        }
        mn.clip_clear()
        uword i
        uword v
        uword lim = cellk.MAXROW
        if not rows
            lim = 255
        uword top = mn.ntop
        if top != 0 {
            for i in 0 to top - 1 {
                if live(mn.rd(i)) {
                    if rows
                        v = rrow()
                    else
                        v = rcol()
                    if v >= at {
                        if insert
                            v += n
                        else if v < at + n {
                            drop(i)
                            continue
                        } else
                            v -= n
                        if v > lim {
                            drop(i)
                            continue
                        }
                        if rows
                            pokew(mn.R, v)
                        else
                            @(mn.R + cellk.R_COL) = lsb(v)
                        mn.save(i)
                    }
                }
            }
        }
        mn.rehash()
        ; column widths follow their columns
        if not rows {
            ubyte c
            ubyte a = lsb(at)
            ubyte k = lsb(n)
            if insert {
                c = 255
                while c >= a + k and c >= k {
                    @(mn.colw + c) = @(mn.colw + c - k)
                    c--
                }
                for c in a to lsb(at + n - 1)
                    @(mn.colw + c) = cellk.DEFW
            } else {
                for c in a to 255 {
                    if c as uword + n <= 255
                        @(mn.colw + c) = @(mn.colw + c + k)
                    else
                        @(mn.colw + c) = cellk.DEFW
                }
            }
        }
        ; every formula's references follow
        mn.adj_mode = cellk.ADJ_COLS
        if rows
            mn.adj_mode = cellk.ADJ_ROWS
        mn.adj_at = at
        mn.adj_n = n as word
        if not insert
            mn.adj_n = -(n as word)
        if top != 0 {
            for i in 0 to top - 1 {
                if mn.rd(i) == cellk.T_FORM {
                    fix_formula()
                    mn.save(i)
                }
            }
        }
        mn.changed()
    }

    sub drop(uword i) {
        mn.release(i)
        mn.nused--
    }

    ; ---------------- AutoSum / functions ----------------
    sub autosum() {
        if mn.editing {
            mn.append(iso:"SUM(")
            mn.draw_fbar()
            return
        }
        mn.sel_norm()
        uword r1 = mn.s_r1
        uword r2 = mn.s_r2
        ubyte c1 = mn.s_c1
        ubyte c2 = mn.s_c2
        if not mn.single() and r2 < cellk.MAXROW and r2 - r1 < 2000 {
            ; a block: a SUM under every column (or right of a single row)
            ubyte c
            if r1 == r2 and c2 < 255 {
                put_sum(r1, c2 + 1, r1, c1, r2, c2)
            } else {
                for c in c1 to c2 {
                    if not put_sum(r2 + 1, c, r1, c, r2, c)
                        break
                }
            }
            mn.select(r2 + 1, c1, false)
            return
        }
        ; one cell: numbers above, else to the left
        uword r = mn.cur_r
        ubyte cc = mn.cur_c
        mn.start_edit(iso:"=SUM(", false)
        if r > 1 and mn.is_num(r - 1, cc) {
            uword up = r - 1
            while up > 1 and mn.is_num(up - 1, cc)
                up--
            mn.append_range(up, cc, r - 1, cc)
            mn.append(iso:")")
        } else if cc > 0 and mn.is_num(r, cc - 1) {
            ubyte left = cc - 1
            while left > 0 and mn.is_num(r, left - 1)
                left--
            mn.append_range(r, left, r, cc - 1)
            mn.append(iso:")")
        } else
            mn.set_status(iso:"Drag over the cells to add, then press Return")
        mn.draw_fbar()
        mn.draw_rows(r, r)
        mn.draw_status()
    }

    sub put_sum(uword r, ubyte c, uword r1, ubyte c1, uword r2, ubyte c2) -> bool {
        mn.cur_r = r
        mn.cur_c = c
        mn.start_edit(iso:"=SUM(", false)
        mn.append_range(r1, c1, r2, c2)
        mn.append(iso:")")
        return mn.commit()
    }

    sub fx_menu() {
        ubyte k = shl.menu(4, 3, shl.MENU_FX)
        mn.draw_grid()
        if k == 255 {
            shl.draw_toolbar()
            return
        }
        if not mn.editing
            mn.start_edit(iso:"=", false)
        else
            mn.ecur = mn.elen
        mn.append(peekw(mn.fn_names + k * 2))
        mn.append(iso:"(")
        mn.set_status(iso:"Click or drag over cells, then press Return")
        shl.draw_toolbar()
        mn.draw_fbar()
        mn.draw_rows(mn.cur_r, mn.cur_r)
        mn.draw_status()
    }

    sub select_all() {
        mn.extent()
        mn.anc_r = 1
        mn.anc_c = 0
        mn.cur_r = 1
        mn.cur_c = 0
        uword ur = mn.used_rows
        if ur == 0
            ur = 1
        mn.select(ur, mn.used_cols, true)
    }
}
