import { strToU8, zipSync } from 'fflate';
import { describe, expect, it } from 'vitest';
import { columnIndex, FILE_MAX_BYTES, namesFrom, namesFromPaste, parseCsv, readNamesFile, type FileLike } from '../src/invites/namesFile';

// Hidden characters are built with fromCharCode: never pasted into source.
const RLO = String.fromCharCode(0x202e);
const ZWSP = String.fromCharCode(0x200b);
const BOM = String.fromCharCode(0xfeff);

function file(name: string, bytes: Uint8Array, size = bytes.byteLength): FileLike {
  return { name, size, arrayBuffer: () => Promise.resolve(bytes.slice().buffer) };
}

const WORKBOOK = `<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Members" sheetId="1" r:id="rId1"/></sheets></workbook>`;
const RELS = `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>`;

function xlsx(sheet: string, shared: string[] = [], extra: Record<string, Uint8Array> = {}): Uint8Array {
  const sst = `<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">${shared.map((s) => `<si><t>${s}</t></si>`).join('')}</sst>`;
  return zipSync({
    'xl/workbook.xml': strToU8(WORKBOOK),
    'xl/_rels/workbook.xml.rels': strToU8(RELS),
    'xl/sharedStrings.xml': strToU8(sst),
    'xl/worksheets/sheet1.xml': strToU8(`<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${sheet}</sheetData></worksheet>`),
    ...extra,
  });
}

describe('xlsx', () => {
  it('reads shared strings, inline strings and numbers by column', async () => {
    const sheet =
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>' +
      '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>1001</v></c></row>' +
      '<row r="3"><c r="A3" t="inlineStr"><is><t>نور عبد الله</t></is></c></row>';
    const result = await readNamesFile(file('members.xlsx', xlsx(sheet, ['Name', 'Phone', 'Ahmed Samir'])));
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.columns.map((c) => c.letter)).toEqual(['A', 'B']);
    expect(result.columns[0]?.header).toBe('Name');
    expect(result.columns[0]?.cells).toEqual(['Name', 'Ahmed Samir', 'نور عبد الله']);
    expect(result.columns[1]?.cells).toEqual(['Phone', '1001', '']);
  });

  it('escapes nothing: markup-like text stays text, entities decoded once', async () => {
    const sheet = '<row r="1"><c r="A1" t="s"><v>0</v></c></row>';
    const result = await readNamesFile(file('x.xlsx', xlsx(sheet, ['&lt;img src=x onerror=alert(1)&gt;'])));
    expect(result.ok && result.columns[0]?.cells[0]).toBe('<img src=x onerror=alert(1)>');
  });

  it('a shared-string index out of range is an empty cell, not a crash', async () => {
    const result = await readNamesFile(file('x.xlsx', xlsx('<row r="1"><c r="A1" t="s"><v>99</v></c><c r="B1" t="s"><v>-1</v></c><c r="C1" t="inlineStr"><is><t>ok</t></is></c></row>')));
    expect(result.ok && result.columns.map((c) => c.cells[0])).toEqual(['ok']);
  });

  it('refuses a zip bomb (too large unzipped)', async () => {
    const huge = new Uint8Array(21 * 1024 * 1024); // zeros compress to almost nothing
    const bomb = zipSync({ 'xl/worksheets/sheet1.xml': huge }, { level: 9 });
    expect(bomb.byteLength).toBeLessThan(FILE_MAX_BYTES);
    expect(await readNamesFile(file('bomb.xlsx', bomb))).toEqual({ ok: false, problem: 'unreadable' });
  });

  it('broken XML and a non-zip .xlsx are unreadable', async () => {
    const broken = zipSync({ 'xl/workbook.xml': strToU8(WORKBOOK), 'xl/_rels/workbook.xml.rels': strToU8(RELS), 'xl/worksheets/sheet1.xml': strToU8('<worksheet><sheetData><row>') });
    expect(await readNamesFile(file('a.xlsx', broken))).toEqual({ ok: false, problem: 'unreadable' });
    expect(await readNamesFile(file('a.xlsx', strToU8('just text')))).toEqual({ ok: false, problem: 'unreadable' });
  });

  it('a relationship that points outside xl/worksheets is ignored', async () => {
    const evilRels = RELS.replace('worksheets/sheet1.xml', '../../../etc/passwd');
    const zip = zipSync({ 'xl/workbook.xml': strToU8(WORKBOOK), 'xl/_rels/workbook.xml.rels': strToU8(evilRels), 'xl/worksheets/sheet1.xml': strToU8('<worksheet/>') });
    expect(await readNamesFile(file('a.xlsx', zip))).toEqual({ ok: false, problem: 'unreadable' });
  });

  it('a password-protected workbook (OLE file) says so; .xls is old Excel', async () => {
    const ole = new Uint8Array([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0, 0]);
    expect(await readNamesFile(file('locked.xlsx', ole))).toEqual({ ok: false, problem: 'locked' });
    expect(await readNamesFile(file('old.xls', ole))).toEqual({ ok: false, problem: 'old_excel' });
  });
});

describe('file checks before reading', () => {
  it.each([
    ['names.pdf', 'wrong_type'],
    ['names', 'wrong_type'],
    ['names.xlsx.exe', 'wrong_type'],
    ['names.numbers', 'wrong_type'],
  ])('%s → %s', async (name, problem) => {
    expect(await readNamesFile(file(name, strToU8('a')))).toEqual({ ok: false, problem });
  });

  it('over 1 MB is refused without reading', async () => {
    let read = false;
    const big: FileLike = { name: 'a.csv', size: FILE_MAX_BYTES + 1, arrayBuffer: () => { read = true; return Promise.resolve(new ArrayBuffer(0)); } };
    expect(await readNamesFile(big)).toEqual({ ok: false, problem: 'too_big' });
    expect(read).toBe(false);
  });

  it('an empty sheet has no names', async () => {
    expect(await readNamesFile(file('a.csv', strToU8('\n\n , \n')))).toEqual({ ok: false, problem: 'empty' });
  });
});

describe('csv', () => {
  it('handles a BOM, quotes, commas in quotes, CRLF and ; or tab delimiters', () => {
    const csv = parseCsv(strToU8(`${BOM}Name,Phone\r\n"Samir, Ahmed",1\r\n"Say ""hi""",2\r\n`));
    expect(csv.ok && csv.columns[0]?.cells).toEqual(['Name', 'Samir, Ahmed', 'Say "hi"']);
    const semi = parseCsv(strToU8('Name;Phone\nMona;3\n'));
    expect(semi.ok && semi.columns[0]?.cells).toEqual(['Name', 'Mona']);
    const tab = parseCsv(strToU8('Name\tPhone\nOmar\t4\n'));
    expect(tab.ok && tab.columns[0]?.cells).toEqual(['Name', 'Omar']);
  });

  it('refuses text that is not UTF-8', () => {
    expect(parseCsv(new Uint8Array([0xff, 0xfe, 0x41]))).toEqual({ ok: false, problem: 'unreadable' });
  });

  it('formula-looking cells stay plain text', () => {
    const csv = parseCsv(strToU8('=HYPERLINK("http://evil.example")\n'));
    // Kept as typed; it is only ever shown as text, never evaluated or exported.
    expect(csv.ok && csv.columns[0]?.cells[0]).toBe('=HYPERLINK("http://evil.example")');
  });
});

describe('names', () => {
  it('skips the title row, empties; flags long names and repeats; strips hidden characters', () => {
    const long = 'x'.repeat(41);
    const list = namesFrom(['Name', 'Ahmed Samir', '', `${RLO}nimda`, `Mo${ZWSP}na`, long, 'ahmed samir'], true);
    expect(list.names).toEqual(['Ahmed Samir', 'nimda', 'Mona', long, 'ahmed samir']);
    expect(list.emptySkipped).toBe(1);
    expect(list.tooLong).toEqual([4]);
    expect(list.repeated).toEqual(['Ahmed Samir', 'ahmed samir']);
    expect(list.cleaned).toBe(true);
  });

  it('a pasted Excel column (tabs, CRLF, trailing empty line) gives the first column', () => {
    const list = namesFromPaste('Ahmed\t010\r\nMona\t011\r\n\r\n');
    expect(list.names).toEqual(['Ahmed', 'Mona']);
    expect(list.emptySkipped).toBe(0);
    expect(list.cleaned).toBe(false);
  });
});

describe('columnIndex', () => {
  it.each([
    ['A1', 0],
    ['Z9', 25],
    ['AA10', 26],
    ['a1', -1],
    ['1A', -1],
    ['', -1],
    ['AAAA1', -1],
  ])('%s → %i', (ref, index) => {
    expect(columnIndex(ref)).toBe(index);
  });
});
