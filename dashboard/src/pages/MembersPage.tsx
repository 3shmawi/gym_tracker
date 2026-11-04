import type { ManagedGym } from '../gyms/gyms';
import { useI18n } from '../i18n';

// D0 placeholder: the members list arrives in D1.
export function MembersPage({ gym }: { readonly gym: ManagedGym }) {
  const { t } = useI18n();
  return (
    <section class="stack" data-gym={gym.id}>
      <h1 class="h1">{t('members.title')}</h1>
      <div class="card">
        <p class="sub">{t('members.comingSoon')}</p>
      </div>
    </section>
  );
}
