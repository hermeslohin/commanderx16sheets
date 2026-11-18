; perftest.p8 - recalculation speed on a large sheet (jiffies = 1/60 s); DONE at the end
%import textio
%import cells
%import formula
%zeropage basicsafe

main {
    sub setf(uword r, ubyte c, str f) {
        void cells.get(r, c)
        cells.R[cells.R_TYPE] = cells.T_FORM
        ubyte n = strings.length(f)
        cells.R[cells.R_LEN] = n
        sys.memcopy(f, &cells.R + cells.R_TXT, n)
        void cells.put(r, c)
    }
    sub start() {
        txt.iso()
        cells.init()
        uword r
        float v
        for r in 1 to 2000 {
            void cells.get(r, 0)
            cells.R[cells.R_TYPE] = cells.T_NUM
            v = r as float
            sys.memcopy(&v, &cells.R + cells.R_VAL, 5)
            void cells.put(r, 0)
        }
        for r in 1 to 1000
            setf(r, 1, iso:"A1*2+A2")
        setf(1, 2, iso:"SUM(A1:A2000)")
        setf(2, 2, iso:"SUM(B1:B1000)")
        uword t0 = cbm.RDTIM16()
        formula.recalc()
        uword t1 = cbm.RDTIM16()
        txt.print(iso:"cells ")
        txt.print_uw(cells.nused)
        txt.print(iso:" evals ")
        txt.print_uw(formula.evals)
        txt.print(iso:" passes ")
        txt.print_ub(formula.passes)
        txt.print(iso:" jiffies ")
        txt.print_uw(t1 - t0)
        txt.nl()
        t0 = cbm.RDTIM16()
        formula.recalc()
        t1 = cbm.RDTIM16()
        txt.print(iso:"second recalc jiffies ")
        txt.print_uw(t1 - t0)
        txt.nl()
        ; an edit: A1500 changes (only SUM(A1:A2000) depends on it)
        void cells.get(1500, 0)
        v = 7.0
        sys.memcopy(&v, &cells.R + cells.R_VAL, 5)
        void cells.put(1500, 0)
        t0 = cbm.RDTIM16()
        formula.recalc_area(1500, 0, 1500, 0)
        t1 = cbm.RDTIM16()
        txt.print(iso:"edit A1500: evals ")
        txt.print_uw(formula.evals)
        txt.print(iso:" jiffies ")
        txt.print_uw(t1 - t0)
        txt.nl()
        ; an edit: A3 changes (B2, B3 and the two SUMs depend on it)
        void cells.get(3, 0)
        sys.memcopy(&v, &cells.R + cells.R_VAL, 5)
        void cells.put(3, 0)
        t0 = cbm.RDTIM16()
        formula.recalc_area(3, 0, 3, 0)
        t1 = cbm.RDTIM16()
        txt.print(iso:"edit A3: evals ")
        txt.print_uw(formula.evals)
        txt.print(iso:" jiffies ")
        txt.print_uw(t1 - t0)
        txt.nl()
        cells.lookup(2, 2)
        txt.print(iso:"C2 = ")
        floats.print(cells.lv)
        txt.nl()
        txt.print(iso:"DONE\r")
    }
}
