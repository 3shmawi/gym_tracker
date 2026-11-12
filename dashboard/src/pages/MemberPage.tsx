import { useRef, useState } from 'preact/hooks';
import { linkHandler, pathOf, type Route } from '../app/router';
import type { Failure } from '../core/failure';
import { useOnline } from '../core/online';
import { initials } from '../core/text';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n } from '../i18n';
import { canManage, NAME_MAX, normalizePermissions, validName, type Member, type MembersRepository, type NewCode, type Permissions, type Role } from '../members/members';
import { Dialog } from '../ui/Dialog';
import { Icon } from '../ui/icons';
import { failureText, formatDate, roleBadge, roleLabel, statusOf } from '../ui/memberText';
import { PrintSheet, usePrint } from '../ui/PrintSheet';
import { drawChecked, logoFor } from '../ui/qrCards';
import { ErrorView, LoadingView, StateBlock } from '../ui/states';
import { useLeaveWarning, useMembersList } from './useMembersList';
import { MemberProgress } from '../ui/MemberProgress';
import type { ProgressRepository } from '../progress/progress';
import type { PlansRepository } from '../plans/plans';
import type { MediaRepository } from '../exercises/media';

/** D5: what the progress panel needs (absent: no panel, as in D1's tests). */
export interface ProgressDeps {
  readonly progress: ProgressRepository;
  readonly plans: PlansRepository;
  readonly media: MediaRepository;
  readonly cloudName: string | null;
}

interface ShownCode {
  readonly code: NewCode;
  readonly canvas: HTMLCanvasElement;
  readonly verified: boolean;
}

interface Problem {
  readonly failure: Failure;
  readonly name: string;
  readonly context: 'change' | 'code';
}

export function MemberPage({
  gym,
  memberId,
  members,
  loadLogo,
  progressDeps,
}: {
  readonly gym: ManagedGym;
  readonly memberId: string;
  readonly members: MembersRepository;
  readonly loadLogo: (logoPath: string | null) => Promise<ImageBitmap | null>;
  readonly progressDeps?: ProgressDeps;
}) {
  const { t, lang } = useI18n();
  const online = useOnline();
  const { data, reload, refresh } = useMembersList(members, gym.id);
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState('');
  const [problem, setProblem] = useState<Problem | null>(null);
  const [shown, setShown] = useState<ShownCode | null>(null);
  const [confirmEnd, setConfirmEnd] = useState(false);
  const logo = useRef<Promise<ImageBitmap | null> | null>(null);
  const print = usePrint();
  useLeaveWarning(shown !== null, `${t('add.leaveTitle')} ${t('member.codeOnce')}`);

  const listRoute: Route = { name: 'members', gymId: gym.id };
  const back = (
    <a class="btn ghost sm back" href={pathOf(listRoute)} onClick={linkHandler(listRoute)}>
      <span class="flip" aria-hidden="true"><Icon name="chevronLeft" /></span>
      {t('member.back')}
    </a>
  );

  if (data.state === 'loading') {
    return (
      <section class="stack">
        {back}
        <LoadingView />
      </section>
    );
  }
  if (data.state === 'failed') {
    return (
      <section class="stack">
        {back}
        <ErrorView failure={data.failure} onRetry={() => void reload()} />
      </section>
    );
  }
  const member = data.members.find((m) => m.id === memberId);
  if (!member) {
    return (
      <section class="stack">
        {back}
        <StateBlock icon="search" title={t('member.notFoundTitle')}>
          <p class="sub">{t('member.notFoundBody')}</p>
        </StateBlock>
      </section>
    );
  }

  const fail = (failure: Failure, context: 'change' | 'code') => {
    setNotice('');
    setProblem({ failure, name: member.name, context });
  };

  const run = async (what: string, action: () => Promise<void>) => {
    if (busy) return;
    setBusy(what);
    setProblem(null);
    setNotice('');
    try {
      await action();
    } finally {
      setBusy(null);
    }
  };

  const save = (change: { name?: string; role?: Role; permissions?: Permissions }) =>
    run('save', async () => {
      const result = await members.update(member.id, change);
      if (result.ok) {
        await refresh();
        setNotice(t('member.saved'));
      } else fail(result.failure, 'change');
    });

  const makeCode = (kind: 'join' | 'recover') =>
    run('code', async () => {
      const result = await members.newCode(member.id, member.name, kind);
      if (!result.ok) {
        fail(result.failure, 'code');
        return;
      }
      logo.current ??= logoFor(loadLogo, gym.logoPath);
      const drawn = drawChecked(result.value.code, await logo.current);
      setShown({ code: result.value, canvas: drawn.canvas, verified: drawn.verified });
      void refresh();
    });

  const retryQr = (withLogo: boolean) => {
    if (!shown) return;
    void (async () => {
      const bitmap = withLogo ? await (logo.current ??= logoFor(loadLogo, gym.logoPath)) : null;
      const drawn = drawChecked(shown.code.code, bitmap);
      setShown({ ...shown, canvas: drawn.canvas, verified: drawn.verified });
    })();
  };

  const revoke = (inviteId: string) =>
    run('revoke', async () => {
      const result = await members.revokeInvite(inviteId);
      if (result.ok) {
        await refresh();
        setNotice(t('member.revoked'));
      } else fail(result.failure, 'code');
    });

  const endMembership = () => {
    setConfirmEnd(false);
    void run('end', async () => {
      const result = await members.end(member.id);
      if (result.ok) {
        await refresh();
        setNotice(t('member.ended'));
      } else fail(result.failure, 'change');
    });
  };

  const manageable = canManage(gym.role, member.role);
  const planRoute: Route = { name: 'member_plan', gymId: gym.id, memberId: member.id };
  const ended = member.status === 'ended';
  const locked = !manageable || ended;
  const status = statusOf(t, lang, member, new Date());
  const sentInvite = member.invite.state === 'sent' ? member.invite : null;
  const otherGym = problem?.failure.reason === 'person_in_other_gym';
  const printable = shown?.verified ? [{ name: shown.code.name, code: shown.code.code, expiresAt: shown.code.expiresAt, canvas: shown.canvas }] : [];

  return (
    <section class="stack">
      <div class="screen-only stack">
        {back}
        <div class="who big">
          <span class="av big" aria-hidden="true">{initials(member.name)}</span>
          <div class="grow">
            <h1 class="h1 plain">{member.name}</h1>
            <div class="badges">
              <span class={`badge ${roleBadge(member.role)}`}>{roleLabel(t, member.role)}</span>
              <span class={`badge ${status.badge}`}>{status.label}</span>
              {status.when ? <span class="cap">{status.when}</span> : null}
            </div>
          </div>
        </div>

        <div class="live" role="status">{notice ? <div class="banner ok"><Icon name="check" />{notice}</div> : null}</div>
        {problem ? (
          <div class="banner err stack-xs" role="alert">
            <span class="row-icon">
              <Icon name="alert" />
              <b>{otherGym ? t('fail.otherGymTitle') : failureText(t, problem.failure, problem.name)}</b>
            </span>
            {otherGym ? <span class="plain-text">{failureText(t, problem.failure, problem.name)}</span> : null}
            {problem.failure.reason === 'last_owner' ? (
              <span class="cap">{t('fail.nothingChanged')}</span>
            ) : null}
            <span>
              <button type="button" class="btn sm" onClick={() => { setProblem(null); }}>{t('fail.ok')}</button>
            </span>
          </div>
        ) : null}
        {!manageable ? (
          <div class="banner info">
            <Icon name="info" />
            {member.role === 'owner' ? t('member.readOnlyOwner') : t('member.readOnlyCaptain')}
          </div>
        ) : null}
        {manageable && ended ? (
          <div class="banner info">
            <Icon name="info" />
            {t('member.endedNote')}
          </div>
        ) : null}

        <MemberForm
          key={formKey(member)}
          member={member}
          isOwner={gym.role === 'owner'}
          locked={locked}
          busy={busy !== null}
          online={online}
          onSave={(change) => void save(change)}
        />

        {progressDeps && manageable ? <MemberProgress gym={gym} member={member} {...progressDeps} /> : null}

        <div class="grid2">
          {manageable && !ended ? (
            <section class="panel" aria-labelledby="s-plan">
              <h2 class="h2" id="s-plan">{t('member.sectionPlan')}</h2>
              <p class="sub">{t('member.planBody')}</p>
              <div class="acts-row" role="group" aria-label={t('member.quickActions')}>
                <a class="btn pri" href={pathOf(planRoute)} onClick={linkHandler(planRoute)}>
                  {t('member.openPlan')}
                </a>
                {([['replace', 'tpl.replace'], ['copy', 'plan.copy'], ['save_template', 'tpl.saveAs']] as const).map(([open, label]) => {
                  const r: Route = { ...planRoute, open };
                  return (
                    <a key={open} class="btn" href={pathOf(r)} onClick={linkHandler(r)}>{t(label)}</a>
                  );
                })}
              </div>
            </section>
          ) : null}
          {!locked && member.status === 'active' ? (
            <section class="panel" aria-labelledby="s-phone">
              <h2 class="h2" id="s-phone">{t('member.sectionPhone')}</h2>
              <p class="sub">{t('member.phoneBody')}</p>
              <button type="button" class="btn self-start" disabled={!online || busy !== null} onClick={() => void makeCode('recover')}>
                {t('member.makeRecovery')}
              </button>
              <span class="cap">{t('member.phoneNote')}</span>
            </section>
          ) : null}
          {!locked && member.status === 'pending' ? (
            <section class="panel" aria-labelledby="s-pending">
              <h2 class="h2" id="s-pending">{t('member.sectionPending')}</h2>
              <p class="sub">{t('member.pendingBody')}</p>
              <div class="acts-row">
                <button type="button" class="btn pri" disabled={!online || busy !== null} onClick={() => void makeCode('join')}>
                  {t('members.makeNewCode')}
                </button>
                {sentInvite ? (
                  <button type="button" class="btn" disabled={!online || busy !== null} onClick={() => void revoke(sentInvite.inviteId)}>
                    {t('member.revoke')}
                  </button>
                ) : null}
              </div>
            </section>
          ) : null}
          {shown ? (
            <section class="panel" aria-labelledby="s-code">
              <h2 class="h2 plain" id="s-code">{t('member.codeTitle', { name: shown.code.name })}</h2>
              <div class="banner info" role="status">
                <Icon name="info" />
                {t('member.codeOnce')}
              </div>
              <div class="code-row">
                <span class="code">{shown.code.code}</span>
                <span class="cap">{t('member.codeExpires', { date: formatDate(lang, shown.code.expiresAt) })}</span>
              </div>
              {shown.verified ? null : (
                <div class="banner err" role="alert">
                  <Icon name="alert" />
                  <span>
                    {t('add.verifyFailed', { ok: 0, total: 1, bad: 1 })}
                    {' '}
                    {t('add.verifyFailedBody', { names: shown.code.name })}
                  </span>
                </div>
              )}
              <div class="acts-row">
                {shown.verified ? (
                  <button type="button" class="btn pri" onClick={print.request}>{t('member.printCard')}</button>
                ) : (
                  <>
                    <button type="button" class="btn pri" onClick={() => { retryQr(true); }}>{t('add.retryQr')}</button>
                    <button type="button" class="btn" onClick={() => { retryQr(false); }}>{t('add.retryNoLogo')}</button>
                  </>
                )}
                <button type="button" class="btn ghost" onClick={() => { setShown(null); }}>{t('member.codeDone')}</button>
              </div>
              {shown.verified ? <span class="cap">{t('add.printHint')}</span> : null}
            </section>
          ) : null}
          {!ended ? (
            <section class="panel danger-zone" aria-labelledby="s-end">
              <h2 class="h2" id="s-end">{t('member.sectionEnd')}</h2>
              <p class="sub">{t(gym.historyAfterEnd === 'locked' ? 'member.endBodyLocked' : 'member.endBody')}</p>
              <button type="button" class="btn danger self-start" disabled={locked || !online || busy !== null} onClick={() => { setConfirmEnd(true); }}>
                {t('member.end')}
              </button>
            </section>
          ) : null}
        </div>
      </div>

      {print.printing && printable.length > 0 ? <PrintSheet gymName={gym.name} cards={printable} /> : null}

      {confirmEnd ? (
        <Dialog titleId="end-title" onClose={() => { setConfirmEnd(false); }}>
          <h2 class="h2" id="end-title">{t('member.endTitle', { name: member.name })}</h2>
          <p class="sub">{t(gym.historyAfterEnd === 'locked' ? 'member.endConfirmBodyLocked' : 'member.endConfirmBody')}</p>
          <div class="acts">
            <button type="button" class="btn" onClick={() => { setConfirmEnd(false); }}>{t('member.cancel')}</button>
            <button type="button" class="btn danger" onClick={endMembership}>{t('member.end')}</button>
          </div>
        </Dialog>
      ) : null}
    </section>
  );
}

/** A new key = the saved values changed, so the form starts again from them. */
const formKey = (m: Member) =>
  [m.id, m.name, m.role, m.permissions.editTargets, m.permissions.editPlan, m.permissions.buildOwnPlan].join('|');

function MemberForm({
  member,
  isOwner,
  locked,
  busy,
  online,
  onSave,
}: {
  readonly member: Member;
  readonly isOwner: boolean;
  readonly locked: boolean;
  readonly busy: boolean;
  readonly online: boolean;
  readonly onSave: (change: { name?: string; role?: Role; permissions?: Permissions }) => void;
}) {
  const { t } = useI18n();
  const [name, setName] = useState(member.name);
  const [role, setRole] = useState<Role>(member.role);
  const [perms, setPerms] = useState<Permissions>(normalizePermissions(member.permissions));
  const clean = validName(name);
  const nameChanged = clean !== null && clean !== member.name;
  const roleChanged = role !== member.role;
  const saved = normalizePermissions(member.permissions);
  const permsChanged = role === 'trainee' && (perms.editTargets !== saved.editTargets || perms.editPlan !== saved.editPlan || perms.buildOwnPlan !== saved.buildOwnPlan);
  const dirty = nameChanged || roleChanged || permsChanged;
  const nameBad = clean === null;

  const submit = (event: Event) => {
    event.preventDefault();
    if (locked || !dirty || clean === null || !online || busy) return;
    onSave({
      ...(nameChanged ? { name: clean } : {}),
      ...(roleChanged && isOwner ? { role } : {}),
      ...(role === 'trainee' && (permsChanged || roleChanged) ? { permissions: normalizePermissions(perms) } : {}),
    });
  };
  const roleDisabled = locked || !isOwner;
  const roles: readonly Role[] = ['owner', 'captain', 'trainee'];

  return (
    <form class="grid2" onSubmit={submit} noValidate>
      <section class="panel" aria-labelledby="s-name">
        <h2 class="h2" id="s-name">{t('member.sectionName')}</h2>
        <div class="field">
          <label for="member-name">{t('member.name')}</label>
          <input
            id="member-name"
            class={`in plain${nameBad ? ' bad' : ''}`}
            value={name}
            maxLength={NAME_MAX}
            disabled={locked}
            aria-invalid={nameBad}
            aria-describedby="member-name-hint"
            onInput={(event) => { setName(event.currentTarget.value); }}
          />
          {nameBad ? (
            <span id="member-name-hint" class="errt"><Icon name="alert" />{t('member.nameInvalid')}</span>
          ) : (
            <span id="member-name-hint" class="hint">{t('member.nameHint')}</span>
          )}
        </div>
        <div class="field">
          <label for="member-role">{t('member.role')}</label>
          <select
            id="member-role"
            class="in"
            value={role}
            disabled={roleDisabled}
            aria-describedby={isOwner ? undefined : 'member-role-hint'}
            onChange={(event) => { setRole(event.currentTarget.value as Role); }}
          >
            {(isOwner ? roles : [member.role]).map((r) => (
              <option key={r} value={r}>{roleLabel(t, r)}</option>
            ))}
          </select>
          {isOwner ? null : <span id="member-role-hint" class="hint">{t('member.roleOwnerOnly')}</span>}
        </div>
      </section>

      {role === 'trainee' ? (
        <section class="panel">
        <fieldset class="perms bare" disabled={locked}>
          <legend class="h2">{t('member.sectionPerms')}</legend>
          <label class="chk">
            <input
              type="checkbox"
              checked={perms.editTargets || perms.editPlan}
              disabled={perms.editPlan}
              aria-describedby="perm-targets-hint"
              onChange={(event) => { setPerms({ ...perms, editTargets: event.currentTarget.checked }); }}
            />
            <span>
              <b>{t('member.permTargets')}</b>
              <span id="perm-targets-hint" class="cap">{perms.editPlan ? t('member.permTargetsAuto') : t('member.permTargetsHint')}</span>
            </span>
          </label>
          <label class="chk">
            <input
              type="checkbox"
              checked={perms.editPlan}
              onChange={(event) => { setPerms(normalizePermissions({ ...perms, editPlan: event.currentTarget.checked })); }}
            />
            <span>
              <b>{t('member.permPlan')}</b>
              <span class="cap">{t('member.permPlanHint')}</span>
            </span>
          </label>
          <label class="chk">
            <input type="checkbox" checked={perms.buildOwnPlan} onChange={(event) => { setPerms({ ...perms, buildOwnPlan: event.currentTarget.checked }); }} />
            <span>
              <b>{t('member.permOwn')}</b>
              <span class="cap">{t('member.permOwnHint')}</span>
            </span>
          </label>
        </fieldset>
        </section>
      ) : null}
      {locked ? null : (
        <div class="acts-row end full">
          <button type="submit" class="btn pri" disabled={!dirty || clean === null || !online || busy}>{busy ? t('member.saving') : t('member.save')}</button>
        </div>
      )}
    </form>
  );
}
