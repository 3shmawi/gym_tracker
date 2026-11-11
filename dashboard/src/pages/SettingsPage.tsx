import { useEffect, useRef, useState } from 'preact/hooks';
import type { Failure } from '../core/failure';
import type { ManagedGym } from '../gyms/gyms';
import { checkLogoFile, GYM_NAME_MAX, reencodeLogo, validGymName, type GymSettingsRepository, type History } from '../gyms/settings';
import { useI18n, type MessageKey } from '../i18n';
import { cleanName } from '../core/text';
import { BrandColourPanel } from '../ui/BrandColour';
import { Icon } from '../ui/icons';

// Gym settings (D5, design board 12): name, logo, what a former member can
// still read. Owners change them; captains see them read-only, as board 12
// shows. The database agrees since migration 0020 (private.i_own). Deleting
// the gym and the team list are not here (board 12 shows them; out of scope).

type Note = { readonly tone: 'ok' | 'err'; readonly key: MessageKey } | null;

const failureKey = (f: Failure): MessageKey => (f.kind === 'forbidden' ? 'set.errForbidden' : f.kind === 'offline' ? 'plan.errOffline' : f.kind === 'session_ended' ? 'fail.session' : f.kind === 'invalid' ? 'set.nameEmpty' : 'set.errServer');

/** Draws the logo (a bitmap from the private bucket) on a canvas: no blob: or data: URL, so the CSP stays as it is. */
function LogoCanvas({ bitmap, label }: { readonly bitmap: ImageBitmap; readonly label: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const c = ref.current;
    const ctx = c?.getContext('2d');
    if (!c || !ctx) return;
    c.width = 128;
    c.height = 128;
    const s = Math.min(128 / bitmap.width, 128 / bitmap.height);
    ctx.clearRect(0, 0, 128, 128);
    ctx.drawImage(bitmap, (128 - bitmap.width * s) / 2, (128 - bitmap.height * s) / 2, bitmap.width * s, bitmap.height * s);
  }, [bitmap]);
  return <canvas ref={ref} role="img" aria-label={label} />;
}

export function SettingsPage({ gym, settings, loadLogo, online, onChanged }: {
  readonly gym: ManagedGym;
  readonly settings: GymSettingsRepository;
  readonly loadLogo: (logoPath: string | null) => Promise<ImageBitmap | null>;
  readonly online: boolean;
  /** The gym changed on the server: reload the gyms list (header, switcher). */
  readonly onChanged: () => void;
}) {
  const { t } = useI18n();
  const [name, setName] = useState(gym.name);
  const [busy, setBusy] = useState<'name' | 'logo' | 'history' | null>(null);
  const [note, setNote] = useState<{ part: 'name' | 'logo' | 'history'; note: Note }>({ part: 'name', note: null });
  const [logo, setLogo] = useState<ImageBitmap | null>(null);
  const [logoPath, setLogoPath] = useState(gym.logoPath);
  const [history, setHistory] = useState<History>(gym.historyAfterEnd);
  const file = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let alive = true;
    if (!logoPath) {
      setLogo(null);
      return;
    }
    // loadLogo falls back to the app icon; show only the gym's own picture.
    void loadLogo(logoPath).then((b) => { if (alive) setLogo(b); });
    return () => {
      alive = false;
    };
  }, [logoPath, loadLogo]);

  const say = (part: 'name' | 'logo' | 'history', n: Note) => { setNote({ part, note: n }); };
  const shown = (part: 'name' | 'logo' | 'history') =>
    note.part === part && note.note ? (
      <div class={`banner ${note.note.tone === 'ok' ? 'ok' : 'err'}`} role={note.note.tone === 'err' ? 'alert' : 'status'}>
        <Icon name={note.note.tone === 'ok' ? 'check' : 'alert'} />
        <span>{t(note.note.key)}</span>
      </div>
    ) : null;

  const cleaned = cleanName(name);
  const nameLen = Array.from(cleaned).length;
  const nameProblem: MessageKey | null = nameLen === 0 ? 'set.nameEmpty' : nameLen > GYM_NAME_MAX ? 'set.nameLong' : null;
  const nameChanged = validGymName(name) !== null && validGymName(name) !== gym.name;

  const saveName = async () => {
    if (validGymName(name) === null) return;
    setBusy('name');
    const r = await settings.rename(gym.id, name);
    setBusy(null);
    if (r.ok) {
      setName(r.value);
      say('name', { tone: 'ok', key: 'set.nameSaved' });
      onChanged();
    } else say('name', { tone: 'err', key: failureKey(r.failure) });
  };

  const pick = async (f: File) => {
    // Checked here, before any request: size, and what the bytes really are.
    const head = new Uint8Array(await f.slice(0, 16).arrayBuffer());
    const check = checkLogoFile(f, head);
    if (!check.ok) {
      say('logo', { tone: 'err', key: check.problem === 'empty' ? 'set.logoEmpty' : check.problem === 'too_big' ? 'set.logoBig' : 'set.logoType' });
      return;
    }
    setBusy('logo');
    const blob = await reencodeLogo(f, check.type);
    if (!blob) {
      setBusy(null);
      say('logo', { tone: 'err', key: 'set.logoBroken' });
      return;
    }
    const r = await settings.setLogo(gym.id, blob, check.type, logoPath);
    setBusy(null);
    if (r.ok) {
      setLogoPath(r.value);
      setLogo(await createImageBitmap(blob).catch(() => null));
      say('logo', { tone: 'ok', key: 'set.logoSaved' });
      onChanged();
    } else say('logo', { tone: 'err', key: failureKey(r.failure) });
  };

  const removeLogo = async () => {
    setBusy('logo');
    const r = await settings.removeLogo(gym.id, logoPath);
    setBusy(null);
    if (r.ok) {
      setLogoPath(null);
      say('logo', { tone: 'ok', key: 'set.logoRemoved' });
      onChanged();
    } else say('logo', { tone: 'err', key: failureKey(r.failure) });
  };

  const saveHistory = async (value: History) => {
    const before = history;
    setHistory(value);
    setBusy('history');
    const r = await settings.setHistory(gym.id, value);
    setBusy(null);
    if (r.ok) {
      say('history', { tone: 'ok', key: 'set.historySaved' });
      onChanged();
    } else {
      setHistory(before);
      say('history', { tone: 'err', key: failureKey(r.failure) });
    }
  };

  if (gym.role !== 'owner') {
    return (
      <section class="stack">
        <div class="stack-sm">
          <h1 class="h1">{t('set.title')}</h1>
          <p class="sub">{t('set.subtitle')}</p>
        </div>
        <div class="banner info" role="note">
          <Icon name="lock" />
          <span>{t('set.readOnly')}</span>
        </div>
        <div class="grid2">
          <section class="panel" aria-labelledby="s-identity">
            <h2 class="h2" id="s-identity">{t('set.identity')}</h2>
            <dl class="kv">
              <dt>{t('set.name')}</dt>
              <dd class="plain-text">{gym.name}</dd>
              <dt>{t('set.logo')}</dt>
              <dd>
                <div class="logo-row">
                  <div class="logo-box">{logo && logoPath ? <LogoCanvas bitmap={logo} label={t('set.logoAlt', { gym: gym.name })} /> : <Icon name="image" />}</div>
                  {logoPath ? null : <p class="cap grow">{t('set.logoNone')}</p>}
                </div>
              </dd>
            </dl>
          </section>
          <section class="panel" aria-labelledby="s-history">
            <h2 class="h2" id="s-history">{t('set.historyTitle')}</h2>
            <p><b>{history === 'readable' ? t('set.readable') : t('set.locked')}</b></p>
            <p class="cap">{history === 'readable' ? t('set.readableBody') : t('set.lockedBody')}</p>
            <p class="cap">{t('set.historyBody')}</p>
          </section>
          <BrandColourPanel gym={gym} settings={settings} online={online} onChanged={onChanged} />
        </div>
      </section>
    );
  }

  const off = !online || busy !== null;
  return (
    <section class="stack">
      <div class="stack-sm">
        <h1 class="h1">{t('set.title')}</h1>
        <p class="sub">{t('set.subtitle')}</p>
      </div>
      {!online ? <p class="cap">{t('plan.offlineHint')}</p> : null}
      <div class="grid2">
        <section class="panel" aria-labelledby="s-identity">
          <h2 class="h2" id="s-identity">{t('set.identity')}</h2>
          <form class="stack-sm" onSubmit={(e) => { e.preventDefault(); void saveName(); }}>
            <div class="field">
              <label for="gym-name">{t('set.name')}</label>
              <input id="gym-name" class={`in plain-text${nameProblem ? ' bad' : ''}`} value={name} maxLength={GYM_NAME_MAX * 4} aria-invalid={nameProblem !== null} aria-describedby="gym-name-hint gym-name-err" onInput={(e) => { setName(e.currentTarget.value); say('name', null); }} />
              <span class="hint" id="gym-name-hint">{t('set.nameHint')}</span>
              <span class="live-slot" id="gym-name-err">{nameProblem ? <span class="errt"><Icon name="alert" />{t(nameProblem)}</span> : null}</span>
            </div>
            <button type="submit" class="btn pri self-start" disabled={off || !nameChanged || nameProblem !== null}>{t('set.saveName')}</button>
          </form>
          {shown('name')}

          <h3 class="h3">{t('set.logo')}</h3>
          <div class="logo-row">
            <div class="logo-box">{logo && logoPath ? <LogoCanvas bitmap={logo} label={t('set.logoAlt', { gym: gym.name })} /> : <Icon name="image" />}</div>
            <p class="cap grow">{logoPath ? t('set.logoHint') : `${t('set.logoNone')} ${t('set.logoHint')}`}</p>
          </div>
          <div class="acts-row">
            <input ref={file} id="logo-file" class="file-in" type="file" accept="image/png,image/jpeg" disabled={off} onChange={(e) => {
              const f = e.currentTarget.files?.[0];
              e.currentTarget.value = '';
              if (f) void pick(f);
            }} />
            <label for="logo-file" class={`btn${off ? ' is-off' : ''}`} aria-disabled={off}>
              {busy === 'logo' ? t('set.logoUploading') : logoPath ? t('set.logoReplace') : t('set.logoPick')}
            </label>
            {logoPath ? <button type="button" class="btn danger" disabled={off} onClick={() => void removeLogo()}>{t('set.logoRemove')}</button> : null}
          </div>
          {shown('logo')}
        </section>

        <section class="panel" aria-labelledby="s-history">
          <h2 class="h2" id="s-history">{t('set.historyTitle')}</h2>
          <fieldset class="perms bare">
            <legend class="sr-only">{t('set.historyTitle')}</legend>
            {(['readable', 'locked'] as const).map((v) => (
              <label key={v} class="radio-card">
                <input type="radio" name="history" value={v} checked={history === v} disabled={off} onChange={() => void saveHistory(v)} />
                <span>
                  <b>{v === 'readable' ? t('set.readable') : t('set.locked')}</b>
                  <span class="cap">{v === 'readable' ? t('set.readableBody') : t('set.lockedBody')}</span>
                </span>
              </label>
            ))}
          </fieldset>
          <p class="cap">{t('set.historyBody')}</p>
          {shown('history')}
        </section>
        <BrandColourPanel gym={gym} settings={settings} online={online} onChanged={onChanged} />
      </div>
    </section>
  );
}
