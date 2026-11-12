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
  it('opens a member\'s plan (D3); both ids must be UUIDs', () => {
    expect(parsePath(`/g/${ID}/members/${ID}/plan`)).toEqual({ name: 'member_plan', gymId: ID, memberId: ID });
    expect(parsePath(`/g/${ID}/members/${ID}/plan/`)).toEqual({ name: 'member_plan', gymId: ID, memberId: ID });
    for (const bad of [`/g/${ID}/members/x/plan`, `/g/${ID}/members/${ID}/plan/extra`, `/g/${ID}/members/${ID.toUpperCase()}/plan`, `/g/${ID}/members/%2e%2e/plan`]) {
      expect(parsePath(bad).name, bad).toBe('not_found');
    }
  });
  it('opens an exercise written into a plan, but only with the app\'s id shape', () => {
    expect(parsePath(`/g/${ID}/exercises/ex-lq3k9a`)).toEqual({ name: 'exercise', gymId: ID, exerciseId: 'ex-lq3k9a' });
    expect(parsePath(`/g/${ID}/exercises/ex-lq3k9a-2`).name).toBe('exercise');
    for (const bad of ['ex-', 'ex-UPPER', 'ex-a b', 'ex-%2e%2e', 'ex-<script>', 'x-lq3k9a', `ex-${'a'.repeat(21)}`, 'ex-a-12345']) {
      expect(parsePath(`/g/${ID}/exercises/${bad}`).name, bad).toBe('not_found');
    }
  });
});
