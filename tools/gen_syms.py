#!/usr/bin/env python3
"""Generate mainsyms_<bank>.p8: X16 Sheets' main-RAM routines and variables as seen from a bank library.

Same idea as X16 Write's gen_wpsyms.py: a bank library is a separate compilation, so it can't link
against the main program. This reads the main build's symbol list (x16sheets.vice-mon-list) and
assembly (x16sheets.asm) and emits, for every routine a library needs:
  * an `extsub @bank <bank> $addr` (JSRFAR: the main routine may switch RAM banks, JSRFAR maps the
    library's bank back before returning), and
  * for multi-parameter subs, a wrapper that stores the arguments into the callee's static
    parameter variables first (single int parameters travel in A / AY / registers instead).
CHECK = address of vid.render_run; the main program passes its own value at init and each library
refuses to run if the builds don't match.

usage: gen_syms.py <build-dir> <bank> <out.p8> [program, default x16sheets]
"""
import re
import sys
from pathlib import Path

B, W, BO = "ubyte", "uword", "bool"
# (alias, block, sub, [(param, type)], return type or None)
SUBS = [
    ("render_run", "vid", "render_run", [("row", B), ("col0", B), ("n", B)], None),
    ("compose_begin", "vid", "compose_begin", [], None),
    ("compose_end", "vid", "compose_end", [], None),
    ("vtext", "vid", "text", [("col", B), ("row", B), ("s", W), ("sty", B), ("fg", B), ("bg", B)], None),
    ("vfill", "vid", "fill", [("col", B), ("row", B), ("n", B), ("fg", B), ("bg", B)], None),
    ("set_status", "sview", "set_status", [("s", W)], None),
    ("draw_status", "sview", "draw_status", [], None),
    ("draw_grid", "sview", "draw_grid", [], None),
    ("draw_fbar", "sview", "draw_fbar", [], None),
    ("draw_rows", "sview", "draw_rows", [("a", W), ("b", W)], None),
    ("put", "sview", "put", [("col", B), ("row", B), ("s", W), ("fg", B), ("bg", B)], None),
    ("num", "sview", "num", [("col", B), ("row", B), ("n", W), ("fg", B), ("bg", B)], None),
    ("copy_str", "sview", "copy_str", [("src", W), ("dst", W), ("maxn", B)], None),
    ("set_filename", "sview", "set_filename", [("s", W)], None),
    ("sel_norm", "sview", "sel_norm", [], None),
    ("single", "sview", "single", [], BO),
    ("in_sel", "sview", "in_sel", [("r", W), ("c", B)], BO),
    ("add_btn", "sview", "add_btn", [("x", B), ("y", B), ("id", B)], None),
    ("click", "sview", "click", [], B),
    ("redraw_everything", "sview", "redraw_everything", [], None),
    ("select", "app", "select", [("r", W), ("c", B), ("extend", BO)], None),
    ("start_edit", "app", "start_edit", [("text", W), ("keep", BO)], None),
    ("commit", "app", "commit", [], BO),
    ("changed", "app", "changed", [], None),
    ("reset_view", "app", "reset_view", [], None),
    ("append", "app", "append", [("s", W)], None),
    ("append_range", "app", "append_range", [("r1", W), ("c1", B), ("r2", W), ("c2", B)], None),
    ("is_num", "app", "is_num", [("r", W), ("c", B)], BO),
    ("get", "cells", "get", [("row", W), ("col", B)], BO),
    ("cput", "cells", "put", [("row", W), ("col", B)], BO),
    ("find", "cells", "find", [("row", W), ("col", B)], W),
    ("load", "cells", "load", [("idx", W)], None),
    ("save", "cells", "save", [("idx", W)], None),
    ("rd", "cells", "rd", [("idx", W)], B),
    ("erase", "cells", "erase", [("row", W), ("col", B)], None),
    ("erase_range", "cells", "erase_range", [("r1", W), ("c1", B), ("r2", W), ("c2", B)], None),
    ("release", "cells", "release", [("idx", W)], None),
    ("rehash", "cells", "rehash", [], None),
    ("extent", "cells", "extent", [], None),
    ("clip_copy", "cells", "clip_copy", [("r1", W), ("c1", B), ("r2", W), ("c2", B)], BO),
    ("clip_clear", "cells", "clip_clear", [], None),
    ("clear_all", "cells", "clear_all", [], None),
    ("free_count", "cells", "free_count", [], W),
    ("mark_rows", "cells", "mark_rows", [], None),
    ("row_has", "cells", "row_has", [("r", W)], BO),
    ("name_put", "cells", "name_put", [("i", W)], None),
    ("name_get", "cells", "name_get", [("i", W)], None),
    ("adjust", "formula", "adjust", [("text", W), ("tl", B)], BO),
    ("cell_name", "formula", "cell_name", [("row", W), ("col", B), ("dst", W)], B),
    ("col_name", "formula", "col_name", [("c", B), ("dst", W)], B),
    ("err_text", "formula", "err_text", [("e", B)], W),
    ("err_code", "formula", "err_code", [("s", W)], B),
    ("parse_ref", "formula", "parse_ref", [("p", B)], BO),
    ("parse_number", "formula", "parse_number", [("s", W)], BO),
    ("recalc", "formula", "recalc", [], None),
    ("fout_rec", "numfmt", "fout_rec", [], None),
    ("disk_delete", "diskio", "delete", [("filenameptr", W)], None),
    ("pill", "theme", "pill", [("col", B), ("row", B), ("label", W), ("fg", B), ("face", B), ("bg", B)], None),
    ("stripes", "theme", "stripes", [("col", B), ("row", B), ("n", B)], None),
]
# (alias, block, var, kind)  kind: ubyte/byte/uword/bool or addr (= its address as a const)
VARS = [
    ("r_ch", "vid", "r_ch", "addr"), ("r_sty", "vid", "r_sty", "addr"), ("r_col", "vid", "r_col", "addr"),
    ("toprow", "sview", "toprow", "uword"), ("leftcol", "sview", "leftcol", "ubyte"),
    ("cur_r", "sview", "cur_r", "uword"), ("cur_c", "sview", "cur_c", "ubyte"),
    ("anc_r", "sview", "anc_r", "uword"), ("anc_c", "sview", "anc_c", "ubyte"),
    ("oth_r", "sview", "oth_r", "uword"), ("oth_c", "sview", "oth_c", "ubyte"),
    ("s_r1", "sview", "s_r1", "uword"), ("s_r2", "sview", "s_r2", "uword"),
    ("s_c1", "sview", "s_c1", "ubyte"), ("s_c2", "sview", "s_c2", "ubyte"),
    ("editing", "sview", "editing", "bool"), ("ebuf", "sview", "ebuf", "addr"),
    ("elen", "sview", "elen", "ubyte"), ("ecur", "sview", "ecur", "ubyte"),
    ("filename", "sview", "filename", "addr"), ("nbuf", "sview", "nbuf", "addr"),
    ("xbuf", "cells", "xbuf", "addr"),
    ("modified", "sview", "modified", "bool"), ("cloud_doc", "sview", "cloud_doc", "bool"),
    ("mouse_btn", "sview", "mouse_btn", "ubyte"), ("mouse_cx", "sview", "mouse_cx", "ubyte"),
    ("mouse_cy", "sview", "mouse_cy", "ubyte"), ("mouse_wheel", "sview", "mouse_wheel", "byte"),
    ("last_key", "sview", "last_key", "ubyte"), ("prev_btn", "sview", "prev_btn", "bool"),
    ("bt_n", "sview", "bt_n", "ubyte"), ("vmax", "sview", "vmax", "uword"),
    ("R", "cells", "R", "addr"), ("colw", "cells", "colw", "addr"),
    ("ntop", "cells", "ntop", "uword"), ("nused", "cells", "nused", "uword"),
    ("used_rows", "cells", "used_rows", "uword"), ("used_cols", "cells", "used_cols", "ubyte"),
    ("clip_r1", "cells", "clip_r1", "uword"), ("clip_r2", "cells", "clip_r2", "uword"),
    ("clip_c1", "cells", "clip_c1", "ubyte"), ("clip_c2", "cells", "clip_c2", "ubyte"),
    ("clip_any", "cells", "clip_any", "bool"),
    ("lv_type", "cells", "lv_type", "ubyte"), ("lv_err", "cells", "lv_err", "ubyte"),
    ("ob", "formula", "ob", "addr"), ("oblen", "formula", "oblen", "ubyte"),
    ("fb", "formula", "fb", "addr"), ("result", "formula", "result", "addr"),
    ("ref_row", "formula", "ref_row", "uword"), ("ref_col", "formula", "ref_col", "ubyte"),
    ("adj_mode", "formula", "adj_mode", "ubyte"), ("adj_dr", "formula", "adj_dr", "word"),
    ("adj_dc", "formula", "adj_dc", "word"), ("adj_at", "formula", "adj_at", "uword"),
    ("adj_n", "formula", "adj_n", "word"), ("fn_names", "formula", "fn_names", "addr"),
    ("nt", "numfmt", "t", "addr"),
    ("tmpname", "app", "tmpname", "addr"),
    ("clip_cut", "app", "clip_cut", "bool"),
    ("cloud_ok", "app", "cloud_ok", "bool"),
    ("hop", "theme", "hop", "ubyte"),  # = 32: Quill cheers (theme.cheer())
    ("theme_rl", "theme", "rl", "addr"),  # the theme's role table: @(mn.theme_rl + R_...)
]


def main(build: Path, bank: int, out: Path, prog: str = "x16sheets"):
    syms = {}
    for line in (build / f"{prog}.vice-mon-list").read_text().splitlines():
        m = re.match(r"al ([0-9a-fA-F]+) \.(\S+)", line)
        if m:
            syms[m.group(2)] = int(m.group(1), 16)
    asm = (build / f"{prog}.asm").read_text().splitlines()

    def lab(block, *parts):
        cands = [":".join([f"p8b_{block}"] + list(parts)),
                 ":".join([block] + [p.replace("p8s_", "").replace("p8v_", "") for p in parts])]
        for cand in cands:
            if cand in syms:
                return syms[cand], cand
        raise SystemExit(f"symbol not found: {block} {parts}")

    def reg_params(label):
        name = label.split(":")[-1]
        regs = {}
        for i, l in enumerate(asm):
            if re.match(rf"^{re.escape(name)}\s+\.proc", l):
                blk = asm[i + 1:i + 8]
                if not any("passed via cpu register" in b for b in blk):
                    return None
                for b in blk:
                    mm = re.match(r"\s+st([axy])\s+(\S+)", b)
                    if mm:
                        regs[mm.group(2)] = mm.group(1).upper()
                return regs
        raise SystemExit(f"proc not found in asm: {name}")

    o = ["; GENERATED by tools/gen_syms.py from the x16sheets build - do not edit.",
         f"; X16 Sheets main-RAM routines/variables as seen from the bank-{bank} library.", "", "mn {",
         "    %option ignore_unused"]
    check, _ = lab("vid", "p8s_render_run")
    o.append(f"    const uword CHECK = ${check:04x}")
    def param_addr(blk, sub, p):
        try:
            return lab(blk, f"p8s_{sub}", f"p8v_{p}")[0]
        except SystemExit:
            pass
        # zero-page parameter: "p8v_name = 113 ; zp ..." inside the sub's .proc (in block blk)
        block = None
        for i, l in enumerate(asm):
            mb = re.match(r"^(p8b_\w+)\s+\.proc", l)
            if mb:
                block = mb.group(1)
            if block == f"p8b_{blk}" and re.match(rf"^p8s_{sub}\s+\.proc", l):
                for l2 in asm[i + 1:]:
                    m = re.match(rf"^p8v_{p}\s+=\s+(\d+)\s+;\s+zp", l2)
                    if m:
                        return int(m.group(1))
                    if re.match(r"^\s+\.pend", l2):
                        break
        raise SystemExit(f"parameter not found: {blk}.{sub}.{p}")

    for alias, blk, sub, params, ret in SUBS:
        addr, label = lab(blk, f"p8s_{sub}")
        retdecl = ""
        if ret:
            retdecl = f" -> {ret} @AY" if ret == W else f" -> {ret} @A"
        clob = "clobbers(X, Y)" if ret else "clobbers(A, X, Y)"
        if ret == W:
            clob = "clobbers(X)"
        regs = reg_params(label) if params else {}
        if regs is not None and (params == [] or regs):
            ps = []
            for pname, ptype in params:
                r = "".join(v for k, v in regs.items() if k.split("+")[0].endswith("_" + pname))
                r = r or ("AY" if ptype == W else "A")
                ps.append(f"{ptype} {pname} @{r}")
            o.append(f"    extsub @bank {bank} ${addr:04x} = {alias}({', '.join(ps)}) {clob}{retdecl}")
            continue
        o.append(f"    extsub @bank {bank} ${addr:04x} = x_{alias}() {clob}{retdecl}")
        sig = ", ".join(f"{t} {p}" for p, t in params)
        o.append(f"    sub {alias}({sig}){' -> ' + ret if ret else ''} {{")
        for p, t in params:
            paddr = param_addr(blk, sub, p)
            if t == W:
                o.append(f"        pokew(${paddr:04x}, {p})")
            elif t == BO:
                o.append(f"        @(${paddr:04x}) = {p} as ubyte")
            else:
                o.append(f"        @(${paddr:04x}) = {p}")
        o.append(f"        {'return ' if ret else ''}x_{alias}()")
        o.append("    }")

    def var_addr(blk, var):
        try:
            return lab(blk, f"p8v_{var}")[0]
        except SystemExit:
            start = next(i for i, l in enumerate(asm) if re.match(rf"^p8b_{blk}\s+\.proc", l))
            for l in asm[start:]:
                m = re.match(rf"^p8v_{var}\s+=\s+(\d+)\s+;\s+zp", l)
                if m:
                    return int(m.group(1))
            raise SystemExit(f"variable not found: {blk}.{var}")

    for alias, blk, var, kind in VARS:
        addr = var_addr(blk, var)
        if kind == "addr":
            o.append(f"    const uword {alias} = ${addr:04x}")
        else:
            o.append(f"    &{kind} {alias} = ${addr:04x}")
    o.append("}")
    out.write_text("\n".join(o) + "\n")
    print(f"wrote {out} (CHECK=${check:04x})")


if __name__ == "__main__":
    main(Path(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3]), *(sys.argv[4:5]))
