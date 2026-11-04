import { describe, expect, it } from 'vitest';
import { GymsRepository } from '../src/gyms/gyms';
import { fakeDataClient } from './fakes';

const A = '0b1c2d3e-4f50-4a6b-8c7d-9e0f1a2b3c4d';
const B = '1b1c2d3e-4f50-4a6b-8c7d-9e0f1a2b3c4d';

describe('GymsRepository', () => {
  it('returns [] when the user has no person row', async () => {
    const repo = new GymsRepository(fakeDataClient({ person: null, rows: [] }));
    expect(await repo.managedGyms('u1')).toEqual({ ok: true, value: [] });
  });
  it('drops deleted gyms, cleans names and sorts', async () => {
    const bidi = String.fromCharCode(0x202e);
    const rows = [
      { role: 'captain', gym: { id: B, name: `Zed${bidi} Gym` } },
      { role: 'owner', gym: null },
      { role: 'owner', gym: { id: A, name: 'Alpha' } },
      { role: 'member', gym: { id: A, name: 'Not a manager' } },
      { role: 'owner', gym: { id: 'not-a-uuid', name: 'Bad id' } },
    ];
    const repo = new GymsRepository(fakeDataClient({ person: { id: 'p1' }, rows, counts: 7 }));
    const result = await repo.managedGyms('u1');
    expect(result).toEqual({
      ok: true,
      value: [
        { id: A, name: 'Alpha', role: 'owner', memberCount: 7, logoPath: null },
        { id: B, name: 'Zed Gym', role: 'captain', memberCount: 7, logoPath: null },
      ],
    });
  });
});
