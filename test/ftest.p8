; headless test of cells + formula: prints PASS/FAIL lines, then DONE
%import textio
%import cells
%import formula
%zeropage basicsafe

main {
    ubyte fails
    sub setnum(uword r, ubyte c, float v) {
        void cells.get(r, c)
        cells.R[cells.R_TYPE] = cells.T_NUM
        sys.memcopy(&v, &cells.R + cells.R_VAL, 5)
        void cells.put(r, c)
    }
    sub setf(uword r, ubyte c, str f) {
        void cells.get(r, c)
        cells.R[cells.R_TYPE] = cells.T_FORM
        ubyte n = strings.length(f)
        cells.R[cells.R_LEN] = n
        sys.memcopy(f, &cells.R + cells.R_TXT, n)
        void cells.put(r, c)
    }
    sub settext(uword r, ubyte c, str f) {
        void cells.get(r, c)
        cells.R[cells.R_TYPE] = cells.T_TEXT
        ubyte n = strings.length(f)
        cells.R[cells.R_LEN] = n
        sys.memcopy(f, &cells.R + cells.R_TXT, n)
        void cells.put(r, c)
    }
    sub chk(str f, float want, ubyte werr) {
        formula.eval(f, strings.length(f))
        txt.print(f)
        txt.print(iso:" = ")
        if formula.everr != 0 {
            txt.print(formula.err_text(formula.everr))
        } else
            floats.print(formula.result)
        float d = formula.result - want
        if formula.everr == werr and (werr != 0 or abs(d) < 0.000001) {
            txt.print(iso:"  PASS\n")
        } else {
            txt.print(iso:"  FAIL\n")
            fails++
        }
    }
    sub chkcell(uword r, ubyte c, float want) {
        cells.lookup(r, c)
        txt.print(iso:"cell ")
        txt.print_uw(r)
        txt.print(iso:" = ")
        floats.print(cells.lv)
        float d = cells.lv - want
        if cells.lv_err == 0 and abs(d) < 0.000001
            txt.print(iso:"  PASS\n")
        else {
            txt.print(iso:"  FAIL\n")
            fails++
        }
    }
    sub chkadj(str f, str want) {
        void formula.adjust(f, strings.length(f))
        formula.ob[formula.oblen] = 0
        txt.print(f)
        txt.print(iso:" -> ")
        txt.print(&formula.ob)
        if strings.compare(&formula.ob, want) == 0
            txt.print(iso:"  PASS\n")
        else {
            txt.print(iso:"  FAIL want ")
            txt.print(want)
            txt.nl()
            fails++
        }
    }

    sub start() {
        txt.iso()
        cells.init()
        txt.print(iso:"maxrecs ")
        txt.print_uw(cells.maxrecs)
        txt.nl()
        setnum(1, 0, 10.0)      ; A1
        setnum(2, 0, 20.0)      ; A2
        setnum(3, 0, 30.5)      ; A3
        settext(4, 0, iso:"hello")  ; A4
        setnum(1, 1, -4.0)      ; B1
        setnum(9999, 255, 7.0)  ; IV9999
        chk(iso:"1+2*3", 7.0, 0)
        chk(iso:"(1+2)*3", 9.0, 0)
        chk(iso:"-2^2", 4.0, 0)
        chk(iso:"2^3^2", 64.0, 0)
        chk(iso:"10/4", 2.5, 0)
        chk(iso:"1/0", 0.0, formula.E_DIV0)
        chk(iso:"50%", 0.5, 0)
        chk(iso:"A1+A2", 30.0, 0)
        chk(iso:"a1 * $A$2", 200.0, 0)
        chk(iso:"SUM(A1:A4)", 60.5, 0)
        chk(iso:"SUM(A1:A3,B1,100)", 156.5, 0)
        chk(iso:"AVERAGE(A1:A3)", 20.1666666667, 0)
        chk(iso:"MIN(A1:B3)", -4.0, 0)
        chk(iso:"MAX(A1:B3)", 30.5, 0)
        chk(iso:"COUNT(A1:A4)", 3.0, 0)
        chk(iso:"COUNT(A1:IV9999)", 5.0, 0)
        chk(iso:"PRODUCT(A1:A2)", 200.0, 0)
        chk(iso:"ABS(B1)", 4.0, 0)
        chk(iso:"SQRT(16)", 4.0, 0)
        chk(iso:"SQRT(B1)", 0.0, formula.E_NUM)
        chk(iso:"INT(-2.5)", -3.0, 0)
        chk(iso:"ROUND(2.345,2)", 2.35, 0)
        chk(iso:"ROUND(-1234.5,-2)", -1200.0, 0)
        chk(iso:"IF(A1>5,1,2)", 1.0, 0)
        chk(iso:"IF(A1<>10,1,2)", 2.0, 0)
        chk(iso:"A4+1", 0.0, formula.E_VALUE)
        chk(iso:"SUM(A4)", 0.0, 0)
        chk(iso:"FOO(1)", 0.0, formula.E_NAME)
        chk(iso:"1E30*1E-30", 1.0, 0)
        chk(iso:"1E30*1E30", 0.0, formula.E_NUM)
        chk(iso:"1E20*1E20", 0.0, formula.E_NUM)
        chk(iso:"(-8)^(1/3)", 0.0, formula.E_NUM)
        chk(iso:"(-2)^3", -8.0, 0)
        chk(iso:"SUM(1,2", 0.0, formula.E_NAME)
        chk(iso:"SUM()", 0.0, 0)
        chk(iso:"#REF!+1", 0.0, formula.E_REF)
        chk(iso:"IV9999*2", 14.0, 0)
        chk(iso:"2*TRUE", 2.0, 0)
        ; recalc chain, out of order
        setf(5, 0, iso:"A6*2")      ; A5 = A6*2
        setf(6, 0, iso:"SUM(A1:A3)")
        formula.recalc()
        chkcell(5, 0, 121.0)
        chkcell(6, 0, 60.5)
        ; references rewriting
        formula.adj_mode = formula.ADJ_MOVE
        formula.adj_dr = 2
        formula.adj_dc = 1
        chkadj(iso:"SUM(A1:A3)+$B$1+C$2", iso:"SUM(B3:B5)+$B$1+D$2")
        formula.adj_dr = -5
        chkadj(iso:"A1+B9", iso:"#REF!+C4")
        formula.adj_mode = formula.ADJ_ROWS
        formula.adj_at = 3
        formula.adj_n = 2
        chkadj(iso:"A2+A3+$A$9+SUM(A1:A5)", iso:"A2+A5+$A$11+SUM(A1:A7)")
        formula.adj_n = -2
        chkadj(iso:"A2+A3+A9+SUM(A1:A5)+SUM(A3:A4)", iso:"A2+#REF!+A7+SUM(A1:A3)+SUM(#REF!)")
        formula.adj_mode = formula.ADJ_COLS
        formula.adj_at = 1
        formula.adj_n = 1
        chkadj(iso:"A1+B1+ROUND(C1,2)", iso:"A1+C1+ROUND(D1,2)")
        ; hash: many cells, delete, find
        uword r
        for r in 1 to 3000
            setnum(r, 7, r as float)
        for r in 1 to 3000 step 2
            cells.erase(r, 7)
        chk(iso:"SUM(H1:H3000)", 2251500.0, 0)
        chk(iso:"COUNT(H1:H9999)", 1500.0, 0)
        txt.print(iso:"used ")
        txt.print_uw(cells.nused)
        txt.print(iso:" free ")
        txt.print_uw(cells.free_count())
        txt.nl()
        if fails == 0
            txt.print(iso:"ALL PASS\n")
        else {
            txt.print_ub(fails)
            txt.print(iso:" FAILED\n")
        }
        txt.print(iso:"DONE\n")
    }
}
