; shfile.p8 - SHFILE.BIN, RAM bank 62: X16 Sheets' file handling: New, Open, Save, Save As, the file
; picker (SD card and ownCloud), and ownCloud through the X16 Office hub (same flow as X16 Write):
;   Open: dial the hub, list Documents/ (only .xlsx and .csv can be opened), download with conv 2
;         (the hub turns any xlsx/csv into the simple XLSX the X16 reads), load it.
;   Save: write the XLSX to a temp file, upload it with conv 2 (the hub stores a normal compressed
;         .xlsx, or a .csv); create-only, or overwrite exactly the version we opened. A conflict asks
;         Overwrite / New name / Cancel.
; Buffers handed to the X16Link libraries (banks 60/61) must be visible from there: they are in the
; free part of golden RAM after XB ($0608-$06F3), like X16 Write's cloud library.

%address  $A000
%memtop   $C000
%output   library
%zeropage dontuse

%import syslib
%import diskio
%import strings
%import x16link_ext
%import shlibs
%import mainsyms_62

main {
    %jmptable (
        fl.setup,           ; $A003  r0 = check -> A
        fl.new_sheet,       ; $A006
        fl.open_sheet,      ; $A009
        fl.save_sheet_e,    ; $A00C  r0L = 1 Save As
    )
    sub start() {
        fl.cname[0] = 0
    }
}

fl {
    const ubyte CONV_SHEET = 2
    const ubyte C_WHITE = 1
    const ubyte C_RED = 2
    const ubyte C_BLUE = 6
    const ubyte C_DGRAY = 11
    const ubyte C_GRAY = 12
    const ubyte C_LGRAY = 15
    const uword row = $0608         ; 72  picker row from list_row
    const uword pickname = $0650    ; 64  chosen name / key file name
    const uword setag = $0690       ; 48  etag in/out
    const uword emsg = $06c0        ; 52  error text

    ubyte[64] cname                 ; remote name ("" = not a cloud document)
    ubyte[48] cetag

    sub setup() -> bool {
        return cx16.r0 == mn.CHECK
    }

    sub copy(uword src, uword dst, ubyte maxn) {
        ubyte i = 0
        while @(src + i) != 0 and i < maxn {
            @(dst + i) = @(src + i)
            i++
        }
        @(dst + i) = 0
    }

    sub status(uword s) {
        mn.set_status(s)
        mn.draw_status()
    }

    sub is_cloud() -> bool {
        return cname[0] != 0
    }

    sub forget() {
        cname[0] = 0
        cetag[0] = 0
        mn.cloud_doc = false
    }

    ; ---------------- New / Open / Save ----------------
    sub discard_ok() -> bool {
        if not mn.modified
            return true
        bool ok = shl.yesno(shl.M_DISCARD)
        mn.redraw_everything()
        return ok
    }

    sub new_sheet() {
        if not discard_ok()
            return
        mn.clear_all()
        forget()
        mn.reset_view()
        mn.modified = false
        mn.set_filename(iso:"untitled.xlsx")
        mn.set_status(iso:"New sheet")
        mn.redraw_everything()
    }

    sub ensure_ext() {
        ubyte n = strings.length(mn.nbuf)
        ubyte i
        for i in 0 to n {
            if i < n and @(mn.nbuf + i) == iso:'.'
                return
        }
        if n < 26
            copy(iso:".xlsx", mn.nbuf + n, 6)
    }

    uword[] load_msg = [iso:"Loaded", iso:"Could not read that file", iso:"That is not an XLSX file",
                        iso:"Compressed XLSX: open it via ownCloud", iso:"No worksheet in that file",
                        iso:"Sheet full: only part was loaded"]

    ; load an xlsx file (name in main RAM)
    sub load_file(uword name) -> bool {
        status(iso:"Loading...")
        ubyte st = shl.xlsx_load(name)
        mn.reset_view()
        mn.modified = false
        mn.set_status(load_msg[st])
        if st == shl.ST_OK and shl.xlsx_lossy()
            mn.set_status(iso:"Loaded (some content could not be shown)")
        if st != shl.ST_OK and st != shl.ST_FULL {
            mn.clear_all()
            mn.reset_view()
            return false
        }
        return true
    }

    sub where(ubyte which) -> ubyte {
        if not mn.cloud_ok
            return 0
        ubyte m = shl.menu(3 + which * 6, 2, which)
        mn.redraw_everything()
        return m
    }

    sub open_sheet() {
        if not discard_ok()
            return
        ubyte m = where(0)
        if m == 1 {
            cl_open()
            return
        }
        if m != 0
            return
        if sd_pick() {
            if load_file(mn.xbuf) {
                forget()
                mn.set_filename(mn.xbuf)
            }
        }
        mn.redraw_everything()
    }

    sub save_sheet_e() {
        save_sheet(cx16.r0L != 0)
    }

    sub save_sheet(bool ask) {
        if not ask and is_cloud() {
            cl_save(false)
            return
        }
        if ask {
            ubyte m = where(1)
            if m == 1 {
                cl_save(true)
                return
            }
            if m != 0
                return
        }
        if ask or strings.startswith(mn.filename, iso:"untitled") {
            copy(mn.filename, mn.nbuf, 30)
            bool ok = shl.dialog_input(shl.T_SAVE_SD, mn.nbuf, 28)
            mn.redraw_everything()
            if not ok
                return
            ensure_ext()
        } else
            copy(mn.filename, mn.nbuf, 30)
        status(iso:"Saving...")
        if shl.xlsx_save(mn.nbuf) {
            forget()
            mn.set_filename(mn.nbuf)
            mn.modified = false
            mn.set_status(iso:"Saved as XLSX")
        } else
            mn.set_status(iso:"SAVE FAILED")
        mn.redraw_everything()
    }

    ; ---------------- file picker (SD card and ownCloud) ----------------
    const ubyte PX = 3
    const ubyte PY = 3
    const ubyte PW = 74
    const ubyte PROWS = 18
    const ubyte LROW = PY + 3
    uword p_total
    uword p_top
    uword p_sel
    bool p_cloud
    ubyte[72] prow

    ; 68-char row text of entry i into prow; false = can't be opened
    sub p_fetch(uword i) -> bool {
        sys.memset(&prow, 68, 32)
        prow[68] = 0
        if p_cloud {
            if lkapi.list_row(i, row) != 0 {
                copy(iso:"(list error)", &prow, 68)
                return false
            }
            sys.memcopy(row + 2, &prow, 69)
            ; only XLSX (type 4) and CSV (type 5) that the hub can deliver
            return (@(row + 1) & 1) == 0 and (@(row) == 4 or @(row) == 5)
        }
        mn.name_get(i)
        ubyte n = strings.length(mn.xbuf)
        sys.memcopy(mn.xbuf, &prow, n)
        sys.memcopy(iso:"XLSX", &prow + 64, 4)
        return true
    }

    sub p_row(ubyte r) {
        uword i = p_top + r
        ubyte y = LROW + r
        ubyte fg = 0
        ubyte bg = C_WHITE
        mn.vfill(PX + 1, y, PW - 2, 0, bg)
        if i >= p_total
            return
        if not p_fetch(i)
            fg = C_GRAY
        if i == p_sel {
            bg = C_BLUE
            fg = C_WHITE
            mn.vfill(PX + 1, y, PW - 2, fg, bg)
        }
        mn.vtext(PX + 2, y, &prow, 0, fg, bg)
    }

    sub p_list() {
        ubyte r
        for r in 0 to PROWS - 1
            p_row(r)
        mn.put(PX + 2, PY + PROWS + 4, iso:"      of      ", C_DGRAY, C_LGRAY)
        mn.num(PX + 2, PY + PROWS + 4, p_sel + 1, C_DGRAY, C_LGRAY)
        mn.num(PX + 11, PY + PROWS + 4, p_total, C_DGRAY, C_LGRAY)
    }

    sub p_move(word d) {
        if p_total == 0
            return
        word ns = (p_sel as word) + d
        if ns < 0
            ns = 0
        if ns >= (p_total as word)
            ns = (p_total - 1) as word
        p_sel = ns as uword
        if p_sel < p_top
            p_top = p_sel
        if p_sel >= p_top + PROWS
            p_top = p_sel - PROWS + 1
        p_list()
    }

    sub p_choose() -> bool {
        if p_total != 0 and p_fetch(p_sel)
            return true
        status(iso:"That file can't be opened here (XLSX/CSV only)")
        return false
    }

    sub draw_box(ubyte x, ubyte y, ubyte w, ubyte h) {
        ubyte r
        for r in y to y + h - 1
            mn.vfill(x, r, w, 0, C_LGRAY)
        mn.vfill(x, y, w, 0, 0)
        mn.vfill(x, y + h - 1, w, 0, 0)
    }

    ; chosen index in p_sel; false = cancelled
    sub picker(uword title, uword header) -> bool {
        p_top = 0
        p_sel = 0
        ubyte lastclick = 255
        ubyte lastt
        draw_box(PX, PY, PW, PROWS + 6)
        mn.vfill(PX, PY, PW, C_WHITE, C_BLUE)
        mn.put(PX + 2, PY, title, C_WHITE, C_BLUE)
        mn.put(PX + 2, PY + 2, header, C_DGRAY, C_LGRAY)
        mn.put(PX + 17, PY + PROWS + 4, iso:"Enter=open  Esc=cancel", C_DGRAY, C_LGRAY)
        mn.put(PX + PW - 22, PY + PROWS + 4, iso:"[ Open ]", 0, C_WHITE)
        mn.put(PX + PW - 12, PY + PROWS + 4, iso:"[Cancel]", 0, C_WHITE)
        p_list()
        if p_total == 0
            mn.put(PX + 2, LROW, iso:"(no spreadsheets found)", C_DGRAY, C_WHITE)
        mn.prev_btn = true
        repeat {
            ubyte k = mn.click()
            if mn.mouse_wheel < 0
                p_move(-3)
            else if mn.mouse_wheel > 0
                p_move(3)
            when k {
                2 -> return false
                3 -> {
                    when mn.last_key {
                        13 -> {
                            if p_choose()
                                return true
                        }
                        $91 -> p_move(-1)
                        $11 -> p_move(1)
                        $82 -> p_move(-PROWS)
                        $02 -> p_move(PROWS)
                    }
                }
                1 -> {
                    ubyte cy = mn.mouse_cy
                    ubyte cx = mn.mouse_cx
                    if cy == PY + PROWS + 4 and cx >= PX + PW - 22 and cx < PX + PW - 14 {
                        if p_choose()
                            return true
                    } else if cy == PY + PROWS + 4 and cx >= PX + PW - 12 and cx < PX + PW - 4 {
                        return false
                    } else if cy >= LROW and cy < LROW + PROWS and cx > PX and cx < PX + PW - 1 {
                        uword i = p_top + cy - LROW
                        if i < p_total {
                            ubyte now = lsb(cbm.RDTIM16())
                            if lsb(i) == lastclick and i == p_sel and now - lastt < 30 {
                                if p_choose()
                                    return true
                            }
                            lastclick = lsb(i)
                            lastt = now
                            p_move((i as word) - (p_sel as word))
                        }
                    }
                }
            }
        }
    }

    ; ---------------- SD card ----------------
    sub is_xlsx(uword nm, ubyte n) -> bool {
        return n >= 5 and @(nm + n - 5) == iso:'.' and (@(nm + n - 4) | 32) == iso:'x' and (@(nm + n - 3) | 32) == iso:'l' and (@(nm + n - 2) | 32) == iso:'s' and (@(nm + n - 1) | 32) == iso:'x'
    }

    ; *.xlsx in the current directory -> picker; the chosen name ends up in mn.xbuf
    sub sd_pick() -> bool {
        status(iso:"Reading the SD card...")
        p_total = 0
        if diskio.lf_start_list_files(0) {
            while diskio.lf_next_entry() and p_total < 190 {
                uword nm = diskio.list_filename
                ubyte n = strings.length(nm)
                if n < 32 and is_xlsx(nm, n) {
                    copy(nm, mn.xbuf, 31)
                    mn.name_put(p_total)
                    p_total++
                }
            }
            diskio.lf_end_list()
        }
        if p_total == 0 {
            ; no listing (or no xlsx files): ask for a name instead
            @(mn.nbuf) = 0
            bool ok = shl.dialog_input(shl.T_OPEN_SD, mn.nbuf, 28)
            if ok {
                ensure_ext()
                copy(mn.nbuf, mn.xbuf, 32)
            }
            return ok
        }
        p_cloud = false
        if not picker(iso:"Open from the SD card", iso:"Name")
            return false
        mn.name_get(p_sel)
        return true
    }

    ; ---------------- ownCloud ----------------
    sub fail(uword what) {
        ubyte i = 0
        while @(what + i) != 0 {
            @(emsg + i) = @(what + i)
            i++
        }
        @(emsg + i) = iso:':'
        @(emsg + i + 1) = iso:' '
        lkapi.get_error(emsg + i + 2, 50 - i - 2)
        mn.set_status(emsg)
    }

    sub online() -> bool {
        status(iso:"Connecting to the hub...")
        copy(iso:"X16LINK.KEY", pickname, 20)
        ubyte st = lkapi.load_key(pickname)
        if st == 0
            st = lkapi.connect()
        if st != 0 {
            lkapi.forget()
            fail(iso:"Hub unreachable")
            return false
        }
        return true
    }

    sub done() {
        lkapi.hangup()
        lkapi.forget()                  ; the key leaves RAM until the next transfer
    }

    sub cl_open() {
        if online() {
            status(iso:"Reading the Documents list...")
            if lkapi.list_begin() != 0 {
                fail(iso:"List failed")
            } else {
                p_total = lkapi.list_total()
                p_cloud = true
                if picker(iso:"Open from ownCloud - Documents", iso:"Name                                      Size  Modified        Type") {
                    void lkapi.list_name(p_sel, pickname, 64)
                    mn.redraw_everything()
                    status(iso:"Downloading...")
                    if lkapi.download(pickname, mn.tmpname, CONV_SHEET) != 0 {
                        fail(iso:"Open failed")
                    } else {
                        if load_file(mn.tmpname) {
                            lkapi.get_etag(setag, 48)
                            copy(setag, &cetag, 47)
                            copy(pickname, &cname, 63)
                            copy(pickname, mn.xbuf, 63)
                            mn.set_filename(mn.xbuf)
                            mn.cloud_doc = true
                            if shl.xlsx_lossy()
                                mn.set_status(iso:"Opened from ownCloud (some content not shown)")
                            else
                                mn.set_status(iso:"Opened from ownCloud")
                        } else
                            forget()
                    }
                    mn.disk_delete(mn.tmpname)
                } else
                    mn.set_status(iso:"Open cancelled")
            }
            done()
        }
        mn.redraw_everything()
    }

    sub ask_name() -> bool {
        bool ok = shl.dialog_input(shl.T_SAVE_OC, mn.nbuf, 40)
        mn.redraw_everything()
        if ok
            ensure_ext()
        return ok and @(mn.nbuf) != 0
    }

    sub same_as_current() -> bool {
        return strings.compare(mn.nbuf, &cname) == 0
    }

    sub cl_save(bool ask) {
        ubyte mode = 0
        if ask or not is_cloud() {
            if is_cloud()
                copy(&cname, mn.nbuf, 40)
            else
                copy(mn.filename, mn.nbuf, 40)
            if not ask_name()
                return
        } else
            copy(&cname, mn.nbuf, 40)
        status(iso:"Saving...")
        if not shl.xlsx_save(mn.tmpname) {
            mn.set_status(iso:"SAVE FAILED (temp file)")
            mn.redraw_everything()
            return
        }
        if online() {
            @(setag) = 0
            if is_cloud() and same_as_current() {
                mode = 1                    ; overwrite exactly the version we have
                copy(&cetag, setag, 47)
            }
            lkapi.set_etag(setag)
            repeat {
                status(iso:"Uploading...")
                ubyte st = lkapi.upload(mn.tmpname, mn.nbuf, mode, CONV_SHEET)
                if st == 0 {
                    lkapi.get_etag(setag, 48)
                    copy(setag, &cetag, 47)
                    copy(mn.nbuf, &cname, 63)
                    mn.set_filename(mn.nbuf)
                    mn.cloud_doc = true
                    mn.modified = false
                    mn.set_status(iso:"Saved to ownCloud")
                    break
                }
                if st != lkapi.S_CONFLICT {
                    fail(iso:"Save failed")
                    break
                }
                ubyte kind = lkapi.conflict(setag, 48)
                ubyte ex = 0
                if kind == 1
                    ex = 1
                ubyte choice = shl.conflict(ex)
                mn.redraw_everything()
                if choice == 0 {
                    mode = 1
                    lkapi.set_etag(setag)   ; overwrite the version the hub just told us about
                } else if choice == 1 {
                    if not ask_name() {
                        mn.set_status(iso:"Save cancelled")
                        break
                    }
                    mode = 0
                    @(setag) = 0
                    lkapi.set_etag(setag)
                } else {
                    mn.set_status(iso:"Save cancelled")
                    break
                }
            }
            done()
        }
        mn.disk_delete(mn.tmpname)
        mn.redraw_everything()
    }
}
