#!/usr/bin/env python3
"""Run the real X16 Office hub link server (x16-office-hub/hub) on 127.0.0.1:<port> with an in-memory
ownCloud (the hub's FakeOC test double), for X16 Sheets' cloud test.

usage: fakehub.py <hub-dir> <sd-dir> <out-dir> [port]
  * writes <sd-dir>/X16LINK.KEY for device x16-sheets-test
  * seeds Documents/A-budget.xlsx (a normal, deflated xlsx with shared strings) and B-data.csv
  * runs until <out-dir>/STOP exists, then dumps every Documents/ file into <out-dir>
"""
import asyncio
import io
import sys
import zipfile
from pathlib import Path

hub, sd, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
port = int(sys.argv[4]) if len(sys.argv) > 4 else 6502
sys.path[:0] = [str(hub), str(hub / "tests")]

from fake_oc import FakeOC                               # noqa: E402
from x16hub.link import keys as K                        # noqa: E402
from x16hub.link.server import Limits, LinkServer        # noqa: E402

KEY = bytes(range(100, 132))
DEV = "x16-sheets-test"


def real_xlsx() -> bytes:
    """A small xlsx the way desktop spreadsheets write it: deflated, shared strings, styles."""
    ct = ('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>')
    rels = ('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    wb = ('<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Budget" sheetId="1" r:id="rId1"/></sheets></workbook>')
    wbrels = ('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
              '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
              '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>')
    ss = ('<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="3" uniqueCount="3">'
          '<si><t>Month</t></si><si><t>Rent</t></si><si><t>Café €</t></si></sst>')
    styles = ('<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
              '<fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders>'
              '<cellXfs count="3"><xf numFmtId="0" fontId="0"/><xf numFmtId="0" fontId="1" applyFont="1"/><xf numFmtId="4" fontId="0"/></cellXfs></styleSheet>')
    sheet = ('<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
             '<row r="1"><c r="A1" t="s" s="1"><v>0</v></c><c r="B1" t="s" s="1"><v>1</v></c></row>'
             '<row r="2"><c r="A2"><v>1</v></c><c r="B2" s="2"><v>1200.5</v></c></row>'
             '<row r="3"><c r="A3"><v>2</v></c><c r="B3" s="2"><v>1300</v></c></row>'
             '<row r="4"><c r="A4" t="s"><v>2</v></c><c r="B4"><f>SUM(B2:B3)</f><v>2500.5</v></c></row>'
             '</sheetData></worksheet>')
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w", zipfile.ZIP_DEFLATED) as z:
        for n, d in (("[Content_Types].xml", ct), ("_rels/.rels", rels), ("xl/workbook.xml", wb),
                     ("xl/_rels/workbook.xml.rels", wbrels), ("xl/sharedStrings.xml", ss),
                     ("xl/styles.xml", styles), ("xl/worksheets/sheet1.xml", sheet)):
            z.writestr(n, d)
    return b.getvalue()


async def main():
    oc = FakeOC()
    oc.ensure_folder("Documents")
    oc.add("Documents/A-budget.xlsx", real_xlsx())
    oc.add("Documents/B-data.csv", "x,y\n1,2\n3,4\n".encode())
    oc.add("Documents/C-letter.rtf", b"{\\rtf1 hi}")
    K.write_sd_keyfile(sd, f"127.0.0.1:{port}", DEV, KEY)
    srv = LinkServer(keys_loader=lambda: {DEV: KEY}, oc_factory=lambda: oc,
                     limits=Limits(handshake=60, idle=600, partial=30), cal_db_factory=lambda: None)
    s = await srv.start("127.0.0.1", port)
    print("hub up", flush=True)
    out.mkdir(parents=True, exist_ok=True)
    while not (out / "STOP").exists():
        await asyncio.sleep(0.3)
    for p, (data, _e, _t) in oc.files.items():
        (out / p.split("/")[-1]).write_bytes(data)
    s.close()


asyncio.run(main())
