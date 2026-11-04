import { unzipSync, type UnzipFileInfo } from 'fflate';
import { cleanName } from '../core/text';
import { NAME_MAX } from '../members/members';

// Names from an Excel (.xlsx) or CSV file, read in the browser only (board
// 1.7). The file is untrusted: it is size-limited before reading, unzipped
// with a cap (a zip bomb can't fill memory), parsed as XML data only (the
// browser's DOMParser never loads external entities), and every cell becomes
// plain text through cleanName(). Nothing is uploaded.

export const FILE_MAX_BYTES = 1024 * 1024; // 1 MB, as the board says
const UNZIPPED_MAX_BYTES = 20 * 1024 * 1024;
const ROWS_MAX = 5000;
const COLS_MAX = 26;

export type FileProblem =
  | 'too_big' //   over 1 MB
  | 'wrong_type' // not .xlsx or .csv (an old .xls says so)
  | 'old_excel' //  a .xls file
  | 'locked' //     a password-protected workbook (an encrypted OLE file)
  | 'unreadable' // broken zip/XML, or limits hit
  | 'empty'; //     no names in the first sheet

export interface Column {
  /** 'A', 'B', … */
  readonly letter: string;
  /** The first row's text, as a hint ("Name"). */
  readonly header: string;
  /** Every cell of the column from the first row on, as text. */
  readonly cells: readonly string[];
}

export type Sheet = { readonly ok: true; readonly columns: readonly Column[] } | { readonly ok: false; readonly problem: FileProblem };

export interface NameList {
  readonly names: readonly string[];
  readonly emptySkipped: number;
  /** Lines (1-based, in the list) whose name is longer than 40 characters. */
  readonly tooLong: readonly number[];
  /** Names that appear more than once (kept, but shown to check). */
  readonly repeated: readonly string[];
  /** True when hidden direction or control characters were removed somewhere. */
  readonly cleaned: boolean;
}

export interface FileLike {
  readonly name: string;
  readonly size: number;
  arrayBuffer(): Promise<ArrayBuffer>;
}

const OLE_MAGIC = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
const ZIP_MAGIC = [0x50, 0x4b, 0x03, 0x04];

const startsWith = (bytes: Uint8Array, magic: readonly number[]) => magic.every((b, i) => bytes[i] === b);

export async function readNamesFile(file: FileLike): Promise<Sheet> {
  const ext = /\.([a-z0-9]{1,5})$/i.exec(file.name)?.[1]?.toLowerCase() ?? '';
  if (file.size > FILE_MAX_BYTES) return { ok: false, problem: 'too_big' };
  if (ext === 'xls') return { ok: false, problem: 'old_excel' };
  if (ext !== 'xlsx' && ext !== 'csv') return { ok: false, problem: 'wrong_type' };
  let bytes: Uint8Array;
  try {
    bytes = new Uint8Array(await file.arrayBuffer());
  } catch {
    return { ok: false, problem: 'unreadable' };
  }
  if (bytes.byteLength > FILE_MAX_BYTES) return { ok: false, problem: 'too_big' };
  if (startsWith(bytes, OLE_MAGIC)) return { ok: false, problem: ext === 'xlsx' ? 'locked' : 'old_excel' };
  if (ext === 'csv') return parseCsv(bytes);
  if (!startsWith(bytes, ZIP_MAGIC)) return { ok: false, problem: 'unreadable' };
  return parseXlsx(bytes);
}

// ---------------------------------------------------------------- CSV ----

export function parseCsv(bytes: Uint8Array): Sheet {
  let text: string;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    return { ok: false, problem: 'unreadable' };
  }
  text = text.replace(/^\uFEFF/, '');
  const firstLine = text.split(/\r?\n/, 1)[0] ?? '';
  const delimiter = [',', ';', '\t'].reduce((best, d) => (count(firstLine, d) > count(firstLine, best) ? d : best), ',');
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i] ?? '';
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') {
        cell += '"';
        i++;
      } else if (ch === '"') quoted = false;
      else cell += ch;
      continue;
    }
    if (ch === '"' && cell === '') quoted = true;
    else if (ch === delimiter) {
      row.push(cell);
      cell = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(cell);
      rows.push(row);
      row = [];
      cell = '';
      if (rows.length > ROWS_MAX) return { ok: false, problem: 'unreadable' };
    } else cell += ch;
  }
  if (cell !== '' || row.length) {
    row.push(cell);
    rows.push(row);
  }
  return toSheet(rows);
}

function count(s: string, ch: string): number {
  return s.split(ch).length - 1;
}

// --------------------------------------------------------------- XLSX ----

export function parseXlsx(bytes: Uint8Array): Sheet {
  let files: Record<string, Uint8Array>;
  let total = 0;
  try {
    files = unzipSync(bytes, {
      filter: (info: UnzipFileInfo) => {
        const wanted = info.name === 'xl/workbook.xml' || info.name === 'xl/_rels/workbook.xml.rels' || info.name === 'xl/sharedStrings.xml' || /^xl\/worksheets\/sheet\d{1,3}\.xml$/.test(info.name);
        if (!wanted) return false;
        total += info.originalSize;
        if (info.originalSize > UNZIPPED_MAX_BYTES || total > UNZIPPED_MAX_BYTES) throw new RangeError('too large unzipped');
        return true;
      },
    });
  } catch {
    return { ok: false, problem: 'unreadable' };
  }
  const xml = (name: string): Document | null => {
    const data = files[name];
    if (!data) return null;
    const doc = new DOMParser().parseFromString(new TextDecoder().decode(data), 'application/xml');
    return doc.getElementsByTagName('parsererror').length ? null : doc;
  };
  const sheetPath = firstSheetPath(xml('xl/workbook.xml'), xml('xl/_rels/workbook.xml.rels'));
  const sheet = sheetPath ? xml(sheetPath) : null;
  if (!sheet) return { ok: false, problem: 'unreadable' };
  const shared = sharedStrings(xml('xl/sharedStrings.xml'));

  const rows: (string[] | undefined)[] = [];
  for (const rowEl of Array.from(byLocal(sheet, 'row'))) {
    const rowIndex = Number(rowEl.getAttribute('r') ?? rows.length + 1) - 1;
    if (!Number.isInteger(rowIndex) || rowIndex < 0 || rowIndex >= ROWS_MAX) continue;
    const row: (string | undefined)[] = [];
    for (const c of Array.from(byLocal(rowEl, 'c'))) {
      const col = columnIndex(c.getAttribute('r') ?? '');
      if (col < 0 || col >= COLS_MAX) continue;
      row[col] = cellText(c, shared);
    }
    rows[rowIndex] = Array.from(row, (v) => v ?? '');
  }
  return toSheet(Array.from(rows, (r) => r ?? []));
}

function byLocal(node: Document | Element, name: string): HTMLCollectionOf<Element> {
  return node.getElementsByTagNameNS('*', name);
}

function firstSheetPath(workbook: Document | null, rels: Document | null): string | null {
  const first = workbook ? byLocal(workbook, 'sheet')[0] : undefined;
  const rid = first?.getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships', 'id') ?? first?.getAttribute('r:id');
  if (rid && rels) {
    for (const rel of Array.from(byLocal(rels, 'Relationship'))) {
      if (rel.getAttribute('Id') !== rid) continue;
      const target = (rel.getAttribute('Target') ?? '').replace(/^\/?xl\//, '');
      const path = `xl/${target}`;
      return /^xl\/worksheets\/sheet\d{1,3}\.xml$/.test(path) ? path : null;
    }
  }
  return 'xl/worksheets/sheet1.xml';
}

function sharedStrings(doc: Document | null): string[] {
  if (!doc) return [];
  return Array.from(byLocal(doc, 'si')).map((si) => Array.from(byLocal(si, 't')).map((t) => t.textContent).join(''));
}

function cellText(c: Element, shared: readonly string[]): string {
  const type = c.getAttribute('t');
  if (type === 'inlineStr') return Array.from(byLocal(c, 't')).map((t) => t.textContent).join('');
  const v = byLocal(c, 'v')[0]?.textContent ?? '';
  if (type === 's') {
    const i = Number(v);
    return Number.isInteger(i) && i >= 0 ? (shared[i] ?? '') : '';
  }
  // Numbers, booleans, formulas' cached values: the text as stored.
  return v;
}

/** 'C12' → 2. */
export function columnIndex(ref: string): number {
  const letters = /^([A-Z]{1,3})\d+$/.exec(ref)?.[1];
  if (!letters) return -1;
  let n = 0;
  for (const ch of letters) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

function toSheet(rows: readonly (readonly string[])[]): Sheet {
  const width = Math.min(COLS_MAX, Math.max(0, ...rows.map((r) => r.length)));
  const columns: Column[] = [];
  for (let c = 0; c < width; c++) {
    const cells = rows.map((r) => cleanName(r[c] ?? ''));
    if (!cells.some(Boolean)) continue;
    columns.push({ letter: String.fromCharCode(65 + c), header: cells[0] ?? '', cells });
  }
  return columns.length ? { ok: true, columns } : { ok: false, problem: 'empty' };
}

// -------------------------------------------------------------- names ----

/** The names of one column (or of a pasted text), cleaned and checked. */
export function namesFrom(cells: readonly string[], skipFirstRow: boolean): NameList {
  const raw = skipFirstRow ? cells.slice(1) : cells;
  const names: string[] = [];
  let emptySkipped = 0;
  let cleaned = false;
  for (const cell of raw) {
    const name = cleanName(cell);
    if (name !== cell.replace(/\s+/g, ' ').trim()) cleaned = true;
    if (!name) {
      emptySkipped++;
      continue;
    }
    names.push(name);
  }
  const tooLong = names.flatMap((n, i) => (Array.from(n).length > NAME_MAX ? [i + 1] : []));
  const seen = new Map<string, number>();
  for (const n of names) seen.set(n.toLocaleLowerCase(), (seen.get(n.toLocaleLowerCase()) ?? 0) + 1);
  const repeated = [...new Set(names.filter((n) => (seen.get(n.toLocaleLowerCase()) ?? 0) > 1))];
  return { names, emptySkipped, tooLong, repeated, cleaned };
}

/** Pasted text (a column copied from Excel arrives one cell per line, tabs between columns): the first column. */
export function namesFromPaste(text: string): NameList {
  const lines = text.replace(/^\uFEFF/, '').split(/\r?\n/);
  while (lines.length && (lines[lines.length - 1] ?? '').trim() === '') lines.pop();
  return namesFrom(lines.map((l) => l.split('\t')[0] ?? ''), false);
}
