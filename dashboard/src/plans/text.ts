import type { Failure } from '../core/failure';
import type { I18n, MessageKey } from '../i18n';
import type { Change, TargetField } from './diff';
import type { PlanName } from './model';
import type { EditError } from './edit';

// Fixed messages for the plan pages: one per failure, never the server's text.

export function planFailureKey(failure: Failure): MessageKey {
  switch (failure.kind) {
    case 'offline':
      return 'plan.errOffline';
    case 'forbidden':
      return 'plan.errForbidden';
    case 'session_ended':
      return 'fail.session';
    case 'rate_limited':
      return 'fail.rateLimited';
    case 'invalid':
    case 'not_found':
      return 'plan.errInvalid';
    case 'conflict':
      return failure.reason === 'plan_changed' ? 'conflict.title' : 'plan.errInvalid';
    default:
      return 'plan.errServer';
  }
}

export function editErrorKey(error: EditError): MessageKey {
  switch (error) {
    case 'too_many':
      return 'plan.limitExercises';
    case 'last_day':
      return 'plan.lastDay';
    case 'duplicate':
      return 'plan.duplicate';
    case 'invalid_name':
      return 'name.empty';
    case 'not_found':
      return 'plan.errInvalid';
  }
}

export const nameIn = (lang: I18n['lang'], name: PlanName): string => (lang === 'ar' ? name.ar : name.en);

const FIELD_KEY: Record<TargetField, MessageKey> = {
  sets: 'diff.f.sets',
  reps: 'diff.f.reps',
  rest: 'diff.f.rest',
  step: 'diff.f.step',
  unit: 'diff.f.unit',
  superset: 'diff.f.superset',
};

/** One readable line per change, in the page's language. */
export function changeLine({ t, lang }: Pick<I18n, 't' | 'lang'>, c: Change): string {
  const n = (name: PlanName) => nameIn(lang, name);
  switch (c.kind) {
    case 'day_added':
      return t('diff.dayAdded', { day: n(c.day) });
    case 'day_removed':
      return t('diff.dayRemoved', { day: n(c.day) });
    case 'day_renamed':
      return t('diff.dayRenamed', { from: n(c.from), to: n(c.to) });
    case 'days_reordered':
      return t('diff.daysReordered');
    case 'exercise_added':
      return t('diff.exerciseAdded', { day: n(c.day), exercise: n(c.exercise) });
    case 'exercise_removed':
      return t('diff.exerciseRemoved', { day: n(c.day), exercise: n(c.exercise) });
    case 'exercise_renamed':
      return t('diff.exerciseRenamed', { day: n(c.day), from: n(c.from), to: n(c.to) });
    case 'exercises_reordered':
      return t('diff.exercisesReordered', { day: n(c.day) });
    case 'targets_changed':
      return t('diff.targets', { day: n(c.day), exercise: n(c.exercise), fields: c.fields.map((f) => t(FIELD_KEY[f])).join(lang === 'ar' ? '، ' : ', ') });
  }
}
