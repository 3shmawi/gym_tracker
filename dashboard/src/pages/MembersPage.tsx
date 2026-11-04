import type { ComponentChildren } from 'preact';
import { useMemo, useState } from 'preact/hooks';
import { linkHandler, pathOf, type Route } from '../app/router';
import { cleanName, initials } from '../core/text';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n } from '../i18n';
import { NAME_MAX, type Member, type MembersRepository } from '../members/members';
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

export function MembersPage({ gym, members }: { readonly gym: ManagedGym; readonly members: MembersRepository }) {
  const { t, lang } = useI18n();
  const { data, reload } = useMembersList(members, gym.id);
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
  const rows = all.filter((m) => matches(m, tab) && (needle === '' || m.name.toLocaleLowerCase().includes(needle)));
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
                      <td class="end">
                        <Link route={route} class="btn sm" label={t('members.manageName', { name: m.name })}>{t('members.manage')}</Link>
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
              const sub = [roleLabel(t, m.role), m.status === 'pending' || m.status === 'ended' ? status.when : permsText(t, m)].filter(Boolean).join(' · ');
              return (
                <li key={m.id}>
                  <Link route={route} class="panel mcard" label={t('members.manageName', { name: m.name })}>
                    <span class="av" aria-hidden="true">{initials(m.name)}</span>
                    <span class="meta">
                      <b class="plain">{m.name}</b>
                      <span class="cap">{sub}</span>
                    </span>
                    <span class={`badge ${status.badge}`}>{status.label}</span>
                  </Link>
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
