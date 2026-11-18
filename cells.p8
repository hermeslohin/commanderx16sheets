; cells.p8 - the sheet's cell store in banked ("high") RAM.
;
;   hash index : RAM banks 1..4    16384 slots x 2 bytes (record index + 1; 0 = empty, $ffff = deleted)
;   records    : RAM banks 5..55   128 records x 64 bytes per bank = 6528 cells on a 512 KB X16,
;                + banks 64..      on bigger machines (up to 12288 records in all)
;   bank 56    : used-row bitmap (xlsx writer)
;   banks 57-59, 62, 63: X16 Sheets' code libraries; 60/61: X16Link libraries.
;
; A record holds one cell: position, type, style, cached value (5-byte float) and up to 50 bytes of
; text (the text itself, or a formula without its leading '='). Clipboard cells are records too
; (type | T_CLIP); they are not in the hash index.
;
; Code in the bank libraries can't switch RAM banks, so they reach the records only through the
; routines here (via JSRFAR), mostly load()/rd()/save() with the R buffer in main RAM.

%import syslib
%import floats

cells {
    %option ignore_unused

    const uword MAXROW = 9999
    const ubyte MAXLEN = 50
    const ubyte HBANK = 1
    const uword HMASK = $3fff
    const ubyte PBANK = 5
    const ubyte PB_LOW = 51             ; banks 5..55
    const ubyte ROWBANK = 56
    const uword MAXRECS = 12288

    ; record layout
    const ubyte R_ROW = 0               ; uword
    const ubyte R_COL = 2
    const ubyte R_TYPE = 3
    const ubyte R_STY = 4               ; bold | align<<1 | fmt<<3 (the xlsx style index, see SHEETFMT.md)
    const ubyte R_ERR = 5               ; formula error code (0 = none)
    const ubyte R_LEN = 6
    const ubyte R_VAL = 7               ; 5-byte float; in free records: next free index
    const ubyte R_TXT = 12

    const ubyte T_FREE = 0
    const ubyte T_NUM = 1
    const ubyte T_TEXT = 2
    const ubyte T_FORM = 3
    const ubyte T_BLANK = 4             ; empty but formatted
    const ubyte T_CLIP = $80

    ; style bits
    const ubyte ST_BOLD = 1
    const ubyte ST_ALIGN = 6            ; mask, value >> 1: 0 general 1 left 2 center 3 right
    const ubyte ST_FMT = $18            ; mask, value >> 3: 0 general 1 0.00 2 percent 3 currency

    uword maxrecs
    uword ntop                          ; high-water mark of the record pool
    uword nused                         ; cells in the sheet
    uword nclip                         ; clipboard records
    uword ntomb                         ; deleted hash slots
    uword freehead
    ubyte[64] R                         ; record buffer in main RAM
    ubyte[64] xbuf                      ; strings handed between bank libraries (file names)
    ubyte[256] colw                     ; column widths in characters
    const ubyte DEFW = 10

    ; lookup results (lookup())
    ubyte lv_type
    ubyte lv_err
    float lv

    sub init() {
        uword nb = cx16.numbanks()      ; 64 on a 512 KB machine, 256 with 2 MB
        maxrecs = (PB_LOW as uword) * 128
        if nb > 64 {
            maxrecs += (nb - 64) * 128
            if maxrecs > MAXRECS
                maxrecs = MAXRECS
        }
        clear_all()
    }

    sub clear_all() {
        ubyte b
        for b in HBANK to HBANK + 3 {
            cx16.rambank(b)
            sys.memset($a000, 8192, 0)
        }
        ntop = 0
        nused = 0
        nclip = 0
        ntomb = 0
        freehead = $ffff
        sys.memset(&colw, 256, DEFW)
    }

    ; record index -> address in $a000-$bfff, with its RAM bank selected (hot path: assembly)
    ;   bank k = idx >> 7 -> 5 + k (k < 51) or 64 + k - 51,  address = $a000 + (idx & 127) * 64
    asmsub rec_ptr(uword idx @AY) clobbers(X) -> uword @AY {
        %asm {{
            sty  P8ZP_SCRATCH_B1
            tax
            asl  a                  ; carry = bit 7 of the low byte
            lda  P8ZP_SCRATCH_B1
            rol  a                  ; k = idx >> 7
            cmp  #p8c_PB_LOW
            bcc  +
            adc  #64-p8c_PB_LOW-1   ; carry is set
            bne  ++
+           adc  #p8c_PBANK         ; carry is clear
+           sta  $00                ; RAM bank
            txa
            and  #$7f
            lsr  a
            lsr  a
            ora  #$a0
            tay
            txa
            and  #3
            lsr  a
            ror  a
            ror  a                  ; (idx & 3) << 6
            rts
        }}
    }

    ; hash slot -> address, its bank selected: bank 1 + (h >> 12), $a000 + (h & $0fff) * 2
    asmsub hslot(uword h @AY) clobbers(X) -> uword @AY {
        %asm {{
            tax
            tya
            lsr  a
            lsr  a
            lsr  a
            lsr  a
            clc
            adc  #p8c_HBANK
            sta  $00
            tya
            and  #$0f
            sta  P8ZP_SCRATCH_B1
            txa
            asl  a
            tax
            lda  P8ZP_SCRATCH_B1
            rol  a
            ora  #$a0
            tay
            txa
            rts
        }}
    }

    sub hash(uword row, ubyte col) -> uword {
        return ((row << 6) + (row << 5) + row + col) & HMASK     ; row * 97 + col
    }

    ; record index of a cell, $ffff if there is none
    sub find(uword row, ubyte col) -> uword {
        uword h = hash(row, col)
        uword v
        uword rp
        repeat {
            v = peekw(hslot(h))
            if v == 0
                return $ffff
            if v != $ffff {
                rp = rec_ptr(v - 1)
                if @(rp + R_COL) == col and peekw(rp) == row
                    return v - 1
            }
            h = (h + 1) & HMASK
        }
    }

    sub hinsert(uword row, ubyte col, uword idx) {
        uword h = hash(row, col)
        uword p
        uword v
        repeat {
            p = hslot(h)
            v = peekw(p)
            if v == 0 or v == $ffff {
                if v == $ffff
                    ntomb--
                pokew(p, idx + 1)
                return
            }
            h = (h + 1) & HMASK
        }
    }

    sub hremove(uword row, ubyte col) {
        uword h = hash(row, col)
        uword p
        uword v
        uword rp
        repeat {
            p = hslot(h)
            v = peekw(p)
            if v == 0
                return
            if v != $ffff {
                rp = rec_ptr(v - 1)
                if @(rp + R_COL) == col and peekw(rp) == row {
                    void hslot(h)
                    pokew(p, $ffff)
                    ntomb++
                    if ntomb > 2000
                        rehash()
                    return
                }
            }
            h = (h + 1) & HMASK
        }
    }

    ; rebuild the index from the record pool (after rows/columns moved, or too many deleted slots)
    sub rehash() {
        ubyte b
        for b in HBANK to HBANK + 3 {
            cx16.rambank(b)
            sys.memset($a000, 8192, 0)
        }
        ntomb = 0
        uword i
        uword rp
        ubyte t
        if ntop == 0
            return
        for i in 0 to ntop - 1 {
            rp = rec_ptr(i)
            t = @(rp + R_TYPE)
            if t != T_FREE and t < T_CLIP
                hinsert(peekw(rp), @(rp + R_COL), i)
        }
    }

    sub alloc() -> uword {
        uword idx
        if freehead != $ffff {
            idx = freehead
            freehead = peekw(rec_ptr(idx) + R_VAL)
            return idx
        }
        if ntop < maxrecs {
            ntop++
            return ntop - 1
        }
        return $ffff
    }

    sub release(uword idx) {
        uword rp = rec_ptr(idx)
        @(rp + R_TYPE) = T_FREE
        pokew(rp + R_VAL, freehead)
        freehead = idx
    }

    sub free_count() -> uword {
        uword n = maxrecs - ntop
        uword f = freehead
        while f != $ffff {
            n++
            f = peekw(rec_ptr(f) + R_VAL)
        }
        return n
    }

    ; ---------------- whole-record access through R ----------------
    sub load(uword idx) {
        sys.memcopy(rec_ptr(idx), &R, 64)
    }

    sub save(uword idx) {
        uword rp = rec_ptr(idx)
        sys.memcopy(&R, rp, 64)
    }

    ; load the cell at row/col into R; false (and R = empty cell) if there is none
    sub get(uword row, ubyte col) -> bool {
        uword idx = find(row, col)
        if idx == $ffff {
            sys.memset(&R, 64, 0)
            pokew(&R, row)
            R[R_COL] = col
            return false
        }
        load(idx)
        return true
    }

    ; store R as cell (row, col); false if the sheet is full
    sub put(uword row, ubyte col) -> bool {
        pokew(&R, row)
        R[R_COL] = col
        uword idx = find(row, col)
        if idx == $ffff {
            idx = alloc()
            if idx == $ffff
                return false
            save(idx)
            hinsert(row, col, idx)
            nused++
            return true
        }
        save(idx)
        return true
    }

    sub erase(uword row, ubyte col) {
        uword idx = find(row, col)
        if idx == $ffff
            return
        hremove(row, col)
        release(idx)
        nused--
    }

    ; value of a cell for formulas: lv_type (T_*), lv_err, lv
    sub lookup(uword row, ubyte col) {
        uword idx = find(row, col)
        lv_err = 0
        lv = 0.0
        if idx == $ffff {
            lv_type = T_FREE
            return
        }
        uword rp = rec_ptr(idx)
        lv_type = @(rp + R_TYPE)
        if lv_type == T_NUM or lv_type == T_FORM {
            lv_err = @(rp + R_ERR)
            sys.memcopy(rp + R_VAL, &lv, 5)
        }
    }

    ; load record idx into R, return its type
    sub rd(uword idx) -> ubyte {
        load(idx)
        return R[R_TYPE]
    }

    ; used-row bitmap in bank 56 (bit set = row has cells)
    sub mark_rows() {
        cx16.rambank(ROWBANK)
        sys.memset($a000, 1252, 0)
        uword i
        uword rp
        ubyte t
        uword r
        if ntop == 0
            return
        for i in 0 to ntop - 1 {
            rp = rec_ptr(i)
            t = @(rp + R_TYPE)
            if t != T_FREE and t < T_CLIP {
                r = peekw(rp)
                cx16.rambank(ROWBANK)
                @($a000 + (r >> 3)) |= 1 << lsb(r & 7)
            }
        }
    }

    sub row_has(uword r) -> bool {
        cx16.rambank(ROWBANK)
        return @($a000 + (r >> 3)) & (1 << lsb(r & 7)) != 0
    }

    ; SD card file names for the picker (bank 56 from $a800, 190 x 32 bytes), through sview.xbuf
    sub name_put(uword i) {
        cx16.rambank(ROWBANK)
        sys.memcopy(&xbuf, $a800 + i * 32, 32)
    }
    sub name_get(uword i) {
        cx16.rambank(ROWBANK)
        sys.memcopy($a800 + i * 32, &xbuf, 32)
    }

    sub rec_type(uword idx) -> ubyte {
        return @(rec_ptr(idx) + R_TYPE)
    }

    ; ---------------- clipboard ----------------
    uword clip_r1
    uword clip_r2
    ubyte clip_c1
    ubyte clip_c2
    bool clip_any

    sub clip_clear() {
        uword i
        uword rp
        if nclip != 0 and ntop != 0 {
            for i in 0 to ntop - 1 {
                rp = rec_ptr(i)
                if @(rp + R_TYPE) >= T_CLIP
                    release(i)
            }
        }
        nclip = 0
        clip_any = false
    }

    ; copy the range into the clipboard (positions kept absolute); false if out of memory
    sub clip_copy(uword r1, ubyte c1, uword r2, ubyte c2) -> bool {
        clip_clear()
        clip_r1 = r1
        clip_r2 = r2
        clip_c1 = c1
        clip_c2 = c2
        clip_any = true
        uword i
        uword rp
        uword r
        ubyte c
        ubyte t
        uword top = ntop
        if top == 0
            return true
        for i in 0 to top - 1 {
            rp = rec_ptr(i)
            t = @(rp + R_TYPE)
            if t != T_FREE and t < T_CLIP {
                r = peekw(rp)
                c = @(rp + R_COL)
                if r >= r1 and r <= r2 and c >= c1 and c <= c2 {
                    load(i)
                    uword n = alloc()
                    if n == $ffff {
                        clip_clear()
                        return false
                    }
                    R[R_TYPE] = t | T_CLIP
                    save(n)
                    nclip++
                }
            }
        }
        return true
    }

    ; ---------------- range scans ----------------
    ; erase every cell in the range
    sub erase_range(uword r1, ubyte c1, uword r2, ubyte c2) {
        uword i
        uword rp
        uword r
        ubyte c
        ubyte t
        if ntop == 0
            return
        for i in 0 to ntop - 1 {
            rp = rec_ptr(i)
            t = @(rp + R_TYPE)
            if t != T_FREE and t < T_CLIP {
                r = peekw(rp)
                c = @(rp + R_COL)
                if r >= r1 and r <= r2 and c >= c1 and c <= c2 {
                    hremove(r, c)
                    release(i)
                    nused--
                }
            }
        }
    }

    ; used area: max row / max column of all cells (0 rows = empty sheet)
    uword used_rows
    ubyte used_cols
    sub extent() {
        uword i
        uword rp
        ubyte t
        used_rows = 0
        used_cols = 0
        if ntop == 0
            return
        for i in 0 to ntop - 1 {
            rp = rec_ptr(i)
            t = @(rp + R_TYPE)
            if t != T_FREE and t < T_CLIP {
                if peekw(rp) > used_rows
                    used_rows = peekw(rp)
                if @(rp + R_COL) > used_cols
                    used_cols = @(rp + R_COL)
            }
        }
    }
}
