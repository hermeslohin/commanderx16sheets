# X16 sheet format ("simple XLSX") and hub contract

X16 Sheets reads and writes a deliberately small subset of XLSX so a 6502 can
handle it without a decompressor. Every file it writes is a valid .xlsx that
Excel / LibreOffice / ownCloud open directly. The X16 Office hub converts any
real-world .xlsx (or .csv) **to** this subset when the X16 opens it (`conv=2`),
and re-packs (deflates) it when the X16 saves it.

## ZIP container

* Every entry is **stored** (method 0), no data descriptor (flag bit 3 clear),
  no ZIP64, no encryption, no extra fields, no comments. CRC-32 and sizes are
  in the local headers. A central directory and end record follow as usual.
* Entries, in this order (the X16 only needs `xl/worksheets/sheet1.xml`; the
  reader skips everything else, so order is not essential when reading):
  `[Content_Types].xml`, `_rels/.rels`, `xl/workbook.xml`,
  `xl/_rels/workbook.xml.rels`, `xl/styles.xml`, `xl/worksheets/sheet1.xml`.
* Only one sheet. Workbook sheet name: `Sheet1`.

## sheet1.xml

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<cols><col min="2" max="2" width="14" customWidth="1"/></cols>
<sheetData>
<row r="1"><c r="A1" s="1" t="inlineStr"><is><t>Item</t></is></c><c r="B1"><v>12.5</v></c></row>
<row r="3"><c r="B3" s="8"><f>SUM(B1:B2)</f><v>30</v></c><c r="C3" t="e"><f>1/0</f><v>#DIV/0!</v></c></row>
</sheetData></worksheet>
```

* Rows ascending, cells ascending inside a row, `r` attribute always present.
* Cell kinds the X16 understands:
  * number: `<v>` only (no `t`, or `t="n"`),
  * text: `t="inlineStr"` + `<is><t>..</t></is>` (`t="str"` with `<v>` is also accepted),
  * formula: `<f>` (Excel syntax, no leading `=`) plus an optional cached `<v>`;
    `t="e"` marks a cached error value, `t="str"` a cached text result.
* Text: ASCII is literal; `& < > " '` use the 5 standard entities; every
  non-ASCII character is written as a numeric reference `&#N;` (decimal).
  The X16 works in ISO-8859-15; the hub replaces characters that ISO-8859-15
  cannot hold with `?` (and sets the LOSSY flag). The X16 reader also decodes
  `&#xH;` and 2-byte UTF-8.
* A cell with only a style (`<c r="B2" s="16"/>`) is a formatted empty cell; the X16
  writes them, the hub drops them when it converts.
* `<cols>`: `width` in characters (the X16 rounds to an integer 3..40;
  default column width 10). Columns without an entry use the default.

### Limits (the hub truncates beyond them and sets the LOSSY flag)

| | |
|---|---|
| columns | 256 (A..IV) |
| rows | 9999 |
| cells | 6000 when the hub converts (the X16 holds 6528 on 512 KB, 12288 on 2 MB) |
| text | 50 bytes (ISO-8859-15) |
| formula | 46 bytes (the X16 keeps a 6-byte reference box per formula); longer formulas keep only their cached value |

### Style index `s` (fixed table, 32 entries, `cellXfs` in this order)

`s = bold + 2*align + 8*fmt`

* bold: 0 / 1
* align: 0 general, 1 left, 2 center, 3 right
* fmt: 0 General (numFmtId 0), 1 `0.00` (numFmtId 2), 2 `0.00%` (numFmtId 10),
  3 currency `"$"#,##0.00` (custom numFmtId 164)

`styles.xml` therefore has 2 fonts (regular, bold Calibri 11), the default
fills/borders, one custom numFmt (164), and 32 `<xf>` entries. When the hub
normalizes a foreign file it maps each cell's style to the nearest entry
(bold font -> bold; horizontal alignment; number format: General/0 -> 0,
any fixed-decimal -> 1, any percent -> 2, any currency -> 3).

### Formulas

The X16 evaluates (Excel semantics; `^` is left-associative and unary minus binds
tighter, so `-2^2` = 4 and `2^3^2` = 64): numbers, cell refs (`A1`, `$A$1`, mixed), ranges (`A1:B9`) as
function arguments, `+ - * / ^`, unary `-`, postfix `%`, comparisons
`= <> < > <= >=` (1/0), parentheses and the functions
`SUM AVERAGE MIN MAX COUNT PRODUCT ABS SQRT INT ROUND IF`.
Other formulas are kept as text and show `#NAME?` after recalculation on the X16.
The hub keeps formulas verbatim (it does not evaluate); it drops sheet-qualified
references' sheet names only if they point at the first sheet (otherwise the
formula is kept and will show `#REF!`/`#NAME?` on the X16).

## Hub docs channel additions

* LIST entry type byte: 0 other, 1 RTF, 2 TXT, **3 DOCX, 4 XLSX, 5 CSV**.
* conv byte (OPEN and SAVE): 0 native bytes (.csv: charset converted like .txt), 1 RTF on the X16 side
  (valid for .rtf .txt .docx), **2 X16 sheet (simple XLSX) on the X16 side
  (valid for .xlsx .csv)**. A conv that doesn't fit the file type -> E_UNSUPPORTED.
* OPEN `.docx` conv 1: DOCX -> RTF the X16 WP can import.
* SAVE `.docx` conv 1: X16 WP RTF -> DOCX (bold/italic/underline, the 3 fonts,
  16 text + highlight colours, alignment, indent, bullet/number lists, page breaks;
  soft-wrapped lines (`{\*\xwp N}` bit 7) are joined back into paragraphs).
* OPEN `.xlsx` / `.csv` conv 2: -> simple XLSX (first sheet only).
* SAVE `.xlsx` conv 2: validate the simple XLSX, store it deflated (the upload is not
  held to the limits above, so a 2 MB X16 can save 12000 cells).
  SAVE `.csv` conv 2: cell values (formula cells: cached value) -> UTF-8 CSV.
