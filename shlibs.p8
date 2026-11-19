; shlibs.p8 - entry points of X16 Sheets' bank libraries (jump tables at $A003..; $A000 = init).
; Imported by the main program and by the libraries themselves (they call each other through JSRFAR).
; Arguments in cx16 r0..r3, results in A / AY. Pointers passed between banks must point into main RAM
; (or into the called library's own bank); strings that cross go through sview.xbuf.
;
;   bank 57 SHOPS.BIN   editing operations (format, clipboard, rows/columns, AutoSum, functions)
;   bank 58 SHXR.BIN    XLSX reader
;   bank 59 SHXW.BIN    XLSX writer
;   bank 62 SHFILE.BIN  New / Open / Save, SD card picker, ownCloud (X16Link)
;   bank 63 SHUI.BIN    toolbars, tool tips, dialogs, menus
;   bank 55 SHSA.BIN    Save As folder browser (SD card and ownCloud)
;   bank 56 SHTH.BIN    theme loader at $AA00, loaded only when needed (app.themes(); see shth.p8)

shl {
    %option ignore_unused
    const ubyte OPS = 57
    const ubyte XR = 58
    const ubyte XW = 59
    const ubyte FILE = 62
    const ubyte UI = 63
    const ubyte SA = 55
    const ubyte TH = 56

    ; ---- SHUI (63)
    extsub @bank UI $A000 = ui_init() clobbers(A, X, Y)
    extsub @bank UI $A003 = ui_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank UI $A006 = draw_toolbar() clobbers(A, X, Y)
    extsub @bank UI $A009 = show_tip(ubyte id @R0) clobbers(A, X, Y)
    extsub @bank UI $A00C = dialog_input(ubyte title @R0, uword buf @R1, ubyte maxlen @R2) clobbers(X, Y) -> bool @A
    extsub @bank UI $A00F = yesno(ubyte msg @R0) clobbers(X, Y) -> bool @A
    extsub @bank UI $A012 = message(ubyte title @R0, ubyte msg @R1) clobbers(A, X, Y)
    extsub @bank UI $A015 = menu(ubyte x @R0, ubyte y @R1, ubyte which @R2) clobbers(X, Y) -> ubyte @A
    extsub @bank UI $A018 = conflict(ubyte exists @R0) clobbers(X, Y) -> ubyte @A
    extsub @bank UI $A01B = upload_icons() clobbers(A, X, Y)
    extsub @bank UI $A01E = sa_frame(ubyte cl @R0) clobbers(A, X, Y)

    ; dialog titles / messages (SHUI owns the texts)
    const ubyte T_SAVE_SD = 0
    const ubyte T_OPEN_SD = 1
    const ubyte T_SAVE_OC = 2
    const ubyte T_SHEETFULL = 3
    const ubyte T_NEWFOLDER = 4
    const ubyte M_QUIT = 0
    const ubyte M_DISCARD = 1
    const ubyte M_FULL = 2
    const ubyte M_REPLACE = 3
    const ubyte MENU_OPEN = 0
    const ubyte MENU_SAVE = 1
    const ubyte MENU_FX = 2

    ; ---- SHFILE (62)
    extsub @bank FILE $A000 = file_init() clobbers(A, X, Y)
    extsub @bank FILE $A003 = file_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank FILE $A006 = new_sheet() clobbers(A, X, Y)
    extsub @bank FILE $A009 = open_sheet() clobbers(A, X, Y)
    extsub @bank FILE $A00C = save_sheet(ubyte ask @R0) clobbers(A, X, Y)

    ; ---- SHTH (56, at $AA00: loaded by app.themes() each time)
    extsub @bank TH $AA00 = th_init() clobbers(A, X, Y)
    extsub @bank TH $AA03 = th_run(uword rl @R0, uword dk @R1, uword msg @R2, uword cur @R3, ubyte what @R4) clobbers(X, Y) -> bool @A

    ; ---- SHSA (55)
    extsub @bank SA $A000 = sa_init() clobbers(A, X, Y)
    extsub @bank SA $A003 = sa_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank SA $A006 = sa_browse(ubyte cl @R0) clobbers(X, Y) -> bool @A
    extsub @bank SA $A009 = sa_key_path() clobbers(A, X, Y)
    extsub @bank SA $A00C = sa_exists(uword name @R0) clobbers(X, Y) -> bool @A
    extsub @bank SA $A00F = sa_cd_back() clobbers(A, X, Y)

    ; ---- SHXW (59)
    extsub @bank XW $A000 = xw_init() clobbers(A, X, Y)
    extsub @bank XW $A003 = xw_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank XW $A006 = xlsx_save(uword name @R0) clobbers(X, Y) -> bool @A

    ; ---- SHXR (58)
    extsub @bank XR $A000 = xr_init() clobbers(A, X, Y)
    extsub @bank XR $A003 = xr_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank XR $A006 = xlsx_load(uword name @R0) clobbers(X, Y) -> ubyte @A
    extsub @bank XR $A009 = xlsx_lossy() clobbers(X, Y) -> bool @A
    const ubyte ST_OK = 0
    const ubyte ST_DISK = 1
    const ubyte ST_FORMAT = 2
    const ubyte ST_COMPRESSED = 3
    const ubyte ST_NOSHEET = 4
    const ubyte ST_FULL = 5

    ; ---- SHOPS (57)
    extsub @bank OPS $A000 = ops_init() clobbers(A, X, Y)
    extsub @bank OPS $A003 = ops_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank OPS $A006 = style_op(ubyte op @R0) clobbers(A, X, Y)
    extsub @bank OPS $A009 = width_op(byte d @R0) clobbers(A, X, Y)
    extsub @bank OPS $A00C = clear_cells(ubyte all @R0) clobbers(A, X, Y)
    extsub @bank OPS $A00F = copy_cells(ubyte cut @R0) clobbers(A, X, Y)
    extsub @bank OPS $A012 = paste_cells() clobbers(A, X, Y)
    extsub @bank OPS $A015 = rowcol_op(ubyte rows @R0, ubyte insert @R1) clobbers(A, X, Y)
    extsub @bank OPS $A018 = autosum() clobbers(A, X, Y)
    extsub @bank OPS $A01B = fx_menu() clobbers(A, X, Y)
    extsub @bank OPS $A01E = select_all() clobbers(A, X, Y)
}
