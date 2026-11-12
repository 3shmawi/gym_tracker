import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { Failure } from '../core/failure';
import { libraryExercise } from '../exercises/catalog';
import type { MediaRepository } from '../exercises/media';
import { useGymMedia } from '../exercises/useGymMedia';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n } from '../i18n';
import type { Member } from '../members/members';
import type { Plan } from '../plans/model';
import type { PlansRepository } from '../plans/plans';
import { byExercise, fillWeeks, MOVE_DAY_ID, perWeek, type Progress, type ProgressRepository } from '../progress/progress';
import { dateLabel, gymWeek, num, weekLabel, weekTick } from '../progress/weeks';
import { BarChart, LineChart } from './Charts';
import { Icon } from './icons';
import { ExerciseThumb } from './Picture';
import { ErrorView, LoadingView, StateBlock } from './states';

// A member's progress in this gym (D5; design board 10, "his workouts in this
// gym"): stats, the last 12 weeks, recent workouts, weight progress per
// exercise. Reads the views of migration 0012 only; nothing is written.

type Loaded = { readonly state: 'loading' } | { readonly state: 'failed'; readonly failure: Failure } | { readonly state: 'ready'; readonly progress: Progress; readonly plan: Plan | null };

function useProgress(repo: ProgressRepository, plans: PlansRepository, memberId: string) {
  const [data, setData] = useState<Loaded>({ state: 'loading' });
  const token = useRef(0);
  const reload = useCallback(async () => {
    const mine = ++token.current;
    setData({ state: 'loading' });
    const [p, plan] = await Promise.all([repo.load(memberId), plans.get(memberId)]);
    if (mine !== token.current) return;
    // The plan only names days and exercises; without it, names fall back.
    setData(p.ok ? { state: 'ready', progress: p.value, plan: plan.ok ? plan.value.plan : null } : { state: 'failed', failure: p.failure });
  }, [repo, plans, memberId]);
  useEffect(() => {
    void reload();
    return () => {
      token.current++;
    };
  }, [reload]);
  return { data, reload };
}

interface Props {
  readonly gym: ManagedGym;
  readonly member: Member;
  readonly progress: ProgressRepository;
  readonly plans: PlansRepository;
  readonly media: MediaRepository;
  readonly cloudName: string | null;
}

export function MemberProgress(props: Props) {
  const { t } = useI18n();
  const { member, gym } = props;
  const title = <h2 class="h2" id="s-progress">{t('prog.title', { gym: gym.name })}</h2>;
  if (member.status === 'ended') {
    return (
      <section class="panel" aria-labelledby="s-progress">
        {title}
        <StateBlock icon="lock" title={t('prog.endedTitle')}><p class="sub">{t('prog.endedBody')}</p></StateBlock>
      </section>
    );
  }
  if (member.status === 'pending') {
    return (
      <section class="panel" aria-labelledby="s-progress">
        {title}
        <StateBlock icon="clock" title={t('prog.pendingTitle')}><p class="sub">{t('prog.pendingBody')}</p></StateBlock>
      </section>
    );
  }
  return <ActiveProgress {...props} title={title} />;
}

function ActiveProgress({ gym, member, progress, plans, media, cloudName, title }: Props & { readonly title: preact.JSX.Element }) {
  const { t, lang } = useI18n();
  const { data, reload } = useProgress(progress, plans, member.id);
  const gymMedia = useGymMedia(media, gym.id);
  const covers = gymMedia.data.state === 'ready' ? gymMedia.data.media.pictures : new Map<string, readonly string[]>();
  const now = useMemo(() => new Date(), [data]);
  const [exercise, setExercise] = useState<string | null>(null);

  if (data.state === 'loading') return <section class="panel" aria-labelledby="s-progress" aria-busy="true">{title}<span class="sr-only">{t('prog.loading')}</span><LoadingView /></section>;
  if (data.state === 'failed') return <section class="panel" aria-labelledby="s-progress">{title}<ErrorView failure={data.failure} onRetry={() => void reload()} /></section>;

  const { summary, weeks, workouts, points } = data.progress;
  const plan = data.plan;
  if (!summary || summary.workoutsTotal === 0) {
    return (
      <section class="panel" aria-labelledby="s-progress">
        {title}
        <StateBlock icon="dumbbell" title={t('prog.noneTitle')}><p class="sub">{t('prog.noneBody')}</p></StateBlock>
      </section>
    );
  }

  const exName = (id: string) => {
    for (const d of plan?.days ?? []) {
      const e = d.exercises.find((x) => x.id === id);
      if (e) return lang === 'ar' ? e.name.ar : e.name.en;
    }
    const lib = libraryExercise(id);
    return lib ? (lang === 'ar' ? lib.ar : lib.en) : t('prog.exUnknown');
  };
  const dayName = (id: string | null) => {
    // A Move games round (docs/designs/move_games.md §8): not a plan day.
    if (id === MOVE_DAY_ID) return t('prog.dayMove');
    const d = id ? plan?.days.find((x) => x.id === id) : undefined;
    return d ? (lang === 'ar' ? d.name.ar : d.name.en) : t('prog.dayGone');
  };
  const dash = t('prog.dash');
  const n = (v: number, digits = 0) => num(lang, v, digits);

  // Stats ------------------------------------------------------------------
  const avg = perWeek(summary, now);
  const levelName = (l: typeof summary.level) => t(`prog.level.${l}`);
  const nextLine = summary.weeksToNext === null ? t('prog.top') : summary.comeback ? t('prog.nextComeback', { weeks: n(summary.weeksToNext), level: levelName(summary.bestLevel) }) : t('prog.next', { weeks: n(summary.weeksToNext) });

  // Weeks ------------------------------------------------------------------
  const filled = fillWeeks(weeks, now);
  const thisWeek = gymWeek(now);
  const bars = filled.map((w, i) => ({
    key: String(w.week),
    value: w.workouts,
    tick: i % 3 === filled.length % 3 || w.week === thisWeek ? weekTick(lang, w.week) : null,
    tip: t('prog.weekBar', { week: weekLabel(lang, w.week), count: n(w.workouts) }),
  }));
  const lastWeek = filled.at(-1);

  // Records per workout --------------------------------------------------------
  const recordsBySession = new Map<string, number>();
  for (const p of points) if (p.isRecord) recordsBySession.set(p.sessionId, (recordsBySession.get(p.sessionId) ?? 0) + 1);

  // Exercises -----------------------------------------------------------------
  const exercises = byExercise(points);
  const chosen = exercise && exercises.has(exercise) ? exercise : ([...exercises.keys()][0] ?? null);
  const series = chosen ? exercises.get(chosen) ?? [] : [];

  return (
    <section class="panel stack" aria-labelledby="s-progress">
      {title}
      <p class="cap">{t('prog.only')}</p>

      <div class="stats">
        <div class="stat"><b class="num">{n(summary.workoutsTotal)}</b><span class="cap">{t('prog.total')}</span></div>
        <div class="stat"><b class="num">{avg === null ? dash : n(avg, 1)}</b><span class="cap">{t('prog.perWeek')}</span></div>
        <div class="stat">
          <b>{levelName(summary.level)}</b>
          <span class="cap">{t('prog.levelLabel')} · {t('prog.best', { level: levelName(summary.bestLevel) })}</span>
        </div>
      </div>
      <p class="cap">
        {t('prog.streak', { weeks: n(summary.streakWeeks) })} · {nextLine}
        <br />
        {summary.firstWorkoutAt ? t('prog.first', { date: dateLabel(lang, summary.firstWorkoutAt) }) : null}
        {summary.lastWorkoutAt ? ` · ${t('prog.last', { date: dateLabel(lang, summary.lastWorkoutAt) })}` : null}
      </p>
      <p class="cap"><Icon name="info" /> {t('prog.levelNote')}</p>

      <h3 class="h3">{t('prog.weeksTitle')}</h3>
      <BarChart bars={bars} threshold={3} thresholdLabel={t('prog.activeLine')} label={t('prog.weeksChart', { last: lastWeek ? t('prog.weekBar', { week: weekLabel(lang, lastWeek.week), count: n(lastWeek.workouts) }) : dash })} />
      <details class="tbl">
        <summary>{t('prog.showTable')}</summary>
        <div class="tblbox" tabIndex={0} role="group" aria-label={t('prog.weeksTitle')}>
          <table class="t">
            <caption class="sr-only">{t('prog.weeksTitle')}</caption>
            <thead><tr><th scope="col">{t('prog.colWeek')}</th><th scope="col">{t('prog.colWorkouts')}</th><th scope="col">{t('prog.colDays')}</th><th scope="col">{t('prog.colSets')}</th><th scope="col">{t('prog.colMinutes')}</th><th scope="col">{t('prog.colActive')}</th></tr></thead>
            <tbody>
              {[...filled].reverse().map((w) => (
                <tr key={w.week}>
                  <th scope="row" class="plain-text">{weekLabel(lang, w.week)}</th>
                  <td class="num">{n(w.workouts)}</td>
                  <td class="num">{n(w.trainingDays)}</td>
                  <td class="num">{n(w.setsDone)} / {w.plannedSets === null ? dash : n(w.plannedSets)}</td>
                  <td class="num">{w.minutes === null ? dash : n(w.minutes)}</td>
                  <td>{w.activeWeek ? t('prog.yes') : t('prog.no')}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
      <p class="cap">{t('prog.plannedNote')}</p>

      <h3 class="h3">{t('prog.recentTitle')}</h3>
      <div class="tblbox" tabIndex={0} role="group" aria-label={t('prog.recentTitle')}>
        <table class="t">
          <caption class="sr-only">{t('prog.recentTitle')}</caption>
          <thead><tr><th scope="col">{t('prog.colDate')}</th><th scope="col">{t('prog.colDay')}</th><th scope="col">{t('prog.colDuration')}</th><th scope="col">{t('prog.colSetsFull')}</th><th scope="col">{t('prog.colSkipped')}</th></tr></thead>
          <tbody>
            {workouts.map((w) => {
              const records = recordsBySession.get(w.id) ?? 0;
              const skipped = w.skippedExerciseIds;
              return (
                <tr key={w.id}>
                  <th scope="row">{dateLabel(lang, w.finishedAt)}{records > 0 ? <span class="badge ok">{t('prog.records', { count: n(records) })}</span> : null}</th>
                  <td class="plain-text">{dayName(w.dayId)}</td>
                  <td class="num">{w.durationSeconds === null ? dash : t('prog.minutes', { count: n(Math.round(w.durationSeconds / 60)) })}</td>
                  <td class="num">{n(w.setsDone)} / {n(w.setsLogged)} / {w.plannedSets === null ? dash : n(w.plannedSets)}</td>
                  <td class="plain-text">{skipped === null ? dash : skipped.length === 0 ? t('prog.noneSkipped') : skipped.map(exName).join(lang === 'ar' ? '، ' : ', ')}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <h3 class="h3">{t('prog.exTitle')}</h3>
      {chosen === null ? (
        <p class="cap">{t('prog.exNone')}</p>
      ) : (
        <>
          <div class="ex-pick">
            <ExerciseThumb cloudName={cloudName} cover={covers.get(chosen)?.[0]} />
            <div class="field">
              <label for="ex-pick">{t('prog.exPick')}</label>
              <select id="ex-pick" class="in" value={chosen} onChange={(e) => { setExercise(e.currentTarget.value); }}>
                {[...exercises.keys()].map((id) => (
                  <option key={id} value={id}>{exName(id)}</option>
                ))}
              </select>
            </div>
          </div>
          <LineChart
            points={series.map((p, i) => ({
              key: `${p.sessionId}-${String(i)}`,
              value: p.topWeight,
              record: p.isRecord,
              tick: i === 0 || i === series.length - 1 ? dateLabel(lang, p.finishedAt) : null,
              tip: t('prog.exPoint', { date: dateLabel(lang, p.finishedAt), weight: n(p.topWeight, 2), reps: n(p.repsAtTop) }),
            }))}
            recordLabel={t('prog.record')}
            label={t('prog.exChart', { exercise: exName(chosen), first: n(series[0]?.topWeight ?? 0, 2), last: n(series.at(-1)?.topWeight ?? 0, 2), records: n(series.filter((p) => p.isRecord).length) })}
          />
          <details class="tbl">
            <summary>{t('prog.showTable')}</summary>
            <div class="tblbox" tabIndex={0} role="group" aria-label={`${t('prog.exTitle')}: ${exName(chosen)}`}>
              <table class="t">
                <caption class="sr-only">{t('prog.exTitle')}: {exName(chosen)}</caption>
                <thead><tr><th scope="col">{t('prog.colDate')}</th><th scope="col">{t('prog.colWeight')}</th><th scope="col">{t('prog.colReps')}</th><th scope="col">{t('prog.record')}</th></tr></thead>
                <tbody>
                  {[...series].reverse().map((p, i) => (
                    <tr key={`${p.sessionId}-${String(i)}`}>
                      <th scope="row">{dateLabel(lang, p.finishedAt)}</th>
                      <td class="num">{n(p.topWeight, 2)}</td>
                      <td class="num">{n(p.repsAtTop)}</td>
                      <td>{p.isRecord ? t('prog.yes') : t('prog.no')}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </details>
        </>
      )}
    </section>
  );
}
