import { pathOf } from '../app/router';
import { initials } from '../core/text';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n } from '../i18n';
import { Icon } from '../ui/icons';

export function GymPickerPage({ gyms, onPick }: { readonly gyms: readonly ManagedGym[]; readonly onPick: (gym: ManagedGym) => void }) {
  const { t } = useI18n();
  return (
    <div class="page-center wide stack">
      <div class="stack-sm">
        <h1 class="h1">{t('gyms.title')}</h1>
        <p class="sub">{t('gyms.subtitle', { count: gyms.length })}</p>
      </div>
      <ul class="gym-list">
        {gyms.map((gym, index) => {
          const owner = gym.role === 'owner';
          const role = owner ? t('gyms.roleOwner') : t('gyms.roleCaptain');
          return (
            <li key={gym.id}>
              <a
                class="card gym-card"
                href={pathOf({ name: 'members', gymId: gym.id })}
                onClick={(event) => {
                  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
                  event.preventDefault();
                  onPick(gym);
                }}
              >
                <span class={`lg big${index % 2 === 1 ? ' amber' : ''}`} aria-hidden="true">{initials(gym.name)}</span>
                <span class="meta">
                  <b>{gym.name}</b>
                  <span class="cap">{role} · {t('gyms.memberCount', { count: gym.memberCount })}</span>
                </span>
                <span class={`badge ${owner ? 'ok' : 'keep'}`}>{role}</span>
                <span class="flip" aria-hidden="true"><Icon name="chevronRight" /></span>
              </a>
            </li>
          );
        })}
      </ul>
      <p class="cap">{t('gyms.note')}</p>
    </div>
  );
}
