; cellk.p8 - cell record layout constants for the bank libraries (same values as cells.p8).
cellk {
    %option ignore_unused
    const uword MAXROW = 9999
    const ubyte MAXLEN = 50
    const ubyte R_COL = 2
    const ubyte R_TYPE = 3
    const ubyte R_STY = 4
    const ubyte R_ERR = 5
    const ubyte R_LEN = 6
    const ubyte R_VAL = 7
    const ubyte R_TXT = 12
    const ubyte T_FREE = 0
    const ubyte T_NUM = 1
    const ubyte T_TEXT = 2
    const ubyte T_FORM = 3
    const ubyte T_BLANK = 4
    const ubyte T_CLIP = $80
    const ubyte ST_BOLD = 1
    const ubyte ST_ALIGN = 6
    const ubyte ST_FMT = $18
    const ubyte DEFW = 10
    const ubyte E_REF = 3
    const ubyte ADJ_MOVE = 1
    const ubyte ADJ_ROWS = 2
    const ubyte ADJ_COLS = 3
}
