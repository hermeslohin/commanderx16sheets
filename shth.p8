; shth.p8 - SHTH.BIN: X16 Sheets' theme loader as a bank library (the same idea as X16 Write's
; X16WPTH.BIN). The part of theme.p8 that reads the theme files (init, next, load, and diskio's file
; writing for X16THEME.CFG) runs here, so main RAM keeps only theme.p8's role table, the drawing and
; Quill. It takes no RAM of its own: app.themes() loads it each time it is needed (at start and when
; Quill is clicked) into RAM bank 56 at $AA00, the SD picker's file names (cells.name_put, idle then);
; the theme file is read just below it, at vid.TBANK / vid.TBUF (bank 56, $A800). run() gets the
; addresses of the main program's theme.rl, theme.dk, theme.msg and theme.cur and copies its results
; there. Without this file X16 Sheets is shown in the built-in Sunset Arcade colours (without Quill).

%address  $AA00
%memtop   $C000
%output   library
%zeropage dontuse

%import syslib
%import theme

main {
    %jmptable (
        th.run,         ; $AA03  r0..r3 = &theme.rl, &theme.dk, &theme.msg, &theme.cur (the main program's),
                        ;        r4L = 0: the saved theme, 1: the next one -> A false if there are no theme files
    )

    sub start() {
    }
}

th {
    sub run() -> bool {
        uword prl = cx16.r0
        uword pdk = cx16.r1
        uword pmsg = cx16.r2
        uword pcur = cx16.r3
        bool ok = true
        theme.cur = @(pcur)
        if cx16.r4L == 0
            theme.init()
        else
            ok = theme.next()
        sys.memcopy(&theme.rl, prl, 64)
        sys.memcopy(&theme.dk, pdk, 32)
        sys.memcopy(&theme.msg + 7, pmsg + 7, 16)
        @(pcur) = theme.cur
        return ok and theme.cur != 0
    }
}
