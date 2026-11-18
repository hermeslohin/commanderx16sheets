; numfmt.p8 - number display: General, 0.00, 0.00% and $#,##0.00, fitted to a column width.

%import floats
%import strings
%import cells

numfmt {
    %option ignore_unused

    ubyte[40] out               ; result (iso, 0-terminated)
    ubyte olen
    ubyte[24] t

    sub put(ubyte c) {
        if olen < 38 {
            out[olen] = c
            olen++
            out[olen] = 0
        }
    }

    ; FOUT text of v into t without the leading blank, ".5" -> "0.5", "-.5" -> "-0.5"
    sub fout(float v) {
        uword s = floats.tostr(v)
        ubyte i = 0
        ubyte n = 0
        if @(s) == iso:'-' {
            t[n] = iso:'-'
            n++
            i++
        }
        if @(s + i) == iso:'.' {
            t[n] = iso:'0'
            n++
        }
        while @(s + i) != 0 and n < 22 {
            t[n] = @(s + i)
            n++
            i++
        }
        t[n] = 0
    }

    ; FOUT text of the value in cells.R (for the xlsx writer library: no float parameters cross banks)
    sub fout_rec() {
        float v
        sys.memcopy(&cells.R + cells.R_VAL, &v, 5)
        fout(v)
    }

    sub general(float v) {
        olen = 0
        out[0] = 0
        fout(v)
        ubyte i = 0
        while t[i] != 0 {
            put(t[i])
            i++
        }
    }

    ; fixed 2 decimals; commas: thousands separators; dollar: currency sign
    sub fixed2(float v, bool commas, bool dollar) {
        olen = 0
        out[0] = 0
        float a = abs(v)
        if a >= 9999999.0 {
            general(v)
            return
        }
        fout(floats.round(a * 100.0))
        ubyte n = strings.length(&t)
        ; at least 3 digits: 5 -> 005 -> 0.05
        while n < 3 {
            sys.memcopy(&t, &t + 1, n + 1)
            t[0] = iso:'0'
            n++
        }
        bool neg = v < 0.0 and (n > 3 or t[0] != iso:'0' or t[1] != iso:'0' or t[2] != iso:'0')
        if neg
            put(iso:'-')
        if dollar
            put(iso:'$')
        ubyte ni = n - 2
        ubyte i
        for i in 0 to ni - 1 {
            put(t[i])
            if commas and i != ni - 1 and (ni - 1 - i) % 3 == 0
                put(iso:',')
        }
        put(iso:'.')
        put(t[n - 2])
        put(t[n - 1])
    }

    ; v in format fmt (0 general, 1 0.00, 2 percent, 3 currency), fitted into w characters.
    ; Too wide: General shows fewer decimals, otherwise "###".
    sub format(float v, ubyte fmt, ubyte w) {
        when fmt {
            1 -> fixed2(v, false, false)
            2 -> {
                if abs(v) < 99999.0 {
                    fixed2(v * 100.0, false, false)
                    put(iso:'%')
                } else
                    general(v)
            }
            3 -> fixed2(v, true, true)
            else -> general(v)
        }
        if olen <= w
            return
        if fmt == 0 {
            ; drop decimals that don't fit (rounded): find the '.', no exponent
            ubyte dot = 255
            ubyte i
            for i in 0 to olen - 1 {
                if out[i] == iso:'E'
                    break
                if out[i] == iso:'.'
                    dot = i
            }
            if i == olen and dot != 255 and dot < w {
                ubyte dec = w - dot - 1
                float m = 1.0
                repeat dec
                    m = m * 10.0
                float r = floats.floor(abs(v) * m + 0.5) / m
                if v < 0.0
                    r = -r
                general(r)
                if olen > w {
                    olen = w
                    out[w] = 0
                }
                if out[olen - 1] == iso:'.' {
                    olen--
                    out[olen] = 0
                }
                return
            }
        }
        olen = 0
        repeat w
            put(iso:'#')
    }
}
