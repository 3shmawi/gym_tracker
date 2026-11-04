import type { Failure } from '../core/failure';
import type { Lang } from '../core/prefs';
import type { I18n } from '../i18n';
import type { Member, Role } from '../members/members';

type T = I18n['t'];

/** "12 Oct 2026" / "١٢ أكتوبر ٢٠٢٦": the app's date format. */
export function formatDate(lang: Lang, date: Date): string {
  return new Intl.DateTimeFormat(lang === 'ar' ? 'ar-EG' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).format(date);
}

export function roleLabel(t: T, role: Role): string {
  return role === 'owner' ? t('members.roleOwner') : role === 'captain' ? t('members.roleCaptain') : t('members.roleTrainee');
}

export const roleBadge = (role: Role): string => (role === 'owner' ? 'ok' : role === 'captain' ? 'keep' : '');

export interface StatusView {
  readonly badge: 'ok' | 'warn' | 'err' | '';
  readonly label: string;
  readonly when: string;
}

const DAY = 86_400_000;

export function expiresText(t: T, expiresAt: Date, now: Date): string {
  const days = Math.ceil((expiresAt.getTime() - now.getTime()) / DAY);
  if (days <= 0) return t('members.expiresToday');
  if (days === 1) return t('members.expiresOne');
  if (days === 2) return t('members.expiresTwo');
  return t('members.expiresMany', { count: days });
}

export function statusOf(t: T, lang: Lang, member: Member, now: Date): StatusView {
  if (member.status === 'ended') {
    return { badge: '', label: t('members.statusEnded'), when: member.endedAt ? t('members.ended', { date: formatDate(lang, member.endedAt) }) : '' };
  }
  if (member.status === 'active') {
    return { badge: 'ok', label: t('members.statusActive'), when: member.joinedAt ? t('members.joined', { date: formatDate(lang, member.joinedAt) }) : '' };
  }
  const invite = member.invite;
  if (invite.state === 'sent') return { badge: 'warn', label: t('members.statusCodeSent'), when: expiresText(t, invite.expiresAt, now) };
  if (invite.state === 'expired') return { badge: 'err', label: t('members.statusCodeExpired'), when: t('members.makeNewCode') };
  return { badge: 'warn', label: t('members.statusNoCode'), when: t('members.makeNewCode') };
}

/** The "Can change" column. */
export function permsText(t: T, member: Member): string {
  if (member.status === 'ended') return '—';
  if (member.role === 'owner') return t('members.permEverything');
  if (member.role === 'captain') return t('members.permCaptain');
  const p = member.permissions;
  const parts = [
    ...(p.editTargets || p.editPlan ? [t('members.permTargets')] : []),
    ...(p.editPlan ? [t('members.permPlan')] : []),
    ...(p.buildOwnPlan ? [t('members.permOwn')] : []),
  ];
  return parts.length ? parts.join(' · ') : t('members.permNone');
}

/** A message for a refused write. Never the server's own text. */
export function failureText(t: T, failure: Failure, name = ''): string {
  if (failure.reason === 'person_in_other_gym') return t('fail.otherGym', { name });
  switch (failure.kind) {
    case 'offline':
      return t('fail.offline');
    case 'forbidden':
      return t('fail.forbidden');
    case 'session_ended':
      return t('fail.session');
    case 'not_found':
      return t('fail.notFound');
    case 'rate_limited':
      return t('fail.rateLimited');
    case 'invalid':
      return t('fail.invalid');
    case 'conflict':
      // reason last_owner: memberships_guard, "a gym needs at least one active owner".
      return failure.reason === 'last_owner' ? t('fail.lastOwner') : t('fail.conflict');
    default:
      return t('fail.server');
  }
}
