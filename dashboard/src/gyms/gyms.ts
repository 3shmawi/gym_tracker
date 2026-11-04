import type { SupabaseClient } from '@supabase/supabase-js';
import { guard, unwrap, type Result } from '../core/result';
import { cleanName } from '../core/text';

export type ManagerRole = 'owner' | 'captain';

export interface ManagedGym {
  readonly id: string;
  readonly name: string;
  readonly role: ManagerRole;
  /** Storage path in bucket gym-logos (<gym_id>/logo.png|jpg|jpeg), or null. */
  readonly logoPath: string | null;
  /** Members that are active or waiting to join. */
  readonly memberCount: number;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Same shape as the gyms.logo_path check (migration 0005). */
export const LOGO_PATH = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/logo\.(png|jpe?g)$/;

export function isGymId(value: string): boolean {
  return UUID.test(value);
}

/**
 * The gyms the signed-in person runs. RLS decides (migration 0005):
 * - people: "read own person";
 * - memberships: "read own memberships" (status active, role owner|captain);
 * - gyms: "members read their gyms" (deleted gyms come back as null);
 * - member counts: "managers read gym memberships" (i_manage, permanent session).
 */
export class GymsRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  async managedGyms(userId: string): Promise<Result<ManagedGym[]>> {
    return guard(async () => {
      const person = unwrap(
        await this.supabase.from('people').select('id').eq('auth_user_id', userId).maybeSingle<{ id: string }>(),
      );
      if (!person) return [];

      const rows = unwrap(
        await this.supabase
          .from('memberships')
          .select('role, gym:gyms(id, name, logo_path)')
          .eq('person_id', person.id)
          .eq('status', 'active')
          .in('role', ['owner', 'captain'])
          .overrideTypes<MembershipRow[], { merge: false }>(),
      );

      const gyms = (rows ?? []).flatMap((row): Omit<ManagedGym, 'memberCount'>[] => {
        const gym = Array.isArray(row.gym) ? row.gym[0] : row.gym;
        const role = row.role;
        if (!gym || !isGymId(gym.id) || (role !== 'owner' && role !== 'captain')) return [];
        const logoPath = typeof gym.logo_path === 'string' && LOGO_PATH.test(gym.logo_path) && gym.logo_path.startsWith(`${gym.id}/`) ? gym.logo_path : null;
        return [{ id: gym.id, name: cleanName(gym.name), role, logoPath }];
      });

      const counted = await Promise.all(
        gyms.map(async (gym) => {
          const { count, error } = await this.supabase
            .from('memberships')
            .select('id', { count: 'exact', head: true })
            .eq('gym_id', gym.id)
            .neq('status', 'ended');
          if (error) throw error;
          return { ...gym, memberCount: count ?? 0 };
        }),
      );
      return counted.sort((a, b) => a.name.localeCompare(b.name));
    });
  }
}

interface MembershipRow {
  role: string;
  gym: GymRow | GymRow[] | null;
}

interface GymRow {
  id: string;
  name: unknown;
  logo_path?: unknown;
}
