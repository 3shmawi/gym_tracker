import { describe, expect, it } from 'vitest';
import { parsePath } from '../src/app/router';

const ID = '0b1c2d3e-4f50-4a6b-8c7d-9e0f1a2b3c4d';

describe('parsePath', () => {
  it('knows the fixed paths', () => {
    expect(parsePath('/')).toEqual({ name: 'home' });
    expect(parsePath('/sign-in')).toEqual({ name: 'sign_in' });
    expect(parsePath('/gyms/')).toEqual({ name: 'gyms' });
  });
  it('accepts a lowercase uuid gym id', () => {
    expect(parsePath(`/g/${ID}/members`)).toEqual({ name: 'members', gymId: ID });
    expect(parsePath(`/g/${ID}/members/`)).toEqual({ name: 'members', gymId: ID });
  });
  it('rejects bad ids and odd paths', () => {
    expect(parsePath(`/g/${ID.toUpperCase()}/members`).name).toBe('not_found');
    expect(parsePath('/g/not-a-uuid/members').name).toBe('not_found');
    expect(parsePath(`/g/${ID}/members/extra`).name).toBe('not_found');
    expect(parsePath('//evil.example').name).toBe('not_found');
    expect(parsePath('/%2e%2e/').name).toBe('not_found');
    expect(parsePath('/nope').name).toBe('not_found');
  });
});
