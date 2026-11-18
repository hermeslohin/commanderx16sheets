; shxr.p8 - SHXR.BIN, RAM bank 58: the XLSX reader of X16 Sheets (see SHEETFMT.md).
; Streams the ZIP from the SD card, skips other entries, parses xl/worksheets/sheet1.xml as it goes
; (only stored entries: compressed files come through the hub, which converts them).

%address  $A000
%memtop   $C000
%output   library
%zeropage dontuse

%import syslib
%import diskio
%import conv
%import strings
%import cellk
%import mainsyms_58

main {
    %jmptable (
        xr.setup,           ; $A003  r0 = check -> A
        xr.load_e,          ; $A006  r0 = file name (main RAM) -> A status
        xr.lossy_e,         ; $A009  -> A
    )
    sub start() {
    }
}

xr {
    const ubyte ST_OK = 0
    const ubyte ST_DISK = 1
    const ubyte ST_FORMAT = 2       ; not a zip / not xlsx
    const ubyte ST_COMPRESSED = 3   ; deflated (needs the hub)
    const ubyte ST_NOSHEET = 4
    const ubyte ST_FULL = 5
    bool lossy

    sub setup() -> bool {
        return cx16.r0 == mn.CHECK
    }
    sub load_e() -> ubyte {
        return load(cx16.r0)
    }
    sub lossy_e() -> bool {
        return lossy
    }

    ; ---------------- load ----------------
    uword ibuf = memory("xibuf", 256, 0)
    uword ipos
    uword ilen
    bool ieof
    long remain                     ; bytes left in the current zip entry

    sub fill() -> bool {
        ilen = diskio.f_read(ibuf, 256)
        ipos = 0
        if ilen == 0
            ieof = true
        return ilen != 0
    }

    ; next byte of the file (raw)
    sub rb() -> ubyte {
        if ipos >= ilen {
            if not fill()
                return 0
        }
        ipos++
        return @(ibuf + ipos - 1)
    }

    ; next byte of the current entry; ieof at its end
    sub nb() -> ubyte {
        if remain == 0 {
            ieof = true
            return 0
        }
        remain--
        return rb()
    }

    ubyte[30] hdr
    ubyte[72] ename

    sub load(uword fname) -> ubyte {
        lossy = false
        ieof = false
        ilen = 0
        ipos = 0
        if not diskio.f_open(fname)
            return ST_DISK
        ubyte st = ST_NOSHEET
        repeat {
            ubyte i
            for i in 0 to 3
                hdr[i] = rb()
            if ieof {
                st = ST_FORMAT
                break
            }
            if hdr[0] != iso:'P' or hdr[1] != iso:'K' {
                st = ST_FORMAT
                break
            }
            if hdr[2] != 3 or hdr[3] != 4
                break                   ; central directory: no (more) entries
            for i in 4 to 29
                hdr[i] = rb()
            uword flags = mkword(hdr[7], hdr[6])
            uword method = mkword(hdr[9], hdr[8])
            remain = mklong(hdr[21], hdr[20], hdr[19], hdr[18])
            uword nlen = mkword(hdr[27], hdr[26])
            uword xlen = mkword(hdr[29], hdr[28])
            ubyte k = 0
            while nlen != 0 {
                ubyte ch = rb()
                if k < 71 {
                    ename[k] = ch
                    k++
                }
                nlen--
            }
            ename[k] = 0
            while xlen != 0 {
                void rb()
                xlen--
            }
            if ieof {
                st = ST_FORMAT
                break
            }
            bool sheet = strings.startswith(&ename, iso:"xl/worksheets/sheet") and strings.endswith(&ename, iso:".xml")
            if (flags & 8) != 0 and (method != 0 or sheet) {
                st = ST_COMPRESSED      ; sizes only in a data descriptor
                break
            }
            if sheet {
                if method != 0 {
                    st = ST_COMPRESSED
                    break
                }
                mn.clear_all()
                st = parse_sheet()
                break
            }
            while remain != 0 {
                void rb()
                remain--
                if ieof
                    break
            }
        }
        diskio.f_close()
        if st == ST_OK
            mn.recalc()
        return st
    }

    ; ---------------- sheet XML ----------------
    ubyte[20] tag
    ubyte[16] an                    ; attribute name
    ubyte[40] av                    ; attribute value
    ubyte[56] vtext                 ; <v>
    ubyte vn
    ubyte[56] ftext                 ; <f>
    ubyte fn
    ubyte[56] ttext                 ; <t> (inline string, may come in several runs)
    ubyte tn
    bool has_f
    bool has_v
    bool has_t
    uword crow
    ubyte ccol
    ubyte csty
    ubyte ctype                     ; 0 n, 1 inlineStr, 2 str, 3 e, 4 b, 5 s
    bool full
    ubyte pend                      ; a byte read ahead (0 = none)

    sub getc() -> ubyte {
        if pend != 0 {
            ubyte c = pend
            pend = 0
            return c
        }
        return nb()
    }

    sub parse_sheet() -> ubyte {
        full = false
        pend = 0
        ubyte c
        repeat {
            c = getc()
            if ieof
                break
            if c == iso:'<'
                read_tag()
            if full
                return ST_FULL
        }
        return ST_OK
    }

    sub is_tag(str s) -> bool {
        return strings.compare(&tag, s) == 0
    }

    sub read_tag() {
        ubyte n = 0
        ubyte c = getc()
        if c == iso:'?' or c == iso:'!' {
            ; declaration / comment: skip to '>'
            while not ieof and c != iso:'>'
                c = getc()
            return
        }
        while c != 32 and c != iso:'>' and c != iso:'/' and c != 13 and c != 10 and c != 9 and not ieof {
            if n < 19 {
                tag[n] = c
                n++
            }
            c = getc()
        }
        if c == iso:'/' and n == 0 {
            ; closing tag
            c = getc()
            while c != iso:'>' and not ieof {
                if n < 19 {
                    tag[n] = c
                    n++
                }
                c = getc()
            }
            tag[n] = 0
            if is_tag(iso:"c")
                end_cell()
            return
        }
        tag[n] = 0
        bool cell = is_tag(iso:"c")
        bool col = is_tag(iso:"col")
        if cell {
            crow = 0
            ccol = 0
            csty = 0
            ctype = 0
            has_f = false
            has_v = false
            has_t = false
            vn = 0
            fn = 0
            tn = 0
        }
        uword cmin = 0
        uword cmax = 0
        ubyte cw = 0
        bool selfclose = false
        ; attributes
        repeat {
            while c == 32 or c == 13 or c == 10 or c == 9
                c = getc()
            if c == iso:'>' or ieof
                break
            if c == iso:'/' {
                selfclose = true
                c = getc()
                continue
            }
            ubyte k = 0
            while c != iso:'=' and c != iso:'>' and c != 32 and not ieof {
                if k < 15 {
                    an[k] = c
                    k++
                }
                c = getc()
            }
            an[k] = 0
            if c != iso:'='
                continue
            ubyte q = getc()
            k = 0
            c = getc()
            while c != q and not ieof {
                if k < 39 {
                    av[k] = c
                    k++
                }
                c = getc()
            }
            av[k] = 0
            c = getc()
            if cell {
                if strings.compare(&an, iso:"r") == 0 {
                    @(mn.fb) = 0
                    sys.memcopy(&av, mn.fb, k + 1)
                    if mn.parse_ref(0) {
                        crow = mn.ref_row
                        ccol = mn.ref_col
                    } else
                        lossy = true
                } else if strings.compare(&an, iso:"s") == 0 {
                    csty = lsb(conv.str2uword(&av))
                    if csty > 31 {
                        csty = 0
                        lossy = true
                    }
                } else if strings.compare(&an, iso:"t") == 0 {
                    when av[0] {
                        iso:'i' -> ctype = 1
                        iso:'e' -> ctype = 3
                        iso:'b' -> ctype = 4
                        iso:'s' -> {
                            if av[1] == iso:'t'
                                ctype = 2
                            else
                                ctype = 5
                        }
                    }
                }
            } else if col {
                if strings.compare(&an, iso:"min") == 0
                    cmin = conv.str2uword(&av)
                else if strings.compare(&an, iso:"max") == 0
                    cmax = conv.str2uword(&av)
                else if strings.compare(&an, iso:"width") == 0
                    cw = lsb(conv.str2uword(&av))
            }
        }
        if col {
            if cw < 3
                cw = 3
            if cw > 40
                cw = 40
            if cmax > 256
                cmax = 256
            while cmin >= 1 and cmin <= cmax {
                @(mn.colw + lsb(cmin - 1)) = cw
                cmin++
            }
            return
        }
        if cell {
            if selfclose
                end_cell()
            return
        }
        if selfclose
            return
        if is_tag(iso:"v") {
            vn = capture(&vtext, 0)
            has_v = true
        } else if is_tag(iso:"f") {
            fn = capture(&ftext, 0)
            has_f = true
        } else if is_tag(iso:"t") {
            tn = capture(&ttext, tn)
            has_t = true
        }
    }

    ; element text up to the next '<' (left in pend), entities decoded; returns the new length
    sub capture(uword dst, ubyte n) -> ubyte {
        ubyte c
        repeat {
            c = getc()
            if ieof
                break
            if c == iso:'<' {
                pend = c
                break
            }
            if c == iso:'&'
                c = entity()
            else if c >= $c0 {
                ; UTF-8 (the hub writes &#N; but be tolerant)
                ubyte c2 = getc()
                if c == $c2 or c == $c3
                    c = (c << 6) | (c2 & $3f)
                else {
                    if c >= $e0
                        void getc()
                    if c >= $f0
                        void getc()
                    c = iso:'?'
                    lossy = true
                }
            }
            if c == 0
                continue
            if n < cellk.MAXLEN {
                @(dst + n) = c
                n++
            } else
                lossy = true
        }
        @(dst + n) = 0
        return n
    }

    ubyte[12] ent
    sub entity() -> ubyte {
        ubyte k = 0
        ubyte c = getc()
        while c != iso:';' and not ieof and k < 11 {
            ent[k] = c
            k++
            c = getc()
        }
        ent[k] = 0
        if strings.compare(&ent, iso:"amp") == 0
            return iso:'&'
        if strings.compare(&ent, iso:"lt") == 0
            return iso:'<'
        if strings.compare(&ent, iso:"gt") == 0
            return iso:'>'
        if strings.compare(&ent, iso:"quot") == 0
            return iso:'"'
        if strings.compare(&ent, iso:"apos") == 0
            return 39
        if ent[0] == iso:'#' {
            uword u
            if ent[1] == iso:'x' or ent[1] == iso:'X'
                u = conv.hex2uword(&ent + 2)
            else
                u = conv.str2uword(&ent + 1)
            when u {
                $20ac -> return $a4
                $0160 -> return $a6
                $0161 -> return $a8
                $017d -> return $b4
                $017e -> return $b8
                $0152 -> return $bc
                $0153 -> return $bd
                $0178 -> return $be
                9 -> return 32
                10, 13 -> return 32
            }
            if u >= 32 and u < 256 and u != $a4 and u != $a6 and u != $a8 and u != $b4 and u != $b8 and u != $bc and u != $bd and u != $be
                return lsb(u)
        }
        lossy = true
        return iso:'?'
    }

    ubyte[5] one = [$81, 0, 0, 0, 0]       ; 1.0 in the ROM's 5-byte float format
    sub end_cell() {
        if crow == 0
            return
        sys.memset(mn.R, 64, 0)
        @(mn.R + cellk.R_STY) = csty
        ubyte t = cellk.T_BLANK
        ubyte[5] v
        sys.memset(&v, 5, 0)
        if has_f and fn > 46 {
            has_f = false               ; formula too long for the X16: keep the cached value
            lossy = true
            if ctype == 3
                ctype = 0
        }
        if has_f {
            t = cellk.T_FORM
            set_text(&ftext, fn)
            if ctype == 3
                @(mn.R + cellk.R_ERR) = mn.err_code(&vtext)
            else if has_v and ctype == 0 and mn.parse_number(&vtext)
                sys.memcopy(mn.result, &v, 5)
        } else if ctype == 1 or (ctype == 2 and has_v) {
            t = cellk.T_TEXT
            if ctype == 1
                set_text(&ttext, tn)
            else
                set_text(&vtext, vn)
        } else if ctype == 5 {
            lossy = true                ; shared strings are not supported (the hub converts them)
            t = cellk.T_TEXT
            set_text(iso:"?", 1)
        } else if ctype == 4 and has_v {
            t = cellk.T_NUM
            if vtext[0] == iso:'1'
                sys.memcopy(&one, &v, 5)
        } else if ctype == 3 and has_v {
            ; plain error value: keep it as text
            t = cellk.T_TEXT
            set_text(&vtext, vn)
        } else if has_v {
            if mn.parse_number(&vtext) {
                t = cellk.T_NUM
                sys.memcopy(mn.result, &v, 5)
            } else {
                t = cellk.T_TEXT
                set_text(&vtext, vn)
            }
        } else if csty == 0
            return                      ; empty, unformatted
        @(mn.R + cellk.R_TYPE) = t
        sys.memcopy(&v, mn.R + cellk.R_VAL, 5)
        if not mn.cput(crow, ccol)
            full = true
    }

    sub set_text(uword s, ubyte n) {
        if n > cellk.MAXLEN {
            n = cellk.MAXLEN
            lossy = true
        }
        @(mn.R + cellk.R_LEN) = n
        sys.memcopy(s, mn.R + cellk.R_TXT, n)
    }
}
