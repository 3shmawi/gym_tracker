import { isLibraryId } from '../exercises/catalog';
import { numberLocale, useI18n } from '../i18n';
import type { Targets } from '../plans/edit';
import type { ExerciseDiff } from '../plans/templateDiff';
import { LIMITS, type PlanDay, type PlanExercise, type Unit } from '../plans/model';
import { nameIn } from '../plans/text';
import { Icon } from './icons';
import { ExerciseThumb } from './Picture';

// One day of a plan: its name and actions, and a table of its exercises with
// the targets edited in place (board "Dashboard 6"). Pure view: data in,
// callbacks out. Numbers are clamped to the plan limits when they are
// committed (Enter or leaving the field), like the app's steppers.

type Move = 'earlier' | 'later';

interface Props {
  readonly day: PlanDay;
  readonly index: number;
  readonly dayCount: number;
  readonly editable: boolean;
  readonly covers: ReadonlyMap<string, readonly string[]>;
  readonly cloudName: string | null;
  readonly onDay: (action: 'rename' | 'delete' | Move) => void;
  readonly onAdd: () => void;
  readonly onTargets: (exerciseId: string, targets: Targets) => void;
  readonly onSuperset: (exerciseId: string, on: boolean) => void;
  readonly onExercise: (exerciseId: string, action: 'rename' | 'delete' | Move) => void;
  /** D4: exercises of this day that differ from the template, by exercise id. */
  readonly differs?: ReadonlyMap<string, ExerciseDiff>;
  readonly onReset?: (exerciseId: string) => void;
}

const UNITS: readonly Unit[] = ['kg', 'plate', 'reps'];

function NumberCell({ value, min, max, step, label, disabled, onCommit }: { readonly value: number; readonly min: number; readonly max: number; readonly step: number; readonly label: string; readonly disabled: boolean; readonly onCommit: (v: number) => void }) {
  // Uncontrolled: a re-render of the page (pictures arriving, another field
  // saved) must never wipe what is being typed. A new stored value remounts it.
  return (
    <input
      key={value}
      class="in num-in"
      type="number"
      inputMode="numeric"
      min={min}
      max={max}
      step={step}
      defaultValue={String(value)}
      aria-label={label}
      disabled={disabled}
      onChange={(event) => {
        const el = event.currentTarget;
        const raw = Number(el.value);
        const next = Number.isFinite(raw) && el.value.trim() !== '' ? Math.min(max, Math.max(min, Math.round(raw))) : value;
        el.value = String(next);
        if (next !== value) onCommit(next);
      }}
    />
  );
}

export function PlanDayView({ day, index, dayCount, editable, covers, cloudName, onDay, onAdd, onTargets, onSuperset, onExercise, differs, onReset }: Props) {
  const { t, lang } = useI18n();
  const dayName = nameIn(lang, day.name);
  const other = lang === 'ar' ? day.name.en : day.name.ar;
  const unitLabel: Record<Unit, string> = { kg: t('plan.unitKg'), plate: t('plan.unitPlate'), reps: t('plan.unitReps') };
  const stepLabel = (s: number) => t('plan.stepKg', { step: new Intl.NumberFormat(numberLocale(lang)).format(s) });

  const row = (e: PlanExercise, i: number) => {
    const name = nameIn(lang, e.name);
    const second = lang === 'ar' ? e.name.en : e.name.ar;
    const last = i === day.exercises.length - 1;
    const diff = differs?.get(e.id);
    const steps = LIMITS.weightSteps.includes(e.step) ? LIMITS.weightSteps : [...LIMITS.weightSteps, e.step].sort((a, b) => a - b);
    return (
      <tr key={e.id} class={[e.superset ? 'paired' : '', diff ? 'differs' : ''].join(' ').trim() || undefined}>
        <td>
          <div class="who">
            <ExerciseThumb cloudName={cloudName} cover={covers.get(e.id)?.[0]} />
            <span class="stack-xs">
              <b class="plain">{name}</b>
              <span class="cap plain" lang={lang === 'ar' ? 'en' : 'ar'}>{second}</span>
              {isLibraryId(e.id) ? null : <span class="badge">{t('plan.ownExercise')}</span>}
              {diff ? (
                <span class="acts-row">
                  <span class="badge tpl-badge">{t('tpl.templateValue', { value: t('tpl.values', { sets: diff.template.sets, reps: diff.template.reps, rest: diff.template.rest }) })}</span>
                  {editable && onReset ? (
                    <button type="button" class="btn sm" aria-label={t('tpl.resetName', { name })} onClick={() => { onReset(e.id); }}>{t('tpl.reset')}</button>
                  ) : null}
                </span>
              ) : null}
            </span>
          </div>
        </td>
        <td>
          <NumberCell value={e.sets} min={LIMITS.minSets} max={LIMITS.maxSets} step={1} label={t('plan.setsFor', { name })} disabled={!editable} onCommit={(v) => { onTargets(e.id, { sets: v }); }} />
        </td>
        <td>
          <NumberCell value={e.reps} min={LIMITS.minReps} max={LIMITS.maxReps} step={1} label={t('plan.repsFor', { name })} disabled={!editable} onCommit={(v) => { onTargets(e.id, { reps: v }); }} />
        </td>
        <td>
          {e.superset ? (
            <span class="cap">{t('plan.pairRest')}</span>
          ) : (
            <NumberCell value={e.rest} min={LIMITS.minRest} max={LIMITS.maxRest} step={LIMITS.restStep} label={t('plan.restFor', { name })} disabled={!editable} onCommit={(v) => { onTargets(e.id, { rest: v }); }} />
          )}
        </td>
        <td>
          {e.unit === 'kg' ? (
            <select class="in sel-in" aria-label={t('plan.stepFor', { name })} disabled={!editable} value={String(e.step)} onChange={(ev) => { onTargets(e.id, { step: Number(ev.currentTarget.value) }); }}>
              {steps.map((s) => (
                <option key={s} value={String(s)}>{stepLabel(s)}</option>
              ))}
            </select>
          ) : (
            <span class="cap" aria-hidden="true">–</span>
          )}
        </td>
        <td>
          <select class="in sel-in" aria-label={t('plan.unitFor', { name })} disabled={!editable} value={e.unit} onChange={(ev) => { onTargets(e.id, { unit: ev.currentTarget.value as Unit }); }}>
            {UNITS.map((u) => (
              <option key={u} value={u}>{unitLabel[u]}</option>
            ))}
          </select>
        </td>
        <td>
          <input type="checkbox" class="chk-in" aria-label={t('plan.supersetFor', { name })} checked={e.superset} disabled={!editable || last} onChange={(ev) => { onSuperset(e.id, ev.currentTarget.checked); }} />
        </td>
        <td class="end">
          {editable ? (
            <div class="acts-row row-acts">
              <button type="button" class="ib" aria-label={t('plan.exEarlier', { name })} disabled={i === 0} onClick={() => { onExercise(e.id, 'earlier'); }}>
                <span class="flip rot-up"><Icon name="chevronLeft" /></span>
              </button>
              <button type="button" class="ib" aria-label={t('plan.exLater', { name })} disabled={last} onClick={() => { onExercise(e.id, 'later'); }}>
                <span class="flip rot-up"><Icon name="chevronRight" /></span>
              </button>
              <button type="button" class="ib" aria-label={t('plan.exRename', { name })} onClick={() => { onExercise(e.id, 'rename'); }}>
                <Icon name="pencil" />
              </button>
              <button type="button" class="ib danger" aria-label={t('plan.exDelete', { name })} onClick={() => { onExercise(e.id, 'delete'); }}>
                <Icon name="close" />
              </button>
            </div>
          ) : null}
        </td>
      </tr>
    );
  };

  return (
    <section class="panel" aria-labelledby="day-title">
      <div class="row-between">
        <div class="stack-xs">
          <h2 class="h2 plain" id="day-title">{dayName}</h2>
          <span class="cap plain" lang={lang === 'ar' ? 'en' : 'ar'}>{other}</span>
        </div>
        {editable ? (
          <div class="acts-row" role="group" aria-label={t('plan.dayActions', { name: dayName })}>
            <button type="button" class="ib" aria-label={t('plan.dayEarlier')} disabled={index === 0} onClick={() => { onDay('earlier'); }}>
              <span class="flip"><Icon name="chevronLeft" /></span>
            </button>
            <button type="button" class="ib" aria-label={t('plan.dayLater')} disabled={index === dayCount - 1} onClick={() => { onDay('later'); }}>
              <span class="flip"><Icon name="chevronRight" /></span>
            </button>
            <button type="button" class="btn sm" onClick={() => { onDay('rename'); }}>{t('plan.renameDay')}</button>
            <button type="button" class="btn sm danger" disabled={dayCount <= 1} onClick={() => { onDay('delete'); }}>{t('plan.deleteDay')}</button>
          </div>
        ) : null}
      </div>

      {day.exercises.length === 0 ? (
        <p class="sub">{t('plan.dayEmpty')}</p>
      ) : (
        <div class="tblbox">
          <table class="t plan-t">
            <thead>
              <tr>
                <th scope="col">{t('plan.colExercise')}</th>
                <th scope="col">{t('plan.colSets')}</th>
                <th scope="col">{t('plan.colReps')}</th>
                <th scope="col">{t('plan.colRest')}</th>
                <th scope="col">{t('plan.colStep')}</th>
                <th scope="col">{t('plan.colUnit')}</th>
                <th scope="col">{t('plan.colSuperset')}</th>
                <th scope="col"><span class="sr-only">{t('plan.colActions')}</span></th>
              </tr>
            </thead>
            <tbody>{day.exercises.map(row)}</tbody>
          </table>
        </div>
      )}
      {editable ? (
        <div class="acts-row">
          <button type="button" class="btn" disabled={day.exercises.length >= LIMITS.maxExercisesPerDay} onClick={onAdd}>
            <Icon name="plus" />
            {t('plan.addExercise')}
          </button>
          {day.exercises.length >= LIMITS.maxExercisesPerDay ? <span class="cap">{t('plan.limitExercises')}</span> : null}
        </div>
      ) : null}
    </section>
  );
}
