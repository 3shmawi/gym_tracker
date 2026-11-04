import { useEffect, useRef, useState } from 'preact/hooks';
import { linkHandler, navigate, navigateNow, pathOf, type Route } from '../app/router';
import { useOnline } from '../core/online';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n } from '../i18n';
import { joinUrl } from '../invites/qr';
import { namesFromPaste } from '../invites/namesFile';
import { BATCH_MAX, NAME_MAX, normalizePermissions, type AddResult, type MembersRepository, type Permissions } from '../members/members';
import { Dialog } from '../ui/Dialog';
import { Icon } from '../ui/icons';
import { failureText, formatDate } from '../ui/memberText';
import { NamesImport } from '../ui/NamesImport';
import { CARDS_PER_PAGE, PrintSheet, usePrint, type PrintCard } from '../ui/PrintSheet';
import { drawChecked, logoFor } from '../ui/qrCards';
import { StateBlock } from '../ui/states';
import { useLeaveWarning } from './useMembersList';

type Step = 'names' | 'making' | 'codes' | 'print';

interface Checked {
  readonly name: string;
  readonly code: string;
  readonly expiresAt: Date;
  readonly canvas: HTMLCanvasElement;
  readonly verified: boolean;
}

type CodeRow = Extract<AddResult, { ok: true }>;
const isCode = (r: AddResult): r is CodeRow => r.ok;
type FailedRow = Extract<AddResult, { ok: false }>;
const isFailed = (r: AddResult): r is FailedRow => !r.ok;

const NAMES_TEXT_MAX = 8000;

export function AddMembersPage({
  gym,
  role,
  userId,
  members,
  loadLogo,
}: {
  readonly gym: ManagedGym;
  readonly role: 'trainee' | 'captain';
  readonly userId: string;
  readonly members: MembersRepository;
  readonly loadLogo: (logoPath: string | null) => Promise<ImageBitmap | null>;
}) {
  const { t, lang } = useI18n();
  const online = useOnline();
  const [step, setStep] = useState<Step>('names');
  const [text, setText] = useState('');
  const [perms, setPerms] = useState<Permissions>({ editTargets: true, editPlan: false, buildOwnPlan: false });
  const [progress, setProgress] = useState({ done: 0, total: 0 });
  const [results, setResults] = useState<readonly AddResult[]>([]);
  const [startError, setStartError] = useState('');
  const [retrying, setRetrying] = useState(false);
  const [notice, setNotice] = useState('');
  const [cards, setCards] = useState<readonly Checked[]>([]);
  const [qrRetries, setQrRetries] = useState(0);
  const [leaveTo, setLeaveTo] = useState<Route | null>(null);
  const alive = useRef(true);
  const stillHere = () => alive.current;
  const personId = useRef<string | null>(null);
  const logo = useRef<Promise<ImageBitmap | null> | null>(null);
  const print = usePrint();
  useLeaveWarning(step !== 'names', `${t('add.leaveTitle')} ${t('add.leaveBody')}`);

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  const listRoute: Route = { name: 'members', gymId: gym.id };
  const go = (route: Route) => {
    if (step === 'names') navigate(route);
    else setLeaveTo(route);
  };
  const back = (
    <a
      class="btn ghost sm back"
      href={pathOf(listRoute)}
      onClick={(event) => {
        if (step === 'names') {
          linkHandler(listRoute)(event);
        } else if (!event.defaultPrevented && event.button === 0) {
          event.preventDefault();
          go(listRoute);
        }
      }}
    >
      <span class="flip" aria-hidden="true"><Icon name="chevronLeft" /></span>
      {t('nav.members')}
    </a>
  );

  if (role === 'captain' && gym.role !== 'owner') {
    return (
      <section class="stack narrow">
        {back}
        <StateBlock icon="lock" title={t('add.onlyOwnerTitle')}>
          <p class="sub">{t('add.onlyOwnerBody')}</p>
        </StateBlock>
      </section>
    );
  }

  const list = namesFromPaste(text);
  const count = list.names.length;
  const tooMany = count > BATCH_MAX;
  const tooLong = list.tooLong.length > 0;
  const canMake = count > 0 && !tooMany && !tooLong && online;
  const oks = results.filter(isCode);
  const failedRows = results.filter(isFailed);

  const gatherPerson = async (): Promise<string | null> => {
    if (personId.current) return personId.current;
    const result = await members.myPersonId(userId);
    if (!result.ok) {
      setStartError(failureText(t, result.failure));
      return null;
    }
    if (!result.value) {
      setStartError(t('add.noPerson'));
      return null;
    }
    personId.current = result.value;
    return result.value;
  };

  const makeCodes = async () => {
    if (!canMake) return;
    setStartError('');
    const person = await gatherPerson();
    if (!person || !stillHere()) return;
    const names = list.names;
    setResults([]);
    setNotice('');
    setProgress({ done: 0, total: names.length });
    setStep('making');
    const made: AddResult[] = [];
    // One name per call, so the progress is real; add() reports each name on its own.
    for (const name of names) {
      const result = await members.add(gym.id, person, [name], role, role === 'trainee' ? normalizePermissions(perms) : { editTargets: false, editPlan: false, buildOwnPlan: false });
      if (result.ok) made.push(...result.value);
      else made.push({ ok: false, name, failure: result.failure });
      if (!stillHere()) return;
      setProgress({ done: made.length, total: names.length });
    }
    setResults(made);
    setStep('codes');
  };

  const retryFailed = async () => {
    if (retrying) return;
    setRetrying(true);
    setNotice('');
    const next: AddResult[] = [];
    for (const row of results) {
      if (row.ok) {
        next.push(row);
        continue;
      }
      if (row.membershipId) {
        const code = await members.newCode(row.membershipId, row.name, 'join');
        next.push(code.ok ? { ok: true, code: code.value } : { ok: false, name: row.name, failure: code.failure, membershipId: row.membershipId });
      } else {
        const person = await gatherPerson();
        if (!person) {
          next.push(row);
          continue;
        }
        const again = await members.add(gym.id, person, [row.name], role, role === 'trainee' ? normalizePermissions(perms) : { editTargets: false, editPlan: false, buildOwnPlan: false });
        if (again.ok) next.push(...again.value);
        else next.push({ ok: false, name: row.name, failure: again.failure });
      }
      if (!stillHere()) return;
    }
    setResults(next);
    setRetrying(false);
  };

  const copyLinks = async () => {
    const lines = oks.map((r) => `${r.code.name}\t${joinUrl(r.code.code)}`).join('\n');
    try {
      await navigator.clipboard.writeText(lines);
      setNotice(t('add.copied'));
    } catch {
      setNotice(t('add.copyFailed'));
    }
  };

  const checkAndPrint = async () => {
    logo.current ??= logoFor(loadLogo, gym.logoPath);
    const bitmap = await logo.current;
    if (!stillHere()) return;
    setCards(oks.map((r) => ({ name: r.code.name, code: r.code.code, expiresAt: r.code.expiresAt, ...drawChecked(r.code.code, bitmap) })));
    setQrRetries(0);
    setNotice('');
    setStep('print');
  };

  const retryQr = async (withLogo: boolean) => {
    const bitmap = withLogo ? await (logo.current ??= logoFor(loadLogo, gym.logoPath)) : null;
    if (!stillHere()) return;
    setCards((all) => all.map((c) => (c.verified ? c : { ...c, ...drawChecked(c.code, bitmap) })));
    setQrRetries((n) => n + 1);
  };

  const verified = cards.filter((c) => c.verified);
  const unverified = cards.filter((c) => !c.verified);
  const printable: PrintCard[] = verified;
  const stepClass = (s: Step) => `badge${(s === 'codes' ? step === 'codes' || step === 'making' : step === s) ? ' ok' : ''}`;

  return (
    <section class="stack narrow">
      <div class="screen-only stack">
        {back}
        <h1 class="h1">{role === 'captain' ? t('add.titleCaptain') : t('add.titleTrainees')}</h1>
        <ol class="steps" aria-label={t('add.steps')}>
          <li><span class={stepClass('names')} aria-current={step === 'names' ? 'step' : undefined}>{t('add.step1')}</span></li>
          <li><span class={stepClass('codes')} aria-current={step === 'codes' || step === 'making' ? 'step' : undefined}>{t('add.step2')}</span></li>
          <li><span class={stepClass('print')} aria-current={step === 'print' ? 'step' : undefined}>{t('add.step3')}</span></li>
        </ol>

        {step === 'names' ? (
          <form
            class="panel"
            noValidate
            onSubmit={(event) => {
              event.preventDefault();
              void makeCodes();
            }}
          >
            <div class="field">
              <label for="names">{t('add.names')}</label>
              <textarea
                id="names"
                class={`in names${tooMany || tooLong ? ' bad' : ''}`}
                value={text}
                maxLength={NAMES_TEXT_MAX}
                aria-invalid={tooMany || tooLong}
                aria-describedby="names-hint names-notes"
                onInput={(event) => { setText(event.currentTarget.value); }}
              />
              <span id="names-hint" class="hint">{t('add.namesHint', { max: BATCH_MAX, length: NAME_MAX })}</span>
              <div id="names-notes" class="stack-xs">
                {tooMany ? (
                  <span class="errt">
                    <Icon name="alert" />
                    <span>
                      {t('add.errTooMany', { max: BATCH_MAX, count })}{' '}
                      <button type="button" class="btn sm" onClick={() => { setText(list.names.slice(0, BATCH_MAX).join('\n')); }}>{t('add.keepFirst', { max: BATCH_MAX })}</button>
                    </span>
                  </span>
                ) : null}
                {tooLong ? (
                  <span class="errt">
                    <Icon name="alert" />
                    {list.tooLong.length === 1
                      ? t('add.errTooLong', { line: list.tooLong[0] ?? 0, max: NAME_MAX })
                      : t('add.errTooLongMore', { line: list.tooLong.slice(0, 8).join(', '), max: NAME_MAX })}
                  </span>
                ) : null}
                {list.cleaned ? <span class="hint">{t('add.cleaned')}</span> : null}
                {list.emptySkipped > 0 ? <span class="hint">{t('add.skippedEmpty', { count: list.emptySkipped })}</span> : null}
                {list.repeated.length > 0 ? <span class="hint plain-text">{t('add.repeated', { names: list.repeated.slice(0, 5).join(', ') })}</span> : null}
              </div>
              <span class="cap" role="status">{t('add.ready', { count })}</span>
            </div>
            <NamesImport onUse={(names) => { setText(names.join('\n')); }} />
            {role === 'trainee' ? (
              <fieldset class="perms bare">
                <legend class="h2">{t('add.permsLegend')}</legend>
                <label class="chk">
                  <input
                    type="checkbox"
                    checked={perms.editTargets || perms.editPlan}
                    disabled={perms.editPlan}
                    onChange={(event) => { setPerms({ ...perms, editTargets: event.currentTarget.checked }); }}
                  />
                  <span><b>{t('member.permTargets')}</b><span class="cap">{t('member.permTargetsHint')}</span></span>
                </label>
                <label class="chk">
                  <input type="checkbox" checked={perms.editPlan} onChange={(event) => { setPerms(normalizePermissions({ ...perms, editPlan: event.currentTarget.checked })); }} />
                  <span><b>{t('member.permPlan')}</b><span class="cap">{t('member.permPlanHint')}</span></span>
                </label>
                <label class="chk">
                  <input type="checkbox" checked={perms.buildOwnPlan} onChange={(event) => { setPerms({ ...perms, buildOwnPlan: event.currentTarget.checked }); }} />
                  <span><b>{t('member.permOwn')}</b><span class="cap">{t('member.permOwnHint')}</span></span>
                </label>
              </fieldset>
            ) : null}
            {startError ? <div class="banner err" role="alert"><Icon name="alert" />{startError}</div> : null}
            <div class="acts-row end">
              {online ? null : <span class="hint grow">{t('add.offlineHint')}</span>}
              <button type="submit" class="btn pri" disabled={!canMake}>
                {count === 0 ? t('add.makeNone') : count === 1 ? t('add.makeOne') : t('add.make', { count })}
              </button>
            </div>
          </form>
        ) : null}

        {step === 'making' ? (
          <div class="panel" role="status" aria-live="polite">
            <p class="sub"><b>{t('add.progress', { done: progress.done, total: progress.total })}</b></p>
            <progress class="bar" max={progress.total} value={progress.done} aria-hidden="true" />
          </div>
        ) : null}

        {step === 'codes' ? (
          <div class="stack">
            {oks.length > 0 ? (
              <div class="banner info" role="status">
                <Icon name="info" />
                {t('add.codesBanner')}
              </div>
            ) : null}
            {failedRows.length > 0 ? (
              <div class="banner off stack-xs" role="alert">
                <span class="row-icon">
                  <Icon name="alert" />
                  <b>{oks.length === 0 ? t('add.partialNone') : t('add.partial', { done: oks.length, total: results.length })}</b>
                </span>
                <span>{t('add.partialWho')}</span>
                <ul class="plain-list">
                  {failedRows.map((row, i) => (
                    <li key={i}>
                      <b class="plain">{row.name}</b>
                      {' · '}
                      <span>{row.membershipId ? t('add.waitingNote') : failureText(t, row.failure, row.name)}</span>
                    </li>
                  ))}
                </ul>
                <span>
                  <button type="button" class="btn pri sm" disabled={!online || retrying} onClick={() => void retryFailed()}>
                    {retrying ? t('add.retrying') : t('add.retry', { count: failedRows.length })}
                  </button>
                </span>
              </div>
            ) : null}
            <div class="live" role="status">{notice}</div>
            {oks.length > 0 ? (
              <>
                <div class="tblbox" tabIndex={0} role="region" aria-label={t('add.step2')}>
                  <table class="t codes-t">
                    <thead>
                      <tr>
                        <th scope="col">{t('add.colName')}</th>
                        <th scope="col">{t('add.colCode')}</th>
                        <th scope="col">{t('add.colExpires')}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {oks.map((r) => (
                        <tr key={r.code.code}>
                          <td><b class="plain">{r.code.name}</b></td>
                          <td><span class="code">{r.code.code}</span></td>
                          <td class="num">{formatDate(lang, r.code.expiresAt)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div class="acts-row end">
                  <button type="button" class="btn" onClick={() => void copyLinks()}>{t('add.copyLinks')}</button>
                  <button type="button" class="btn pri" onClick={() => void checkAndPrint()}>
                    {oks.length === 1 ? t('add.checkOne') : t('add.check', { count: oks.length })}
                  </button>
                </div>
              </>
            ) : null}
          </div>
        ) : null}

        {step === 'print' ? (
          <div class="panel">
            {unverified.length === 0 ? (
              <div class="banner ok" role="status">
                <Icon name="check" />
                <span>{t('add.verified', { ok: verified.length, total: cards.length })}</span>
              </div>
            ) : (
              <>
                <div class="banner err" role="alert">
                  <Icon name="alert" />
                  <span>{t('add.verifyFailed', { ok: verified.length, bad: unverified.length, total: cards.length })}</span>
                </div>
                <p class="sub plain-text">{t('add.verifyFailedBody', { names: unverified.map((c) => c.name).join(', ') })}</p>
              </>
            )}
            {verified.length > 0 ? (
              <>
                <p class="sub">{t('add.cardsSummary', { cards: verified.length, pages: Math.ceil(verified.length / CARDS_PER_PAGE) })}</p>
                <p class="cap">{t('add.printHint')}</p>
              </>
            ) : null}
            <div class="acts-row">
              {verified.length > 0 ? (
                <button type="button" class="btn pri" onClick={print.request}>
                  {verified.length === 1 ? t('add.printOne') : t('add.print', { count: verified.length })}
                </button>
              ) : null}
              {unverified.length > 0 ? (
                <button type="button" class="btn" onClick={() => void retryQr(true)}>{t('add.retryQr')}</button>
              ) : null}
              {unverified.length > 0 && qrRetries > 0 ? (
                <button type="button" class="btn" onClick={() => void retryQr(false)}>{t('add.retryNoLogo')}</button>
              ) : null}
              <button type="button" class="btn ghost" onClick={() => { setStep('codes'); }}>{t('add.backToCodes')}</button>
              <button type="button" class="btn ghost" onClick={() => { go(listRoute); }}>{t('add.done')}</button>
            </div>
          </div>
        ) : null}
      </div>

      {print.printing && printable.length > 0 ? <PrintSheet gymName={gym.name} cards={printable} /> : null}

      {leaveTo ? (
        <Dialog titleId="leave-title" onClose={() => { setLeaveTo(null); }}>
          <h2 class="h2" id="leave-title">{t('add.leaveTitle')}</h2>
          <p class="sub">{t('add.leaveBody')}</p>
          <div class="acts">
            <button type="button" class="btn pri" onClick={() => { setLeaveTo(null); }}>{t('add.stay')}</button>
            <button
              type="button"
              class="btn"
              onClick={() => {
                const route = leaveTo;
                setLeaveTo(null);
                navigateNow(route);
              }}
            >
              {t('add.leave')}
            </button>
          </div>
        </Dialog>
      ) : null}
    </section>
  );
}
