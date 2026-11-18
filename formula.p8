; formula.p8 - formula evaluation (iterative shunting-yard: Prog8 subroutines are not re-entrant),
; reference rewriting (copy/paste, insert/delete rows and columns) and recalculation.
;
; Syntax (Excel compatible subset): numbers, A1 / $A$1 refs, A1:B9 ranges as function arguments,
; + - * / ^, unary -, postfix %, = <> < > <= >= (give 1/0), parentheses, TRUE/FALSE and
; SUM AVERAGE MIN MAX COUNT PRODUCT ABS SQRT INT ROUND IF.
;
; The ROM float routines jump into BASIC on overflow / division by zero / bad arguments, which
; would kill the program, so every operation that could fail is checked first (exponent bytes).

%import syslib
%import floats
%import conv
%import strings
%import cells

formula {
    %option ignore_unused

    const ubyte E_DIV0 = 1
    const ubyte E_VALUE = 2
    const ubyte E_REF = 3
    const ubyte E_NAME = 4
    const ubyte E_NUM = 5
    const ubyte E_NA = 6
    const ubyte E_CIRC = 7

    str err_div0 = iso:"#DIV/0!"
    str err_value = iso:"#VALUE!"
    str err_ref = iso:"#REF!"
    str err_name = iso:"#NAME?"
    str err_num = iso:"#NUM!"
    str err_na = iso:"#N/A"

    sub err_text(ubyte e) -> str {
        when e {
            E_DIV0 -> return err_div0
            E_REF -> return err_ref
            E_NAME -> return err_name
            E_NUM -> return err_num
            E_NA -> return err_na
        }
        return err_value
    }

    ; error string (as in an xlsx <v>) -> code
    sub err_code(uword s) -> ubyte {
        ubyte e
        for e in 1 to 6 {
            if strings.compare(s, err_text(e)) == 0
                return e
        }
        return E_VALUE
    }

    const ubyte OP_LP = 1
    const ubyte OP_FN = 2
    const ubyte OP_NEG = 3
    const ubyte OP_ADD = 10
    const ubyte OP_SUB = 11
    const ubyte OP_MUL = 12
    const ubyte OP_DIV = 13
    const ubyte OP_POW = 14
    const ubyte OP_EQ = 15
    const ubyte OP_NE = 16
    const ubyte OP_LT = 17
    const ubyte OP_GT = 18
    const ubyte OP_LE = 19
    const ubyte OP_GE = 20

    const ubyte F_SUM = 1
    const ubyte F_AVERAGE = 2
    const ubyte F_MIN = 3
    const ubyte F_MAX = 4
    const ubyte F_COUNT = 5
    const ubyte F_PRODUCT = 6
    const ubyte F_ABS = 7
    const ubyte F_SQRT = 8
    const ubyte F_INT = 9
    const ubyte F_ROUND = 10
    const ubyte F_IF = 11
    const ubyte NFUNCS = 11
    uword[] @shared @nosplit fn_names = [iso:"SUM", iso:"AVERAGE", iso:"MIN", iso:"MAX", iso:"COUNT", iso:"PRODUCT",
                        iso:"ABS", iso:"SQRT", iso:"INT", iso:"ROUND", iso:"IF"]

    ubyte[64] fb                ; formula text being evaluated / rewritten
    ubyte[64] ob                ; rewrite output
    ubyte oblen
    ubyte[24] numb

    float[24] vs
    ubyte vsp
    ubyte[24] ops
    ubyte osp
    const ubyte FDEPTH = 8
    ubyte[FDEPTH] fcode
    ubyte[FDEPTH] fargc
    ubyte[FDEPTH] fvbase
    bool[FDEPTH] fconsumed
    bool[FDEPTH] fhasrange
    bool[FDEPTH] fprodov
    uword[FDEPTH] fcnt
    float[FDEPTH] fsum
    float[FDEPTH] fmin
    float[FDEPTH] fmax
    float[FDEPTH] fprod
    float[FDEPTH] fa1
    float[FDEPTH] fa2
    float[FDEPTH] fa3
    ubyte fd                    ; number of open function frames

    ubyte everr
    float result
    ubyte fp

    ; ---------------- character helpers ----------------
    sub upc(ubyte c) -> ubyte {
        if c >= iso:'a' and c <= iso:'z'
            return c - 32
        return c
    }
    sub is_letter(ubyte c) -> bool {
        c = upc(c)
        return c >= iso:'A' and c <= iso:'Z'
    }
    sub is_digit(ubyte c) -> bool {
        return c >= iso:'0' and c <= iso:'9'
    }
    sub is_ident(ubyte c) -> bool {
        return is_letter(c) or is_digit(c) or c == iso:'_' or c == iso:'.'
    }
    sub skip_sp() {
        while fb[fp] == 32
            fp++
    }

    ; ---------------- cell references ----------------
    uword ref_row
    ubyte ref_col
    bool ref_absr
    bool ref_absc
    ubyte ref_end

    ; parse a reference in fb at p: [$]COL[$]ROW, COL = A..IV, ROW = 1..9999
    sub parse_ref(ubyte p) -> bool {
        ref_absc = false
        ref_absr = false
        if fb[p] == iso:'$' {
            ref_absc = true
            p++
        }
        if not is_letter(fb[p])
            return false
        uword col = upc(fb[p]) - iso:'A'
        p++
        if is_letter(fb[p]) {
            col = (col + 1) * 26 + (upc(fb[p]) - iso:'A')
            p++
            if is_letter(fb[p]) or col > 255
                return false
        }
        if fb[p] == iso:'$' {
            ref_absr = true
            p++
        }
        if not is_digit(fb[p])
            return false
        uword row = 0
        ubyte nd = 0
        while is_digit(fb[p]) {
            row = row * 10 + (fb[p] - iso:'0')
            p++
            nd++
            if nd > 4
                return false
        }
        if row == 0 or row > cells.MAXROW or is_ident(fb[p]) or fb[p] == iso:'('
            return false
        ref_row = row
        ref_col = lsb(col)
        ref_end = p
        return true
    }

    ; column letters of c into dst, returns the length (1 or 2)
    sub col_name(ubyte c, uword dst) -> ubyte {
        if c < 26 {
            @(dst) = iso:'A' + c
            return 1
        }
        @(dst) = iso:'A' + c / 26 - 1
        @(dst + 1) = iso:'A' + c % 26
        return 2
    }

    ; "B12" style name of a cell into dst (0-terminated), returns the length
    sub cell_name(uword row, ubyte col, uword dst) -> ubyte {
        ubyte n = col_name(col, dst)
        uword s = conv.str_uw(row)
        ubyte i = 0
        while @(s + i) != 0 {
            @(dst + n) = @(s + i)
            n++
            i++
        }
        @(dst + n) = 0
        return n
    }

    ; ---------------- float safety ----------------
    float fa
    float fbv
    sub expo(float f) -> ubyte {
        return @(&f)
    }

    ; ---------------- stacks ----------------
    sub vpush(float v) {
        if vsp >= 24 {
            if everr == 0
                everr = E_VALUE
            return
        }
        vs[vsp] = v
        vsp++
    }
    sub vpop() -> float {
        if vsp == 0 {
            if everr == 0
                everr = E_VALUE
            return 0.0
        }
        vsp--
        return vs[vsp]
    }

    sub prec(ubyte op) -> ubyte {
        if op >= OP_EQ
            return 1
        when op {
            OP_ADD, OP_SUB -> return 2
            OP_MUL, OP_DIV -> return 3
            OP_POW -> return 4
            OP_NEG -> return 5
        }
        return 0
    }

    sub apply(ubyte op) {
        if op == OP_NEG {
            fa = vpop()
            vpush(-fa)
            return
        }
        fbv = vpop()
        fa = vpop()
        if everr != 0
            return
        ubyte ea = expo(fa)
        ubyte eb = expo(fbv)
        when op {
            OP_ADD, OP_SUB -> {
                if ea >= 254 or eb >= 254 {
                    everr = E_NUM
                    return
                }
                if op == OP_ADD
                    vpush(fa + fbv)
                else
                    vpush(fa - fbv)
            }
            OP_MUL -> {
                if ea != 0 and eb != 0 and (ea as uword) + eb >= 128 + 254 {
                    everr = E_NUM
                    return
                }
                vpush(fa * fbv)
            }
            OP_DIV -> {
                if eb == 0 {
                    everr = E_DIV0
                    return
                }
                if ea != 0 and (ea as uword) + 128 >= (eb as uword) + 254 {
                    everr = E_NUM
                    return
                }
                vpush(fa / fbv)
            }
            OP_POW -> vpush(power(fa, fbv))
            OP_EQ -> vpush(bool2f(fa == fbv))
            OP_NE -> vpush(bool2f(fa != fbv))
            OP_LT -> vpush(bool2f(fa < fbv))
            OP_GT -> vpush(bool2f(fa > fbv))
            OP_LE -> vpush(bool2f(fa <= fbv))
            OP_GE -> vpush(bool2f(fa >= fbv))
        }
    }

    sub bool2f(bool b) -> float {
        if b
            return 1.0
        return 0.0
    }

    float pw_t
    sub power(float a, float b) -> float {
        if b == 0.0
            return 1.0
        if a == 0.0 {
            if b < 0.0
                everr = E_DIV0
            return 0.0
        }
        bool neg = false
        if a < 0.0 {
            if floats.floor(b) != b {
                everr = E_NUM
                return 0.0
            }
            a = -a
            ; odd integer exponent keeps the sign
            if abs(b) < 1000000.0 {
                pw_t = b / 2.0
                neg = floats.floor(pw_t) != pw_t
            }
        }
        if floats.floor(b) == b and abs(b) <= 64.0 {
            ; small integer power: exact repeated multiplication
            ubyte n = abs(b) as ubyte
            float r = 1.0
            repeat n {
                if expo(r) + expo(a) >= 128 + 254 {
                    everr = E_NUM
                    return 0.0
                }
                r = r * a
            }
            if b < 0.0
                r = 1.0 / r
            if neg
                return -r
            return r
        }
        pw_t = b * floats.ln(a)
        if pw_t > 87.0 {
            everr = E_NUM
            return 0.0
        }
        if pw_t < -87.0
            return 0.0
        pw_t = floats.pow(a, b)
        if neg
            return -pw_t
        return pw_t
    }

    ; ---------------- function frames ----------------
    sub setpos(ubyte n, float v) {
        when n {
            0 -> fa1[fd - 1] = v
            1 -> fa2[fd - 1] = v
            2 -> fa3[fd - 1] = v
        }
    }

    ; one value into the open function: only what that function needs (ROM float calls are slow)
    sub feed(float v) {
        ubyte k = fd - 1
        ubyte code = fcode[k]
        if fcnt[k] == 0 {
            fmin[k] = v
            fmax[k] = v
            fprod[k] = v
            fsum[k] = v
        } else when code {
            F_SUM, F_AVERAGE -> {
                if expo(fsum[k]) >= 254 or expo(v) >= 254
                    everr = E_NUM
                else
                    fsum[k] = fsum[k] + v
            }
            F_MIN -> {
                if v < fmin[k]
                    fmin[k] = v
            }
            F_MAX -> {
                if v > fmax[k]
                    fmax[k] = v
            }
            F_PRODUCT -> {
                ubyte ea = expo(fprod[k])
                ubyte eb = expo(v)
                if ea != 0 and eb != 0 and (ea as uword) + eb >= 128 + 254
                    fprodov[k] = true
                else
                    fprod[k] = fprod[k] * v
            }
        }
        fcnt[k]++
    }

    sub feed_cell_value() {
        if cells.lv_err != 0 {
            if everr == 0
                everr = cells.lv_err
            return
        }
        if cells.lv_type == cells.T_NUM or cells.lv_type == cells.T_FORM
            feed(cells.lv)
    }

    ; a range (or a single reference that is a whole function argument) fed into the open frame
    sub feed_range(uword r1, ubyte c1, uword r2, ubyte c2) {
        uword t
        if r1 > r2 {
            t = r1
            r1 = r2
            r2 = t
        }
        if c1 > c2 {
            ubyte tc = c1
            c1 = c2
            c2 = tc
        }
        ubyte k = fd - 1
        fconsumed[k] = true
        if r1 == r2 and c1 == c2 {
            cells.lookup(r1, c1)
            setpos(fargc[k], cells.lv)
            feed_cell_value()
            return
        }
        fhasrange[k] = true
        uword rows = r2 - r1 + 1
        uword ncols = c2 - c1 + 1
        uword r
        ubyte c
        if rows <= 2000 and rows * ncols <= cells.nused / 4 {
            for r in r1 to r2 {
                for c in c1 to c2 {
                    cells.lookup(r, c)
                    feed_cell_value()
                }
            }
            return
        }
        ; big range, few cells: walk the record pool instead
        uword i
        uword rp
        ubyte ty
        if cells.ntop == 0
            return
        for i in 0 to cells.ntop - 1 {
            rp = cells.rec_ptr(i)
            ty = @(rp + cells.R_TYPE)
            if ty == cells.T_NUM or ty == cells.T_FORM {
                r = peekw(rp)
                c = @(rp + cells.R_COL)
                if r >= r1 and r <= r2 and c >= c1 and c <= c2 {
                    cells.lv_type = ty
                    cells.lv_err = @(rp + cells.R_ERR)
                    sys.memcopy(rp + cells.R_VAL, &cells.lv, 5)
                    feed_cell_value()
                }
            }
        }
    }

    sub open_frame(ubyte code) {
        if fd >= FDEPTH or osp >= 24 {
            everr = E_VALUE
            return
        }
        fcode[fd] = code
        fargc[fd] = 0
        fvbase[fd] = vsp
        fconsumed[fd] = false
        fhasrange[fd] = false
        fprodov[fd] = false
        fcnt[fd] = 0
        fsum[fd] = 0.0
        fmin[fd] = 0.0
        fmax[fd] = 0.0
        fprod[fd] = 0.0
        fa1[fd] = 0.0
        fa2[fd] = 0.0
        fa3[fd] = 0.0
        fd++
        ops[osp] = OP_FN
        osp++
    }

    sub finish_arg() {
        ubyte k = fd - 1
        if fconsumed[k] {
            fconsumed[k] = false
        } else {
            float v = vpop()
            setpos(fargc[k], v)
            feed(v)
        }
        fargc[k]++
    }

    sub close_frame() {
        ubyte k = fd - 1
        ubyte n = fargc[k]
        float r = 0.0
        float x = fa1[k]
        bool positional = fcode[k] >= F_ABS
        if positional and fhasrange[k]
            everr = E_VALUE
        when fcode[k] {
            F_SUM -> r = fsum[k]
            F_AVERAGE -> {
                if fcnt[k] == 0
                    everr = E_DIV0
                else
                    r = fsum[k] / (fcnt[k] as float)
            }
            F_MIN -> r = fmin[k]
            F_MAX -> r = fmax[k]
            F_COUNT -> r = fcnt[k] as float
            F_PRODUCT -> {
                if fprodov[k]
                    everr = E_NUM
                r = fprod[k]
            }
            F_ABS -> {
                if n != 1
                    everr = E_VALUE
                r = abs(x)
            }
            F_SQRT -> {
                if n != 1
                    everr = E_VALUE
                if x < 0.0
                    everr = E_NUM
                else
                    r = sqrt(x)
            }
            F_INT -> {
                if n != 1
                    everr = E_VALUE
                r = floats.floor(x)
            }
            F_ROUND -> {
                if n < 1 or n > 2
                    everr = E_VALUE
                float d = fa2[k]
                if d > 9.0
                    d = 9.0
                if d < -9.0
                    d = -9.0
                byte nd = d as byte
                float m = 1.0
                repeat abs(nd)
                    m = m * 10.0
                float ax = abs(x)
                if expo(ax) < 128 + 100 {
                    if nd >= 0
                        r = floats.floor(ax * m + 0.5) / m
                    else
                        r = floats.floor(ax / m + 0.5) * m
                } else
                    r = ax
                if x < 0.0
                    r = -r
            }
            F_IF -> {
                if n < 2 or n > 3
                    everr = E_VALUE
                if x != 0.0
                    r = fa2[k]
                else
                    r = fa3[k]
            }
        }
        vsp = fvbase[k]
        fd--
        vpush(r)
    }

    ; pop operators down to (not including) the nearest '(' or function marker; returns that marker or 0
    sub reduce_to_mark() -> ubyte {
        while osp != 0 {
            ubyte op = ops[osp - 1]
            if op == OP_LP or op == OP_FN
                return op
            osp--
            apply(op)
            if everr != 0
                return 0
        }
        return 0
    }

    ; ---------------- number scanning ----------------
    ; scans a number at fp into numb; false if it is too large for the ROM float routines
    sub scan_number() -> bool {
        ubyte n = 0
        ubyte idig = 0
        bool dot = false
        bool lead = true
        while (is_digit(fb[fp]) or (fb[fp] == iso:'.' and not dot)) and n < 20 {
            if fb[fp] == iso:'.'
                dot = true
            else if not dot {
                if fb[fp] != iso:'0' or not lead {
                    idig++
                    lead = false
                }
            }
            numb[n] = fb[fp]
            n++
            fp++
        }
        byte ex = 0
        if upc(fb[fp]) == iso:'E' and (is_digit(fb[fp + 1]) or ((fb[fp + 1] == iso:'-' or fb[fp + 1] == iso:'+') and is_digit(fb[fp + 2]))) {
            numb[n] = iso:'E'
            n++
            fp++
            bool eneg = false
            if fb[fp] == iso:'-' or fb[fp] == iso:'+' {
                eneg = fb[fp] == iso:'-'
                numb[n] = fb[fp]
                n++
                fp++
            }
            ubyte ev = 0
            while is_digit(fb[fp]) {
                if ev < 100
                    ev = ev * 10 + (fb[fp] - iso:'0')
                if n < 23 {
                    numb[n] = fb[fp]
                    n++
                }
                fp++
            }
            if ev > 99
                ev = 99
            ex = ev as byte
            if eneg
                ex = -ex
        }
        numb[n] = 0
        if is_ident(fb[fp]) and fb[fp] != iso:'.'
            return false
        if (idig as byte) + ex > 37
            return false
        if ex < -37 {
            numb[0] = iso:'0'
            numb[1] = 0
        }
        return true
    }

    ; is the whole string a plain number? (used for typed input) -> result
    sub parse_number(uword s) -> bool {
        ubyte i = 0
        while @(s + i) != 0 and i < 50 {
            fb[i] = @(s + i)
            i++
        }
        fb[i] = 0
        fp = 0
        skip_sp()
        bool neg = false
        if fb[fp] == iso:'-' or fb[fp] == iso:'+' {
            neg = fb[fp] == iso:'-'
            fp++
        }
        if not is_digit(fb[fp]) and not (fb[fp] == iso:'.' and is_digit(fb[fp + 1]))
            return false
        if not scan_number()
            return false
        skip_sp()
        if fb[fp] != 0
            return false
        result = floats.parse(&numb)
        if neg
            result = -result
        return true
    }

    ; ---------------- evaluation ----------------
    ; evaluate formula text (without '=') -> result / everr
    sub eval(uword text, ubyte tl) {
        if tl > 60
            tl = 60
        sys.memcopy(text, &fb, tl)
        fb[tl] = 0
        fb[tl + 1] = 0
        fb[tl + 2] = 0
        fp = 0
        vsp = 0
        osp = 0
        fd = 0
        everr = 0
        result = 0.0
        bool operand = true
        ubyte c
        ubyte op
        while everr == 0 {
            skip_sp()
            c = fb[fp]
            if operand {
                if c == 0 {
                    everr = E_NAME
                    break
                }
                if is_digit(c) or (c == iso:'.' and is_digit(fb[fp + 1])) {
                    if not scan_number() {
                        everr = E_NUM
                        break
                    }
                    vpush(floats.parse(&numb))
                    operand = false
                } else if c == iso:'(' {
                    fp++
                    if osp >= 24 {
                        everr = E_VALUE
                        break
                    }
                    ops[osp] = OP_LP
                    osp++
                } else if c == iso:'-' {
                    fp++
                    if osp >= 24 {
                        everr = E_VALUE
                        break
                    }
                    ops[osp] = OP_NEG
                    osp++
                } else if c == iso:'+' {
                    fp++
                } else if c == iso:'#' {
                    ; an error literal such as #REF! left behind by a deleted row
                    everr = E_REF
                    break
                } else if c == iso:')' and osp != 0 and ops[osp - 1] == OP_FN and fd != 0 and fargc[fd - 1] == 0 and vsp == fvbase[fd - 1] {
                    fp++
                    osp--
                    close_frame()
                    operand = false
                } else if is_letter(c) or c == iso:'$' {
                    operand = not operand_name()
                } else {
                    everr = E_NAME
                    break
                }
            } else {
                if c == 0
                    break
                fp++
                op = 0
                when c {
                    iso:'+' -> op = OP_ADD
                    iso:'-' -> op = OP_SUB
                    iso:'*' -> op = OP_MUL
                    iso:'/' -> op = OP_DIV
                    iso:'^' -> op = OP_POW
                    iso:'=' -> op = OP_EQ
                    iso:'<' -> {
                        op = OP_LT
                        if fb[fp] == iso:'=' {
                            op = OP_LE
                            fp++
                        } else if fb[fp] == iso:'>' {
                            op = OP_NE
                            fp++
                        }
                    }
                    iso:'>' -> {
                        op = OP_GT
                        if fb[fp] == iso:'=' {
                            op = OP_GE
                            fp++
                        }
                    }
                    iso:'%' -> {
                        vpush(vpop() / 100.0)
                        continue
                    }
                    iso:')' -> {
                        ubyte m = reduce_to_mark()
                        if everr != 0
                            break
                        if m == OP_LP {
                            osp--
                        } else if m == OP_FN {
                            osp--
                            finish_arg()
                            close_frame()
                        } else {
                            everr = E_NAME
                        }
                        continue
                    }
                    iso:',' -> {
                        if reduce_to_mark() != OP_FN {
                            if everr == 0
                                everr = E_NAME
                            break
                        }
                        finish_arg()
                        operand = true
                        continue
                    }
                }
                if op == 0 {
                    everr = E_NAME
                    break
                }
                ubyte p = prec(op)
                while osp != 0 {
                    ubyte top = ops[osp - 1]
                    ubyte tp = prec(top)
                    if tp == 0 or tp < p
                        break
                    osp--
                    apply(top)
                }
                if osp >= 24 {
                    everr = E_VALUE
                    break
                }
                ops[osp] = op
                osp++
                operand = true
            }
        }
        if everr == 0 {
            while osp != 0 {
                osp--
                op = ops[osp]
                if op == OP_LP or op == OP_FN {
                    everr = E_NAME
                    break
                }
                apply(op)
            }
        }
        if everr == 0 and vsp != 1
            everr = E_NAME
        if everr == 0
            result = vs[0]
    }

    ; a name in operand position: function call, TRUE/FALSE, reference or range.
    ; true = an operand is complete; false = a function was opened (an argument comes next)
    sub operand_name() -> bool {
        ubyte s = fp
        ubyte n = 0
        while is_letter(fb[fp + n])
            n++
        if n != 0 and fb[fp + n] == iso:'(' {
            ubyte k
            for k in 0 to NFUNCS - 1 {
                if name_is(s, n, fn_names[k]) {
                    fp += n + 1
                    open_frame(k + 1)
                    return false
                }
            }
            everr = E_NAME
            return true
        }
        if n != 0 and not is_digit(fb[fp + n]) and fb[fp + n] != iso:'$' {
            if name_is(s, n, iso:"TRUE") {
                fp += n
                vpush(1.0)
                return true
            }
            if name_is(s, n, iso:"FALSE") {
                fp += n
                vpush(0.0)
                return true
            }
        }
        if not parse_ref(fp) {
            everr = E_NAME
            return true
        }
        uword r1 = ref_row
        ubyte c1 = ref_col
        fp = ref_end
        bool whole_arg = false
        if fb[fp] == iso:':' {
            if not parse_ref(fp + 1) {
                everr = E_NAME
                return true
            }
            fp = ref_end
            skip_sp()
            if osp == 0 or ops[osp - 1] != OP_FN or (fb[fp] != iso:',' and fb[fp] != iso:')') {
                everr = E_VALUE                 ; a range only makes sense as a function argument
                return true
            }
            feed_range(r1, c1, ref_row, ref_col)
            return true
        }
        ubyte q = fp
        while fb[q] == 32
            q++
        if osp != 0 and ops[osp - 1] == OP_FN and vsp == fvbase[fd - 1] and (fb[q] == iso:',' or fb[q] == iso:')') {
            feed_range(r1, c1, r1, c1)          ; SUM(A1): text/empty cells are skipped, not an error
            return true
        }
        cells.lookup(r1, c1)
        if cells.lv_err != 0 {
            everr = cells.lv_err
            return true
        }
        if cells.lv_type == cells.T_TEXT {
            everr = E_VALUE
            return true
        }
        vpush(cells.lv)
        return true
    }

    sub name_is(ubyte s, ubyte n, str name) -> bool {
        ubyte i
        for i in 0 to n - 1 {
            if upc(fb[s + i]) != name[i]
                return false
        }
        return name[n] == 0
    }

    ; ---------------- recalculation ----------------
    ; Every formula record keeps the bounding box of the cells it refers to (R_BB.., computed here).
    ; After a change only formulas whose box overlaps the changed cells are evaluated again, round
    ; after round, until nothing changes (25 rounds = circular reference).
    const ubyte MAXFLEN = 46
    const ubyte R_BB = 58               ; uword r1, uword r2, ubyte c1, ubyte c2
    uword bb_r1                         ; 0 = no references
    uword bb_r2
    ubyte bb_c1
    ubyte bb_c2

    sub bb_add(uword r, ubyte c) {
        if bb_r1 == 0 {
            bb_r1 = r
            bb_r2 = r
            bb_c1 = c
            bb_c2 = c
            return
        }
        if r < bb_r1
            bb_r1 = r
        if r > bb_r2
            bb_r2 = r
        if c < bb_c1
            bb_c1 = c
        if c > bb_c2
            bb_c2 = c
    }

    ; bounding box of all references in a formula -> bb_*
    sub bbox(uword text, ubyte tl) {
        if tl > 60
            tl = 60
        sys.memcopy(text, &fb, tl)
        fb[tl] = 0
        fb[tl + 1] = 0
        bb_r1 = 0
        bool inq = false
        ubyte p = 0
        ubyte c
        while p < tl {
            c = fb[p]
            if c == iso:'"'
                inq = not inq
            else if not inq and (is_letter(c) or c == iso:'$') and (p == 0 or not is_ident(fb[p - 1])) {
                if parse_ref(p) {
                    bb_add(ref_row, ref_col)
                    p = ref_end
                    if fb[p] == iso:':' and parse_ref(p + 1) {
                        bb_add(ref_row, ref_col)
                        p = ref_end
                    }
                    continue
                }
                while is_ident(fb[p])
                    p++
                continue
            }
            p++
        }
    }

    ; changed area of the current / next round
    uword d_r1
    uword d_r2
    ubyte d_c1
    ubyte d_c2
    uword n_r1                          ; 0 = nothing changed
    uword n_r2
    ubyte n_c1
    ubyte n_c2

    sub n_add(uword r, ubyte c) {
        if n_r1 == 0 {
            n_r1 = r
            n_r2 = r
            n_c1 = c
            n_c2 = c
            return
        }
        if r < n_r1
            n_r1 = r
        if r > n_r2
            n_r2 = r
        if c < n_c1
            n_c1 = c
        if c > n_c2
            n_c2 = c
    }

    ubyte[64] rt
    float oldv
    ubyte passes
    bool circular
    uword evals

    ; evaluate formula record i (bank pointer rp), store the result; true if the value changed
    sub eval_rec(uword i, uword rp) -> bool {
        ubyte tl = @(rp + cells.R_LEN)
        sys.memcopy(rp + cells.R_TXT, &rt, tl)
        sys.memcopy(rp + cells.R_VAL, &oldv, 5)
        ubyte olderr = @(rp + cells.R_ERR)
        eval(&rt, tl)
        evals++
        if everr != 0
            result = 0.0
        rp = cells.rec_ptr(i)
        if everr != olderr or result != oldv {
            @(rp + cells.R_ERR) = everr
            sys.memcopy(&result, rp + cells.R_VAL, 5)
            return true
        }
        return false
    }

    ; full recalculation: boxes for every formula, evaluate all once, then follow the changes
    sub recalc() {
        uword i
        uword rp
        circular = false
        passes = 1
        evals = 0
        n_r1 = 0
        if cells.ntop == 0
            return
        for i in 0 to cells.ntop - 1 {
            rp = cells.rec_ptr(i)
            if @(rp + cells.R_TYPE) == cells.T_FORM {
                store_bbox(i, rp)
                rp = cells.rec_ptr(i)
                if eval_rec(i, rp) {
                    rp = cells.rec_ptr(i)
                    n_add(peekw(rp), @(rp + cells.R_COL))
                }
            }
        }
        rounds()
    }

    sub store_bbox(uword i, uword rp) {
        bbox(rp + cells.R_TXT, @(rp + cells.R_LEN))
        rp = cells.rec_ptr(i)
        pokew(rp + R_BB, bb_r1)
        pokew(rp + R_BB + 2, bb_r2)
        @(rp + R_BB + 4) = bb_c1
        @(rp + R_BB + 5) = bb_c2
    }

    ; after cells r1..r2 / c1..c2 changed (an edit): only what depends on them
    sub recalc_area(uword r1, ubyte c1, uword r2, ubyte c2) {
        circular = false
        passes = 0
        evals = 0
        n_r1 = r1
        n_r2 = r2
        n_c1 = c1
        n_c2 = c2
        ; a formula typed into the area itself: new box, evaluate it first
        uword i
        uword rp
        uword r
        ubyte c
        if cells.ntop == 0
            return
        for i in 0 to cells.ntop - 1 {
            rp = cells.rec_ptr(i)
            if @(rp + cells.R_TYPE) == cells.T_FORM {
                r = peekw(rp)
                c = @(rp + cells.R_COL)
                if r >= r1 and r <= r2 and c >= c1 and c <= c2 {
                    store_bbox(i, rp)
                    void eval_rec(i, cells.rec_ptr(i))
                }
            }
        }
        rounds()
    }

    sub rounds() {
        uword i
        uword rp
        while n_r1 != 0 {
            if passes >= 25 {
                circular = true
                return
            }
            passes++
            d_r1 = n_r1
            d_r2 = n_r2
            d_c1 = n_c1
            d_c2 = n_c2
            n_r1 = 0
            for i in 0 to cells.ntop - 1 {
                rp = cells.rec_ptr(i)
                if @(rp + cells.R_TYPE) == cells.T_FORM {
                    uword b1 = peekw(rp + R_BB)
                    if b1 != 0 and b1 <= d_r2 and peekw(rp + R_BB + 2) >= d_r1 and @(rp + R_BB + 4) <= d_c2 and @(rp + R_BB + 5) >= d_c1 {
                        if eval_rec(i, rp) {
                            rp = cells.rec_ptr(i)
                            n_add(peekw(rp), @(rp + cells.R_COL))
                        }
                    }
                }
            }
        }
    }

    ; ---------------- reference rewriting ----------------
    const ubyte ADJ_MOVE = 1
    const ubyte ADJ_ROWS = 2
    const ubyte ADJ_COLS = 3
    ubyte @shared adj_mode
    word @shared adj_dr
    word @shared adj_dc
    uword @shared adj_at
    word @shared adj_n                  ; > 0 inserted, < 0 deleted
    bool adj_bad

    sub adj_row(uword r, bool absr) -> uword {
        word v = r as word
        if adj_mode == ADJ_MOVE {
            if not absr
                v += adj_dr
        } else if adj_mode == ADJ_ROWS {
            if r >= adj_at {
                if adj_n < 0 and r < adj_at + ((-adj_n) as uword) {
                    adj_bad = true
                    return 1
                }
                v += adj_n
            }
        }
        if v < 1 or v > (cells.MAXROW as word) {
            adj_bad = true
            return 1
        }
        return v as uword
    }

    sub adj_col(ubyte c, bool absc) -> ubyte {
        word v = c as word
        if adj_mode == ADJ_MOVE {
            if not absc
                v += adj_dc
        } else if adj_mode == ADJ_COLS {
            if c >= adj_at {
                if adj_n < 0 and (c as uword) < adj_at + ((-adj_n) as uword) {
                    adj_bad = true
                    return 0
                }
                v += adj_n
            }
        }
        if v < 0 or v > 255 {
            adj_bad = true
            return 0
        }
        return lsb(v)
    }

    ; range end points when rows/columns are deleted: shrink instead of #REF!
    sub adj_span(uword s, uword e, uword lim) -> bool {
        ; result in span_s / span_e; false = the whole range was deleted
        uword d = (-adj_n) as uword
        if s >= adj_at and e < adj_at + d
            return false
        if s >= adj_at + d
            span_s = s - d
        else if s >= adj_at
            span_s = adj_at
        else
            span_s = s
        if e >= adj_at + d
            span_e = e - d
        else if e >= adj_at
            span_e = adj_at - 1
        else
            span_e = e
        return true
    }
    uword span_s
    uword span_e

    sub emit(ubyte c) {
        if oblen < 60 {
            ob[oblen] = c
            oblen++
        } else
            adj_bad = true
    }

    sub emit_ref(uword r, ubyte c, bool absr, bool absc) {
        ubyte[8] t
        if absc
            emit(iso:'$')
        ubyte n = col_name(c, &t)
        emit(t[0])
        if n == 2
            emit(t[1])
        if absr
            emit(iso:'$')
        uword s = conv.str_uw(r)
        while @(s) != 0 {
            emit(@(s))
            s++
        }
    }

    sub emit_s(str s) {
        ubyte i = 0
        while s[i] != 0 {
            emit(s[i])
            i++
        }
    }

    ; rewrite the references of a formula (text, tl) -> ob/oblen. false if the result is too long.
    sub adjust(uword text, ubyte tl) -> bool {
        if tl > 60
            tl = 60
        sys.memcopy(text, &fb, tl)
        fb[tl] = 0
        fb[tl + 1] = 0
        oblen = 0
        bool inq = false
        bool toolong = false
        ubyte p = 0
        ubyte c
        while p < tl {
            c = fb[p]
            if c == iso:'"' {
                inq = not inq
                emit(c)
                p++
                continue
            }
            if not inq and (is_letter(c) or c == iso:'$') and (p == 0 or not is_ident(fb[p - 1])) {
                if parse_ref(p) {
                    uword r1 = ref_row
                    ubyte c1 = ref_col
                    bool ar1 = ref_absr
                    bool ac1 = ref_absc
                    ubyte q = ref_end
                    adj_bad = false
                    if fb[q] == iso:':' and parse_ref(q + 1) {
                        uword r2 = ref_row
                        ubyte c2 = ref_col
                        bool ar2 = ref_absr
                        bool ac2 = ref_absc
                        q = ref_end
                        if adj_mode == ADJ_ROWS and adj_n < 0 {
                            if adj_span(r1, r2, cells.MAXROW) {
                                r1 = span_s
                                r2 = span_e
                            } else
                                adj_bad = true
                        } else if adj_mode == ADJ_COLS and adj_n < 0 {
                            if adj_span(c1, c2, 255) {
                                c1 = lsb(span_s)
                                c2 = lsb(span_e)
                            } else
                                adj_bad = true
                        } else {
                            r1 = adj_row(r1, ar1)
                            c1 = adj_col(c1, ac1)
                            r2 = adj_row(r2, ar2)
                            c2 = adj_col(c2, ac2)
                        }
                        if adj_bad {
                            emit_s(err_ref)
                        } else {
                            emit_ref(r1, c1, ar1, ac1)
                            emit(iso:':')
                            emit_ref(r2, c2, ar2, ac2)
                        }
                    } else {
                        r1 = adj_row(r1, ar1)
                        c1 = adj_col(c1, ac1)
                        if adj_bad
                            emit_s(err_ref)
                        else
                            emit_ref(r1, c1, ar1, ac1)
                    }
                    p = q
                    continue
                }
                ; some other name (function): copy it whole
                while is_ident(fb[p]) {
                    emit(fb[p])
                    p++
                }
                continue
            }
            emit(c)
            p++
        }
        return oblen <= MAXFLEN
    }

    ; tidy a typed formula: upper case outside "..", close open parentheses
    sub tidy(uword s) {
        ubyte i = 0
        ubyte depth = 0
        bool inq = false
        while @(s + i) != 0 {
            ubyte c = @(s + i)
            if c == iso:'"'
                inq = not inq
            else if not inq {
                @(s + i) = upc(c)
                if c == iso:'('
                    depth++
                else if c == iso:')' and depth != 0
                    depth--
            }
            i++
        }
        while depth != 0 and i < MAXFLEN + 1 {
            @(s + i) = iso:')'
            i++
            depth--
        }
        @(s + i) = 0
    }
}
