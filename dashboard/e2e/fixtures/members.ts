import type { Page } from '@playwright/test';
import { strToU8, zipSync } from 'fflate';
import { GYM_A, mockSupabase, prefs, signedInBefore, type Mock, type MockOptions } from './supabase';
import type { Lang, Theme } from './helpers';

export const isPhone = (page: Page): boolean => (page.viewportSize()?.width ?? 1280) <= 720;

export interface OpenOptions extends MockOptions {
  lang?: Lang;
  theme?: Theme;
  /** Path to open (default: the members list of gym A). */
  path?: string;
  /** Keep window.print() from opening a dialog (the print sheet then stays for the test). Default true. */
  stubPrint?: boolean;
}

export const MEMBERS_PATH = `/g/${GYM_A.id}/members`;
export const ADD_PATH = `${MEMBERS_PATH}/add`;
export const ADD_CAPTAIN_PATH = `${MEMBERS_PATH}/add-captain`;
export const memberPath = (id: string) => `${MEMBERS_PATH}/${id}`;

/** A signed-in captain or owner with the fake project, then the page. */
export async function open(page: Page, options: OpenOptions = {}): Promise<Mock> {
  const { lang = 'en', theme = 'light', path = MEMBERS_PATH, stubPrint = true, ...mockOptions } = options;
  await prefs(page, lang, theme);
  await signedInBefore(page);
  const mock = await mockSupabase(page, { gyms: [{ ...GYM_A, role: 'owner' }], ...mockOptions });
  if (stubPrint) {
    await page.addInitScript(() => {
      // The real print dialog can't be driven; the sheet stays in the page so the print layout can be checked.
      window.print = () => {
        (window as unknown as { __printCalls: number }).__printCalls = ((window as unknown as { __printCalls?: number }).__printCalls ?? 0) + 1;
      };
    });
  }
  await page.goto(path);
  return mock;
}

/** The row (desktop table) or card (phone list) of a member on the members list. */
export function rowOf(page: Page, name: string) {
  return isPhone(page) ? page.getByRole('listitem').filter({ hasText: name }) : page.getByRole('row').filter({ hasText: name });
}

// ------------------------------------------------------------------ files ----

const NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/**
 * A real .xlsx (zip of XML parts) with one sheet. `rows[r][c]` is text, a
 * number, or null for an empty cell. Text goes to the shared strings table,
 * as Excel stores it.
 */
export function xlsx(rows: readonly (readonly (string | number | null)[])[]): Buffer {
  const shared: string[] = [];
  const cell = (r: number, c: number, value: string | number | null) => {
    const ref = `${String.fromCharCode(65 + c)}${r + 1}`;
    if (value === null) return `<c r="${ref}"/>`;
    if (typeof value === 'number') return `<c r="${ref}"><v>${value}</v></c>`;
    let i = shared.indexOf(value);
    if (i < 0) i = shared.push(value) - 1;
    return `<c r="${ref}" t="s"><v>${i}</v></c>`;
  };
  const sheetRows = rows.map((row, r) => `<row r="${r + 1}">${row.map((value, c) => cell(r, c, value)).join('')}</row>`).join('');
  const zip = zipSync({
    '[Content_Types].xml': strToU8('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>'),
    'xl/workbook.xml': strToU8(`<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="${NS}" xmlns:r="${REL}"><sheets><sheet name="Roster" sheetId="1" r:id="rId1"/></sheets></workbook>`),
    'xl/_rels/workbook.xml.rels': strToU8(`<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${REL}/worksheet" Target="worksheets/sheet1.xml"/></Relationships>`),
    'xl/worksheets/sheet1.xml': strToU8(`<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="${NS}"><sheetData>${sheetRows}</sheetData></worksheet>`),
    'xl/sharedStrings.xml': strToU8(`<?xml version="1.0" encoding="UTF-8"?><sst xmlns="${NS}" count="${shared.length}" uniqueCount="${shared.length}">${shared.map((t) => `<si><t>${esc(t)}</t></si>`).join('')}</sst>`),
  });
  return Buffer.from(zip);
}

/** The names roster the import tests use: a title row, 4 names (one repeated) and an empty cell. */
export const ROSTER = xlsx([
  ['Joined', 'Name'],
  [45_000, 'Nour Hassan'],
  [45_001, 'Salma Adel'],
  [45_002, null],
  [45_003, 'Omar Khaled'],
  [45_004, 'Nour Hassan'],
]);

export async function chooseFile(page: Page, file: { name: string; mimeType: string; buffer: Buffer }): Promise<void> {
  await page.locator('#names-file').setInputFiles(file);
}
