; shxw.p8 - SHXW.BIN, RAM bank 59: the XLSX writer of X16 Sheets (see SHEETFMT.md).
; A ZIP with stored (uncompressed) entries, written straight to the SD card: every entry is generated
; twice, first only for its CRC-32 and size (needed in the local header), then for real. The sheet XML
; is generated row by row (used-row bitmap, then cell lookups per column) through main-RAM routines.

%address  $A000
%memtop   $C000
%output   library
%zeropage dontuse

%import syslib
%import diskio
%import conv
%import strings
%import cellk
%import mainsyms_59

main {
    %jmptable (
        xw.setup,           ; $A003  r0 = check -> A
        xw.save_e,          ; $A006  r0 = file name (main RAM) -> A true = ok
    )
    sub start() {
        xw.crc_tables()
    }
}

xw {
    %option ignore_unused

    const ubyte ST_OK = 0
    const ubyte ST_DISK = 1
    const ubyte ST_FORMAT = 2       ; not a zip / not xlsx
    const ubyte ST_COMPRESSED = 3   ; deflated (needs the hub)
    const ubyte ST_NOSHEET = 4
    const ubyte ST_FULL = 5

    ; ---------------- CRC-32 (table driven) ----------------
    ubyte[256] t0
    ubyte[256] t1
    ubyte[256] t2
    ubyte[256] t3
    ubyte[4] crc
    bool tables

    sub crc_tables() {
        if tables
            return
        ubyte n = 0
        repeat 256 {
            ubyte c0 = n
            ubyte c1 = 0
            ubyte c2 = 0
            ubyte c3 = 0
            repeat 8 {
                bool lowbit = (c0 & 1) != 0
                c0 = (c0 >> 1) | (c1 << 7)
                c1 = (c1 >> 1) | (c2 << 7)
                c2 = (c2 >> 1) | (c3 << 7)
                c3 >>= 1
                if lowbit {
                    c0 ^= $20
                    c1 ^= $83
                    c2 ^= $b8
                    c3 ^= $ed
                }
            }
            t0[n] = c0
            t1[n] = c1
            t2[n] = c2
            t3[n] = c3
            n++
        }
        tables = true
    }

    sub crc_init() {
        crc[0] = $ff
        crc[1] = $ff
        crc[2] = $ff
        crc[3] = $ff
    }

    asmsub crc_byte(ubyte b @A) clobbers(X) {
        %asm {{
            eor  p8v_crc
            tax
            lda  p8v_crc+1
            eor  p8v_t0,x
            sta  p8v_crc
            lda  p8v_crc+2
            eor  p8v_t1,x
            sta  p8v_crc+1
            lda  p8v_crc+3
            eor  p8v_t2,x
            sta  p8v_crc+2
            lda  p8v_t3,x
            sta  p8v_crc+3
            rts
        }}
    }

    ; ---------------- output ----------------
    uword obuf = memory("xobuf", 128, 0)
    ubyte on
    bool counting
    bool oerr
    long total                      ; bytes written to the file
    long esize                      ; size of the entry being counted

    sub flush() {
        if on != 0 {
            if not diskio.f_write(obuf, on)
                oerr = true
            on = 0
        }
    }

    ; raw byte to the file (headers)
    sub raw(ubyte c) {
        @(obuf + on) = c
        on++
        total++
        if on == 128
            flush()
    }

    ; content byte: counted (CRC + size) in pass 1, written in pass 2
    sub oc(ubyte c) {
        if counting {
            crc_byte(c)
            esize++
        } else
            raw(c)
    }

    sub os(str s) {
        ubyte i = 0
        while s[i] != 0 {
            oc(s[i])
            i++
        }
    }

    sub on_uw(uword v) {
        uword s = conv.str_uw(v)
        while @(s) != 0 {
            oc(@(s))
            s++
        }
    }

    sub raw16(uword v) {
        raw(lsb(v))
        raw(msb(v))
    }
    sub raw32(long v) {
        raw(@(&v))
        raw(@(&v + 1))
        raw(@(&v + 2))
        raw(@(&v + 3))
    }

    ; ISO-8859-15 -> Unicode for the 8 code points that differ from Latin-1
    sub uni(ubyte c) -> uword {
        when c {
            $a4 -> return $20ac
            $a6 -> return $0160
            $a8 -> return $0161
            $b4 -> return $017d
            $b8 -> return $017e
            $bc -> return $0152
            $bd -> return $0153
            $be -> return $0178
        }
        return c
    }

    ; escaped XML text
    sub ox(uword s, ubyte n) {
        ubyte i
        ubyte c
        if n == 0
            return
        for i in 0 to n - 1 {
            c = @(s + i)
            when c {
                iso:'&' -> os(iso:"&amp;")
                iso:'<' -> os(iso:"&lt;")
                iso:'>' -> os(iso:"&gt;")
                iso:'"' -> os(iso:"&quot;")
                else -> {
                    if c >= 128 {
                        oc(iso:'&')
                        oc(iso:'#')
                        on_uw(uni(c))
                        oc(iso:';')
                    } else if c >= 32 or c == 9
                        oc(c)
                }
            }
        }
    }

    ; ---------------- the entries ----------------
    str n_ct = iso:"[Content_Types].xml"
    str n_rels = iso:"_rels/.rels"
    str n_wb = iso:"xl/workbook.xml"
    str n_wbrels = iso:"xl/_rels/workbook.xml.rels"
    str n_styles = iso:"xl/styles.xml"
    str n_sheet = iso:"xl/worksheets/sheet1.xml"
    uword[] names = [n_ct, n_rels, n_wb, n_wbrels, n_styles, n_sheet]
    str xmlhdr = iso:"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
    str ns_main = iso:"xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\""

    sub gen(ubyte e) {
        os(xmlhdr)
        when e {
            0 -> {
                os(iso:"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">")
                os(iso:"<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>")
                os(iso:"<Default Extension=\"xml\" ContentType=\"application/xml\"/>")
                os(iso:"<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>")
                os(iso:"<Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>")
                os(iso:"<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>")
                os(iso:"</Types>")
            }
            1 -> {
                os(iso:"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">")
                os(iso:"<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>")
                os(iso:"</Relationships>")
            }
            2 -> {
                os(iso:"<workbook ")
                os(ns_main)
                os(iso:" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">")
                os(iso:"<sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>")
            }
            3 -> {
                os(iso:"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">")
                os(iso:"<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>")
                os(iso:"<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>")
                os(iso:"</Relationships>")
            }
            4 -> gen_styles()
            5 -> gen_sheet()
        }
    }

    ubyte[4] fmtid = [0, 2, 10, 164]
    sub gen_styles() {
        os(iso:"<styleSheet ")
        os(ns_main)
        os(iso:"><numFmts count=\"1\"><numFmt numFmtId=\"164\" formatCode=\"&quot;$&quot;#,##0.00\"/></numFmts>")
        os(iso:"<fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/><family val=\"2\"/></font>")
        os(iso:"<font><b/><sz val=\"11\"/><name val=\"Calibri\"/><family val=\"2\"/></font></fonts>")
        os(iso:"<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>")
        os(iso:"<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>")
        os(iso:"<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>")
        os(iso:"<cellXfs count=\"32\">")
        ubyte s
        for s in 0 to 31 {
            ubyte fmt = s >> 3
            ubyte al = (s >> 1) & 3
            os(iso:"<xf numFmtId=\"")
            on_uw(fmtid[fmt])
            os(iso:"\" fontId=\"")
            oc(iso:'0' + (s & 1))
            os(iso:"\" fillId=\"0\" borderId=\"0\" xfId=\"0\"")
            if fmt != 0
                os(iso:" applyNumberFormat=\"1\"")
            if (s & 1) != 0
                os(iso:" applyFont=\"1\"")
            if al != 0 {
                os(iso:" applyAlignment=\"1\"><alignment horizontal=\"")
                when al {
                    1 -> os(iso:"left")
                    2 -> os(iso:"center")
                    else -> os(iso:"right")
                }
                os(iso:"\"/></xf>")
            } else
                os(iso:"/>")
        }
        os(iso:"</cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>")
    }

    ubyte[8] cname
    sub gen_sheet() {
        os(iso:"<worksheet ")
        os(ns_main)
        oc(iso:'>')
        ubyte c = 0
        bool any = false
        repeat 256 {
            if @(mn.colw + c) != cellk.DEFW {
                if not any
                    os(iso:"<cols>")
                any = true
                os(iso:"<col min=\"")
                on_uw(c as uword + 1)
                os(iso:"\" max=\"")
                on_uw(c as uword + 1)
                os(iso:"\" width=\"")
                on_uw(@(mn.colw + c))
                os(iso:"\" customWidth=\"1\"/>")
            }
            c++
        }
        if any
            os(iso:"</cols>")
        os(iso:"<sheetData>")
        uword r
        uword idx
        for r in 1 to mn.used_rows {
            if mn.row_has(r) {
                os(iso:"<row r=\"")
                on_uw(r)
                os(iso:"\">")
                for c in 0 to mn.used_cols {
                    idx = mn.find(r, c)
                    if idx != $ffff {
                        mn.load(idx)
                        gen_cell(r, c)
                    }
                }
                os(iso:"</row>")
            }
        }
        os(iso:"</sheetData></worksheet>")
    }

    sub gen_cell(uword r, ubyte c) {
        ubyte t = @(mn.R + cellk.R_TYPE)
        ubyte s = @(mn.R + cellk.R_STY) & 31
        ubyte n = @(mn.R + cellk.R_LEN)
        os(iso:"<c r=\"")
        void mn.cell_name(r, c, &cname)
        os(&cname)
        oc(iso:'"')
        if s != 0 {
            os(iso:" s=\"")
            on_uw(s)
            oc(iso:'"')
        }
        when t {
            cellk.T_NUM -> {
                os(iso:"><v>")
                mn.fout_rec()
                os(mn.nt)
                os(iso:"</v></c>")
            }
            cellk.T_TEXT -> {
                os(iso:" t=\"inlineStr\"><is><t")
                if n != 0 and (@(mn.R + cellk.R_TXT) == 32 or @(mn.R + cellk.R_TXT + n - 1) == 32)
                    os(iso:" xml:space=\"preserve\"")
                oc(iso:'>')
                ox(mn.R + cellk.R_TXT, n)
                os(iso:"</t></is></c>")
            }
            cellk.T_FORM -> {
                ubyte e = @(mn.R + cellk.R_ERR)
                if e != 0
                    os(iso:" t=\"e\"")
                os(iso:"><f>")
                ox(mn.R + cellk.R_TXT, n)
                os(iso:"</f><v>")
                if e != 0
                    os(mn.err_text(e))
                else {
                    mn.fout_rec()
                    os(mn.nt)
                }
                os(iso:"</v></c>")
            }
            else -> os(iso:"/>")
        }
    }

    sub setup() -> bool {
        return cx16.r0 == mn.CHECK
    }

    sub save_e() -> bool {
        return save(cx16.r0)
    }

    ; ---------------- save ----------------
    long[6] eoff
    long[6] elen
    ubyte[24] ecrc
    uword dtime
    uword ddate

    sub save(uword fname) -> bool {
        crc_tables()
        mn.extent()
        mn.mark_rows()
        ; DOS date/time from the RTC (set by the hub when the link was used)
        cx16.clock_get_date_time()
        ubyte yr = cx16.r0L
        if yr < 80
            yr = 126
        ddate = (((yr - 80) as uword) << 9) | ((cx16.r0H as uword) << 5) | cx16.r1L
        dtime = ((cx16.r1H as uword) << 11) | ((cx16.r2L as uword) << 5) | (cx16.r2H >> 1)
        if cx16.r0H == 0 or cx16.r1L == 0
            ddate = $5c21
        diskio.delete(fname)
        if not diskio.f_open_w(fname)
            return false
        oerr = false
        on = 0
        total = 0
        ubyte e
        for e in 0 to 5 {
            ; pass 1: size + CRC
            counting = true
            crc_init()
            esize = 0
            gen(e)
            elen[e] = esize
            ecrc[e * 4] = crc[0] ^ $ff
            ecrc[e * 4 + 1] = crc[1] ^ $ff
            ecrc[e * 4 + 2] = crc[2] ^ $ff
            ecrc[e * 4 + 3] = crc[3] ^ $ff
            ; local header, then pass 2: the data
            eoff[e] = total
            raw(iso:'P')
            raw(iso:'K')
            raw(3)
            raw(4)
            header_common(e)
            raw16(0)
            os_raw(names[e])
            counting = false
            gen(e)
            if oerr
                break
        }
        long cdstart = total
        for e in 0 to 5 {
            raw(iso:'P')
            raw(iso:'K')
            raw(1)
            raw(2)
            raw16(20)
            header_common(e)
            raw16(0)                ; extra
            raw16(0)                ; comment
            raw16(0)                ; disk
            raw16(0)                ; internal attributes
            raw32(0)                ; external attributes
            raw32(eoff[e])
            os_raw(names[e])
        }
        long cdsize = total - cdstart
        raw(iso:'P')
        raw(iso:'K')
        raw(5)
        raw(6)
        raw32(0)                    ; disk numbers
        raw16(6)
        raw16(6)
        raw32(cdsize)
        raw32(cdstart)
        raw16(0)
        flush()
        diskio.f_close_w()
        return not oerr
    }

    ; version needed .. name length (shared by local and central headers)
    sub header_common(ubyte e) {
        raw16(20)
        raw16(0)                    ; flags
        raw16(0)                    ; stored
        raw16(dtime)
        raw16(ddate)
        raw(ecrc[e * 4])
        raw(ecrc[e * 4 + 1])
        raw(ecrc[e * 4 + 2])
        raw(ecrc[e * 4 + 3])
        raw32(elen[e])
        raw32(elen[e])
        raw16(strings.length(names[e]))
    }

    sub os_raw(uword s) {
        while @(s) != 0 {
            raw(@(s))
            s++
        }
    }
}
