import type { ComponentChildren } from 'preact';
import { useEffect, useMemo, useState } from 'preact/hooks';
import type { PlansRepository } from '../plans/plans';
import type { LastWorkout, ProgressRepository } from '../progress/progress';
import { dateLabel } from '../progress/weeks';
import { linkHandler, pathOf, type Route } from '../app/router';
import { cleanName, initials } from '../core/text';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n } from '../i18n';
import { canManage, NAME_MAX, type Member, type MembersRepository } from '../members/members';
import { Icon } from '../ui/icons';
import { permsText, roleBadge, roleLabel, statusOf } from '../ui/memberText';
import { ErrorView, LoadingView, StateBlock } from '../ui/states';
import { useMembersList } from './useMembersList';

type Tab = 'all' | 'active' | 'pending' | 'ended';
const TABS: readonly Tab[] = ['all', 'active', 'pending', 'ended'];

const matches = (member: Member, tab: Tab) => tab === 'all' || member.status === tab;

function Link({ route, class: cls, label, children }: { readonly route: Route; readonly class: string; readonly label?: string; readonly children: ComponentChildren }) {
  return (
    <a class={cls} href={pathOf(route)} aria-label={label} onClick={linkHandler(route)}>
      {children}
    </a>
  );
}

export function MembersPage({ gym, members, progress, plans }: { readonly gym: ManagedGym; readonly members: MembersRepository; readonly progress?: ProgressRepository; readonly plans?: PlansRepository }) {
  const { t, lang } = useI18n();
  const { data, reload } = useMembersList(members, gym.id);
  // D5 (board 10): "Last workout" per member; optional, a failure just hides it.
  const [last, setLast] = useState<ReadonlyMap<string, LastWorkout> | null>(null);
  useEffect(() => {
    let alive = true;
    if (progress) void progress.lastWorkouts(gym.id).then((r) => { if (alive && r.ok) setLast(r.value); });
    return () => {
      alive = false;
    };
  }, [progress, gym.id]);
  // "What needs you": active people you can manage who have no plan yet. Optional; a failure just hides it.
  const [planned, setPlanned] = useState<ReadonlyMap<string, number> | null>(null);
  const memberIds = data.state === 'ready' ? data.members.filter((m) => m.status === 'active' && canManage(gym.role, m.role)).map((m) => m.id).join(',') : '';
  useEffect(() => {
    let alive = true;
    if (plans && memberIds !== '') void plans.versions(memberIds.split(',')).then((r) => { if (alive && r.ok) setPlanned(r.value); });
    return () => {
      alive = false;
    };
  }, [plans, memberIds]);
  const [onlyNoPlan, setOnlyNoPlan] = useState(false);
  const [menuFor, setMenuFor] = useState<string | null>(null);
  const lastText = (m: Member) => {
    const l = last?.get(m.id);
    if (!l || m.status !== 'active') return t('prog.dash');
    return l.lastWorkoutAt ? dateLabel(lang, l.lastWorkoutAt) : t('members.lastNever');
  };
  const [tab, setTab] = useState<Tab>('all');
  const [query, setQuery] = useState('');
  const now = useMemo(() => new Date(), [data]);

  const heading = <h1 class="h1">{t('members.title')}</h1>;
  if (data.state === 'loading') {
    return (
      <section class="stack" data-gym={gym.id}>
        {heading}
        <LoadingView />
      </section>
    );
  }
  if (data.state === 'failed') {
    return (
      <section class="stack" data-gym={gym.id}>
        {heading}
        <ErrorView failure={data.failure} onRetry={() => void reload()} />
      </section>
    );
  }

  const all = data.members;
  const present = all.filter((m) => m.status !== 'ended').length;
  const waiting = all.filter((m) => m.status === 'pending' && m.invite.state === 'sent').length;
  const countOf = (k: Tab) => all.filter((m) => matches(m, k)).length;
  const needle = cleanName(query).toLocaleLowerCase();
  const withoutPlan = (m: Member) => planned !== null && m.status === 'active' && canManage(gym.role, m.role) && !planned.has(m.id);
  const noPlanCount = all.filter(withoutPlan).length;
  const expiredCount = all.filter((m) => m.status === 'pending' && m.invite.state === 'expired').length;
  const rows = all.filter((m) => matches(m, tab) && (!onlyNoPlan || withoutPlan(m)) && (needle === '' || m.name.toLocaleLowerCase().includes(needle)));
  const tabLabel: Record<Tab, string> = {
    all: t('members.tabAll'),
    active: t('members.tabActive'),
    pending: t('members.tabWaiting'),
    ended: t('members.tabEnded'),
  };
  const addTrainees: Route = { name: 'add_members', gymId: gym.id, role: 'trainee' };
  const alone = present <= 1;

  const empty = (() => {
    if (alone && tab === 'all' && needle === '') {
      return (
        <StateBlock icon="members" title={t('members.emptyTitle')}>
          <p class="sub">{t('members.emptyBody')}</p>
          <Link route={addTrainees} class="btn pri">{t('members.addTrainees')}</Link>
        </StateBlock>
      );
    }
    if (needle !== '') {
      return (
        <StateBlock icon="search" title={t('members.noMatchTitle', { query: cleanName(query) })}>
          <p class="sub">{t('members.noMatchBody')}</p>
          <button type="button" class="btn" onClick={() => { setQuery(''); }}>{t('members.clearSearch')}</button>
        </StateBlock>
      );
    }
    return (
      <StateBlock icon="search" title={t('members.noneHereTitle')}>
        <p class="sub">{t('members.noneHereBody')}</p>
        <button type="button" class="btn" onClick={() => { setTab('all'); }}>{t('members.showEveryone')}</button>
      </StateBlock>
    );
  })();

  return (
    <section class="stack" data-gym={gym.id}>
      <div class="page-head">
        <div class="stack-sm grow">
          {heading}
          <p class="sub">
            <span>{present === 1 ? t('members.peopleOne') : t('members.peopleMany', { count: present })}</span>
            {' · '}
            <span>{waiting === 1 ? t('members.codesOne') : t('members.codesMany', { count: waiting })}</span>
          </p>
        </div>
        {gym.role === 'owner' ? (
          <Link route={{ name: 'add_members', gymId: gym.id, role: 'captain' }} class="btn">{t('members.addCaptain')}</Link>
        ) : null}
        <Link route={addTrainees} class="btn pri">
          <Icon name="plus" />
          {t('members.addTrainees')}
        </Link>
      </div>

      {noPlanCount > 0 || expiredCount > 0 ? (
        <div class="attn" role="group" aria-label={t('members.attnTitle')}>
          <b>{t('members.attnTitle')}</b>
          {noPlanCount > 0 ? (
            <button type="button" class="btn sm" aria-pressed={onlyNoPlan} onClick={() => { setOnlyNoPlan(!onlyNoPlan); setTab('all'); }}>
              {noPlanCount === 1 ? t('members.attnNoPlanOne') : t('members.attnNoPlanMany', { count: noPlanCount })}
            </button>
          ) : null}
          {expiredCount > 0 ? (
            <button type="button" class="btn sm" onClick={() => { setOnlyNoPlan(false); setTab('pending'); }}>
              {expiredCount === 1 ? t('members.attnExpiredOne') : t('members.attnExpiredMany', { count: expiredCount })}
            </button>
          ) : null}
          {onlyNoPlan ? <button type="button" class="btn sm ghost" onClick={() => { setOnlyNoPlan(false); }}>{t('members.attnClear')}</button> : null}
        </div>
      ) : null}

      <div class="toolbar">
        <div class="field search">
          <label class="sr-only" for="member-search">{t('members.search')}</label>
          <input
            id="member-search"
            class="in"
            type="search"
            placeholder={t('members.search')}
            maxLength={NAME_MAX}
            value={query}
            onInput={(event) => { setQuery(event.currentTarget.value); }}
          />
        </div>
        <div class="seg" role="group" aria-label={t('members.show')}>
          {TABS.map((k) => (
            <button key={k} type="button" class={tab === k ? 'on' : ''} aria-pressed={tab === k} onClick={() => { setTab(k); }}>
              {tabLabel[k]} <span class="num">{countOf(k)}</span>
            </button>
          ))}
        </div>
      </div>

      {rows.length === 0 || (alone && tab === 'all' && needle === '') ? (
        <div class="panel">{empty}</div>
      ) : (
        <>
          <div class="tblbox wide-only">
            <table class="t">
              <thead>
                <tr>
                  <th scope="col">{t('members.colName')}</th>
                  <th scope="col">{t('members.colRole')}</th>
                  <th scope="col">{t('members.colStatus')}</th>
                  <th scope="col">{t('members.colChange')}</th>
                  {last ? <th scope="col">{t('members.colLast')}</th> : null}
                  <th scope="col"><span class="sr-only">{t('members.colActions')}</span></th>
                </tr>
              </thead>
              <tbody>
                {rows.map((m) => {
                  const status = statusOf(t, lang, m, now);
                  const route: Route = { name: 'member', gymId: gym.id, memberId: m.id };
                  return (
                    <tr key={m.id}>
                      <td>
                        <div class="who">
                          <span class="av" aria-hidden="true">{initials(m.name)}</span>
                          <b class="plain">{m.name}</b>
                        </div>
                      </td>
                      <td><span class={`badge ${roleBadge(m.role)}`}>{roleLabel(t, m.role)}</span></td>
                      <td>
                        <div class="stack-xs">
                          <span class={`badge ${status.badge}`}>{status.label}</span>
                          {status.when ? <span class="cap">{status.when}</span> : null}
                        </div>
                      </td>
                      <td><span class="cap">{permsText(t, m)}</span></td>
                      {last ? <td><span class="cap">{lastText(m)}</span></td> : null}
                      <td class="end">
                        <div class="acts-row">
                          {canManage(gym.role, m.role) && m.status === 'active' ? (
                            <>
                              <Link route={{ name: 'member_plan', gymId: gym.id, memberId: m.id }} class="btn sm ghost" label={t('members.quickPlanName', { name: m.name })}>{t('members.quickPlan')}</Link>
                              <Link route={{ name: 'member_plan', gymId: gym.id, memberId: m.id, open: 'replace' }} class="btn sm ghost" label={t('members.quickTemplateName', { name: m.name })}>{t('members.quickTemplate')}</Link>
                              <Link route={{ name: 'member_plan', gymId: gym.id, memberId: m.id, open: 'copy' }} class="btn sm ghost" label={t('members.quickCopyName', { name: m.name })}>{t('members.quickCopy')}</Link>
                            </>
                          ) : null}
                          <Link route={route} class="btn sm" label={t('members.manageName', { name: m.name })}>{t('members.manage')}</Link>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <ul class="mcards phone-only">
            {rows.map((m) => {
              const status = statusOf(t, lang, m, now);
              const route: Route = { name: 'member', gymId: gym.id, memberId: m.id };
              const sub = [roleLabel(t, m.role), m.status === 'pending' || m.status === 'ended' ? status.when : permsText(t, m), last && m.status === 'active' ? `${t('members.colLast')}: ${lastText(m)}` : null].filter(Boolean).join(' · ');
              const quick = canManage(gym.role, m.role) && m.status === 'active';
              const base: Route = { name: 'member_plan', gymId: gym.id, memberId: m.id };
              const menuId = `mq-${m.id}`;
              return (
                <li key={m.id} class="mcard-wrap">
                  <Link route={route} class="panel mcard">
                    <span class="av" aria-hidden="true">{initials(m.name)}</span>
                    <span class="meta">
                      <b class="plain">{m.name}</b>
                      <span class="cap">{sub}</span>
                    </span>
                    <span class={`badge ${status.badge}`}>{status.label}</span>
                  </Link>
                  {quick ? (
                    <>
                      <button type="button" class="ib mcard-more" aria-expanded={menuFor === m.id} aria-controls={menuId} aria-label={t('members.quickMore', { name: m.name })} onClick={() => { setMenuFor(menuFor === m.id ? null : m.id); }}>
                        <Icon name="more" />
                      </button>
                      {menuFor === m.id ? (
                        <div class="mcard-menu acts-row" id={menuId}>
                          <Link route={base} class="btn sm" label={t('members.quickPlanName', { name: m.name })}>{t('members.quickPlan')}</Link>
                          <Link route={{ ...base, open: 'replace' }} class="btn sm" label={t('members.quickTemplateName', { name: m.name })}>{t('members.quickTemplate')}</Link>
                          <Link route={{ ...base, open: 'copy' }} class="btn sm" label={t('members.quickCopyName', { name: m.name })}>{t('members.quickCopy')}</Link>
                        </div>
                      ) : null}
                    </>
                  ) : null}
                </li>
              );
            })}
          </ul>
        </>
      )}
      <p class="cap">{t('members.note')}</p>
    </section>
  );
}
