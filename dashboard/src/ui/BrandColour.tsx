import { useEffect, useRef, useState } from 'preact/hooks';
import type { Failure } from '../core/failure';
import { azmBrand, contrastOf, deriveBrand, nearErrorRed, parseBrandColor, ratioText, readTyped, type BrandValues, type Mode } from '../gyms/brandColor';
import type { ManagedGym } from '../gyms/gyms';
import type { GymSettingsRepository } from '../gyms/settings';
import { useI18n, type MessageKey } from '../i18n';
import { Icon } from './icons';

// Gym brand colour (D6, docs/designs/gym_brand_colours.md): the owner picks
// one colour; this shows what the app makes of it in light and dark, the
// three contrast numbers, and a phone preview. Captains see the saved
// colour read-only. The dashboard itself stays in Azm's colours.

export const PRESETS: readonly { readonly hex: string; readonly name: MessageKey }[] = [
  { hex: '#facc15', name: 'brand.yellow' },
  { hex: '#f97316', name: 'brand.orange' },
  { hex: '#dc2626', name: 'brand.red' },
  { hex: '#ec4899', name: 'brand.pink' },
  { hex: '#6d28d9', name: 'brand.purple' },
  { hex: '#1e3a8a', name: 'brand.navy' },
  { hex: '#06b6d4', name: 'brand.cyan' },
];

export type PreviewScreen = 'home' | 'workout' | 'sheet';
const SCREENS: readonly { readonly id: PreviewScreen; readonly label: MessageKey }[] = [
  { id: 'home', label: 'brand.pvHome' },
  { id: 'workout', label: 'brand.pvWorkout' },
  { id: 'sheet', label: 'brand.pvSheet' },
];

/**
 * Colours reach the page through the CSSOM (`style.setProperty`), never a
 * style attribute, so the CSP (`style-src 'self'`) is unchanged.
 */
function useColours(values: Readonly<Record<string, string>>) {
  const ref = useRef<HTMLDivElement>(null);
  const key = Object.entries(values).map(([k, v]) => `${k}:${v}`).join(';');
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    for (const [name, value] of Object.entries(values)) el.style.setProperty(name, value);
    // `key` is `values` as text: the effect runs when a colour changes.
  }, [key]);
  return ref;
}

const colourVars = (v: BrandValues) => ({ '--b-brand': v.brand, '--b-on': v.onBrand, '--b-accent': v.primary, '--b-glow1': v.glowStart, '--b-glow2': v.glowEnd });

/** A small drawing of the app in one mode, in the given colours. Decorative text, read as one image. */
export function PhonePreview({ values, mode, screen, gymName, label }: { readonly values: BrandValues; readonly mode: Mode; readonly screen: PreviewScreen; readonly gymName: string; readonly label: string }) {
  const { t } = useI18n();
  const ref = useColours(colourVars(values));
  const initials = Array.from(gymName.trim()).slice(0, 2).join('').toUpperCase() || '?';
  const home = (
    <>
      <div class="pv-row">
        <span class="pv-chip"><span class="pv-tile">{initials}</span><span class="pv-ellip">{gymName}</span></span>
      </div>
      <div class="pv-h">{t('brand.pvToday')}</div>
      <div class="pv-card">
        {(['brand.pvEx1', 'brand.pvEx2', 'brand.pvEx3'] as const).map((ex, i) => (
          <div key={ex} class="pv-ex">
            <span class="pv-pic"><Icon name="dumbbell" /></span>
            <span class="pv-grow pv-ellip">{t(ex)}</span>
            <span class={`pv-badge ${i === 0 ? 'up' : i === 1 ? 'keep' : 'fresh'}`}>{t(i === 0 ? 'brand.pvUp' : i === 1 ? 'brand.pvKeep' : 'brand.pvNew')}</span>
          </div>
        ))}
      </div>
      <div class="pv-link">{t('brand.pvPlan')}</div>
      <div class="pv-btn">{t('brand.pvStart')}</div>
      <div class="pv-grow" />
      <div class="pv-pill on"><span class="pv-grow"><b>{t('brand.pvGo')}</b></span></div>
    </>
  );
  const workout = (
    <>
      <div class="pv-row"><span class="pv-grow pv-h sm">{t('brand.pvEx1')}</span><span class="pv-link">{t('brand.pvHow')}</span></div>
      <div class="pv-bars"><span class="on" /><span class="on" /><span /><span /></div>
      <div class="pv-photo"><Icon name="image" /></div>
      <div class="pv-card">
        <div class="pv-row"><span class="pv-grow"><b>{t('brand.pvSet')}</b></span><span class="pv-badge up">{t('brand.pvUp')}</span></div>
        <div class="pv-sets"><span class="done">50×12</span><span class="done">52.5×12</span><span class="now">52.5×12</span></div>
      </div>
      <div class="pv-btn">{t('brand.pvLog')}</div>
      <div class="pv-grow" />
      <div class="pv-pill"><span class="pv-ring" /><span class="pv-grow"><b>1:12</b></span><span class="pv-key">+15</span></div>
    </>
  );
  const sheet = (
    <>
      <div class="pv-grow" />
      <div class="pv-sheet">
        <div class="pv-h sm">{t('brand.pvWhere')}</div>
        <div class="pv-opt"><span class="pv-tile azm">A</span><span class="pv-grow pv-ellip">{t('brand.pvSolo')}</span><span class="pv-radio" /></div>
        <div class="pv-opt sel"><span class="pv-tile">{initials}</span><span class="pv-grow pv-ellip">{gymName}</span><span class="pv-radio on"><Icon name="check" /></span></div>
        <div class="pv-btn">{t('brand.pvDone')}</div>
        <div class="pv-danger">{t('brand.pvLeave')}</div>
      </div>
    </>
  );
  return (
    <figure class="pv-fig">
      <div ref={ref} class={`pv ${mode}${screen === 'sheet' ? ' dim' : ''}`} role="img" aria-label={label} data-testid={`preview-${mode}`}>
        <div class="pv-in" aria-hidden="true">{screen === 'home' ? home : screen === 'workout' ? workout : sheet}</div>
      </div>
      <figcaption class="cap">{t(mode === 'light' ? 'brand.light' : 'brand.dark')}</figcaption>
    </figure>
  );
}

function Sample({ values, mode }: { readonly values: BrandValues; readonly mode: Mode }) {
  const { t } = useI18n();
  const ref = useColours(colourVars(values));
  const note = values.adjusted === 0 ? t('brand.asPicked') : t(mode === 'light' ? 'brand.darker' : 'brand.lighter', { percent: values.adjusted });
  return (
    <div ref={ref} class={`bc-sample ${mode}`} data-testid={`sample-${mode}`}>
      <span class="bc-mode">{t(mode === 'light' ? 'brand.light' : 'brand.dark')}</span>
      <span class="bc-fill">{t('brand.pvStart')}</span>
      <span class="bc-accent">{t('brand.pvPlan')}</span>
      <code class="bc-code">{values.brand.toUpperCase()}</code>
      <span class="bc-note">{note}</span>
    </div>
  );
}

const failureKey = (f: Failure): MessageKey => (f.kind === 'forbidden' ? 'set.errForbidden' : f.kind === 'offline' ? 'plan.errOffline' : f.kind === 'session_ended' ? 'fail.session' : f.kind === 'invalid' ? 'brand.errFormat' : 'set.errServer');

export function BrandColourPanel({ gym, settings, online, onChanged }: {
  readonly gym: ManagedGym;
  readonly settings: GymSettingsRepository;
  readonly online: boolean;
  readonly onChanged: () => void;
}) {
  const { t } = useI18n();
  const owner = gym.role === 'owner';
  const [saved, setSaved] = useState<string | null>(gym.brandColor);
  const [text, setText] = useState(gym.brandColor ? gym.brandColor.toUpperCase() : '');
  const [screen, setScreen] = useState<PreviewScreen>('home');
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ readonly tone: 'ok' | 'err'; readonly key: MessageKey } | null>(null);

  const empty = text.trim() === '';
  const typed = readTyped(text);
  // What the preview shows: the typed colour when it can be saved, else Azm's.
  const hex = !empty && typed.ok ? typed.hex : null;
  const problem: MessageKey | null = empty || typed.ok ? null : typed.problem === 'format' ? 'brand.errFormat' : 'brand.errNoColour';
  const values = (mode: Mode) => (hex ? deriveBrand(hex, mode) : azmBrand(mode));
  const light = values('light');
  const dark = values('dark');
  const changed = hex !== saved && !(empty && saved === null);
  const off = !online || busy;

  const save = async (value: string | null) => {
    setBusy(true);
    const r = await settings.setBrandColor(gym.id, value);
    setBusy(false);
    if (r.ok) {
      setSaved(r.value);
      setText(r.value ? r.value.toUpperCase() : '');
      setNote({ tone: 'ok', key: r.value ? 'brand.saved' : 'brand.resetDone' });
      onChanged();
    } else setNote({ tone: 'err', key: failureKey(r.failure) });
  };

  const rows: readonly { readonly label: MessageKey; readonly needs: string; readonly light: number; readonly dark: number }[] = hex
    ? [
        { label: 'brand.checkFill', needs: '3', light: contrastOf(light, 'light').fill, dark: contrastOf(dark, 'dark').fill },
        { label: 'brand.checkOn', needs: '4.5', light: contrastOf(light, 'light').onFill, dark: contrastOf(dark, 'dark').onFill },
        { label: 'brand.checkAccent', needs: '4.5', light: contrastOf(light, 'light').accent, dark: contrastOf(dark, 'dark').accent },
      ]
    : [];

  return (
    <section class="panel full" aria-labelledby="s-brand">
      <div class="stack-sm">
        <h2 class="h2" id="s-brand">{t('brand.title')}</h2>
        <p class="cap">{t(owner ? 'brand.body' : 'brand.bodyCaptain')}</p>
      </div>
      <div class="bc-cols">
        <div class="stack bc-col">
          {owner ? (
            <>
              <div class="bc-pick">
                <div class="field">
                  <label for="brand-pick">{t('brand.pick')}</label>
                  <input id="brand-pick" class="bc-colour" type="color" value={hex ?? '#22c55e'} disabled={off} onInput={(e) => { setText(e.currentTarget.value.toUpperCase()); setNote(null); }} />
                </div>
                <div class="field grow">
                  <label for="brand-hex">{t('brand.code')}</label>
                  <input id="brand-hex" class={`in bc-mono${problem ? ' bad' : ''}`} value={text} maxLength={32} spellcheck={false} autocomplete="off" autocapitalize="characters" dir="ltr" placeholder="#FACC15" aria-invalid={problem !== null} aria-describedby="brand-hex-hint brand-hex-err" disabled={off} onInput={(e) => { setText(e.currentTarget.value); setNote(null); }} />
                  <span class="hint" id="brand-hex-hint">{t('brand.codeHint')}</span>
                  <span class="live-slot" id="brand-hex-err">{problem ? <span class="errt"><Icon name="alert" />{t(problem)}</span> : null}</span>
                </div>
              </div>
              <div class="stack-sm">
                <span class="bc-lbl" id="brand-presets">{t('brand.presets')}</span>
                <div class="bc-presets" role="group" aria-labelledby="brand-presets">
                  {PRESETS.map((p) => <PresetButton key={p.hex} hex={p.hex} label={`${t(p.name)} ${p.hex.toUpperCase()}`} on={hex === p.hex} disabled={off} onPick={() => { setText(p.hex.toUpperCase()); setNote(null); }} />)}
                </div>
              </div>
            </>
          ) : (
            <p><b>{saved ? saved.toUpperCase() : t('brand.none')}</b></p>
          )}

          {hex && nearErrorRed(hex) ? (
            <div class="banner off" role="note"><Icon name="alert" /><span>{t('brand.nearRed')}</span></div>
          ) : null}

          <div class="stack-sm">
            <h3 class="h3">{t('brand.uses')}</h3>
            <div class="bc-samples">
              <Sample values={light} mode="light" />
              <Sample values={dark} mode="dark" />
            </div>
            {hex ? null : <p class="cap">{t('brand.azmNote')}</p>}
          </div>

          {rows.length > 0 ? (
            <div class="stack-sm">
              <h3 class="h3">{t('brand.checks')}</h3>
              <div class="bc-table">
                <table class="t bc-checks">
                  <thead>
                    <tr><th scope="col">{t('brand.check')}</th><th scope="col">{t('brand.needs')}</th><th scope="col">{t('brand.light')}</th><th scope="col">{t('brand.dark')}</th></tr>
                  </thead>
                  <tbody>
                    {rows.map((r) => (
                      <tr key={r.label}>
                        <th scope="row">{t(r.label)}</th>
                        <td><span class="num">{r.needs}:1</span></td>
                        <td><span class="num ok">{ratioText(r.light)}:1</span> <span class="sr-only">{t('brand.pass')}</span></td>
                        <td><span class="num ok">{ratioText(r.dark)}:1</span> <span class="sr-only">{t('brand.pass')}</span></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p class="cap">{t('brand.checksNote')}</p>
            </div>
          ) : null}

          {owner ? (
            <div class="acts-row">
              <button type="button" class="btn pri" disabled={off || hex === null || !changed} onClick={() => void save(hex)}>{t('brand.save')}</button>
              <button type="button" class="btn" disabled={off || saved === null} onClick={() => void save(null)}>{t('brand.reset')}</button>
            </div>
          ) : null}
          {note ? (
            <div class={`banner ${note.tone === 'ok' ? 'ok' : 'err'}`} role={note.tone === 'err' ? 'alert' : 'status'}>
              <Icon name={note.tone === 'ok' ? 'check' : 'alert'} /><span>{t(note.key)}</span>
            </div>
          ) : null}
        </div>

        <div class="stack-sm bc-col">
          <div class="acts-row">
            <h3 class="h3 grow">{t('brand.preview')}</h3>
            <div class="seg" role="group" aria-label={t('brand.pvScreen')}>
              {SCREENS.map((s) => <button key={s.id} type="button" class={screen === s.id ? 'on' : ''} aria-pressed={screen === s.id} onClick={() => { setScreen(s.id); }}>{t(s.label)}</button>)}
            </div>
          </div>
          <div class="bc-phones">
            <PhonePreview values={light} mode="light" screen={screen} gymName={gym.name} label={t('brand.pvAlt', { mode: t('brand.light') })} />
            <PhonePreview values={dark} mode="dark" screen={screen} gymName={gym.name} label={t('brand.pvAlt', { mode: t('brand.dark') })} />
          </div>
          <p class="cap">{t('brand.never')}</p>
        </div>
      </div>
    </section>
  );
}

function PresetButton({ hex, label, on, disabled, onPick }: { readonly hex: string; readonly label: string; readonly on: boolean; readonly disabled: boolean; readonly onPick: () => void }) {
  const ref = useRef<HTMLButtonElement>(null);
  useEffect(() => { ref.current?.style.setProperty('--sw', hex); }, [hex]);
  return <button ref={ref} type="button" class={`bc-swatch${on ? ' on' : ''}`} aria-label={label} aria-pressed={on} disabled={disabled} onClick={onPick} />;
}

/** For tests: the saved value as the page would read it. */
export const savedColourOf = (gym: ManagedGym): string | null => parseBrandColor(gym.brandColor);
