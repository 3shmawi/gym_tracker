import { useRef, useState } from 'preact/hooks';
import { cleanName } from '../core/text';
import { useI18n } from '../i18n';
import { namesFrom, readNamesFile, type Column, type FileProblem, type Sheet } from '../invites/namesFile';
import { BATCH_MAX } from '../members/members';
import { Icon } from './icons';

// "Upload Excel or CSV" (board 1.7). The file is read in the browser only;
// the person picks the column, says whether row 1 is a title, and may start
// at a later row (for a file with more than 50 names). "Use these names"
// hands the cleaned names to the caller, which puts them in the textarea.

type Loaded =
  | { readonly state: 'idle' }
  | { readonly state: 'reading' }
  | { readonly state: 'problem'; readonly problem: FileProblem }
  | { readonly state: 'sheet'; readonly fileName: string; readonly columns: readonly Column[] };

const HEADER_MAX = 30;

/** The file row (1-based) of the n-th (0-based) non-empty name, or null. */
function rowOfNameAt(cells: readonly string[], firstRow: number, skipFirst: boolean, n: number): number | null {
  let seen = 0;
  for (let i = skipFirst ? 1 : 0; i < cells.length; i++) {
    if (!cleanName(cells[i])) continue;
    if (seen === n) return firstRow + i;
    seen++;
  }
  return null;
}

export function NamesImport({ onUse }: { readonly onUse: (names: readonly string[]) => void }) {
  const { t } = useI18n();
  const [loaded, setLoaded] = useState<Loaded>({ state: 'idle' });
  const [column, setColumn] = useState(0);
  const [skipFirst, setSkipFirst] = useState(true);
  const [startRow, setStartRow] = useState('1');
  const input = useRef<HTMLInputElement>(null);

  const pick = async (file: File | undefined) => {
    if (!file) return;
    setLoaded({ state: 'reading' });
    let sheet: Sheet;
    try {
      sheet = await readNamesFile(file);
    } catch {
      sheet = { ok: false, problem: 'unreadable' };
    }
    if (input.current) input.current.value = '';
    if (!sheet.ok) {
      setLoaded({ state: 'problem', problem: sheet.problem });
      return;
    }
    setColumn(0);
    setSkipFirst(true);
    setStartRow('1');
    setLoaded({ state: 'sheet', fileName: cleanName(file.name).slice(0, 80), columns: sheet.columns });
  };

  const problemText = (problem: FileProblem): string => {
    switch (problem) {
      case 'too_big':
        return t('imp.tooBig');
      case 'locked':
        return t('imp.locked');
      case 'unreadable':
        return t('imp.unreadable');
      case 'empty':
        return t('imp.empty');
      default:
        return t('imp.wrongType');
    }
  };

  const chooser = (label: string) => (
    <>
      <input
        ref={input}
        id="names-file"
        class="file-in"
        type="file"
        accept=".xlsx,.csv"
        onChange={(event) => void pick(event.currentTarget.files?.[0])}
      />
      <label class="btn" for="names-file">{label}</label>
    </>
  );

  if (loaded.state === 'sheet') {
    const col = loaded.columns[Math.min(column, loaded.columns.length - 1)];
    const cells = col?.cells ?? [];
    const start = Math.max(1, Math.min(Number.parseInt(startRow, 10) || 1, Math.max(cells.length, 1)));
    const skip = skipFirst && start === 1;
    const list = namesFrom(cells.slice(start - 1), skip);
    const count = list.names.length;
    const over = count > BATCH_MAX;
    const nextRow = over ? rowOfNameAt(cells.slice(start - 1), start, skip, BATCH_MAX) : null;
    const firstCell = cleanName(cells[0]);
    return (
      <div class="drop stack-sm">
        <p class="sub"><b class="num plain">{t('imp.firstSheet', { file: loaded.fileName })}</b></p>
        <div class="field">
          <label for="imp-col">{t('imp.column')}</label>
          <select id="imp-col" class="in" value={String(column)} onChange={(event) => { setColumn(Number(event.currentTarget.value)); }}>
            {loaded.columns.map((c, i) => {
              const header = cleanName(c.header).slice(0, HEADER_MAX);
              return <option key={c.letter} value={String(i)}>{header ? `${c.letter} · ${header}` : c.letter}</option>;
            })}
          </select>
        </div>
        <label class="chk plain-pad">
          <input type="checkbox" checked={skipFirst} onChange={(event) => { setSkipFirst(event.currentTarget.checked); }} />
          <span>
            <b>{t('imp.titleRow')}</b>
            {firstCell ? <span class="cap plain">{t('imp.titleRowHint', { first: firstCell.slice(0, 40) })}</span> : null}
          </span>
        </label>
        <div class="field narrow-field">
          <label for="imp-start">{t('imp.startRow')}</label>
          <input id="imp-start" class="in" type="number" inputMode="numeric" min={1} value={startRow} onInput={(event) => { setStartRow(event.currentTarget.value); }} aria-describedby="imp-start-hint" />
          <span id="imp-start-hint" class="hint">{t('imp.startRowHint')}</span>
        </div>
        {list.emptySkipped > 0 ? <div class="banner off" role="status"><Icon name="alert" />{t('imp.skippedEmpty', { count: list.emptySkipped })}</div> : null}
        {list.repeated.length > 0 ? (
          <div class="banner info"><Icon name="info" /><span class="plain-text">{t('imp.repeated', { name: list.repeated[0] ?? '' })}</span></div>
        ) : null}
        {list.tooLong.length > 0 ? <p class="sub">{t('imp.tooLongNote')}</p> : null}
        {count === 0 ? (
          <div class="banner err" role="alert"><Icon name="alert" />{t('imp.noNames')}</div>
        ) : (
          <div class="panel peek">
            {list.names.slice(0, 3).map((n, i) => <span key={i} class="plain">{n}</span>)}
            {count > 3 ? <span class="cap">{t('imp.andMore', { count: count - 3 })}</span> : null}
          </div>
        )}
        {over ? (
          <>
            <div class="banner info" role="status"><Icon name="info" /><span>{t('imp.found', { count, max: BATCH_MAX })}</span></div>
            {nextRow ? <p class="sub">{t('imp.firstGo', { max: BATCH_MAX, row: nextRow })}</p> : null}
          </>
        ) : null}
        <div class="acts-row">
          <button
            type="button"
            class="btn pri"
            disabled={count === 0}
            onClick={() => {
              onUse(list.names.slice(0, BATCH_MAX));
              setLoaded({ state: 'idle' });
            }}
          >
            {over ? t('imp.useFirst', { max: BATCH_MAX }) : t('imp.use', { count })}
          </button>
          <button type="button" class="btn ghost" onClick={() => { setLoaded({ state: 'idle' }); }}>{t('imp.cancel')}</button>
        </div>
      </div>
    );
  }

  return (
    <div class="drop stack-sm">
      {loaded.state === 'problem' ? (
        <>
          <div class="banner err" role="alert"><Icon name="alert" />{problemText(loaded.problem)}</div>
          {loaded.problem === 'old_excel' ? <p class="sub">{t('imp.oldExcel')}</p> : null}
          <div>{chooser(t('imp.chooseOther'))}</div>
          <span class="cap">{t('imp.pasteWorks')}</span>
        </>
      ) : (
        <>
          <div>{chooser(t('imp.upload'))}</div>
          {loaded.state === 'reading' ? <span class="cap" role="status">{t('imp.reading')}</span> : <span class="cap">{t('imp.fileNote')}</span>}
        </>
      )}
    </div>
  );
}
