import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { AuthService, SignedIn } from '../auth/auth';
import type { Captcha } from '../auth/turnstile';
import type { Failure } from '../core/failure';
import { useOnline } from '../core/online';
import { loadPrefs, savePrefs, type Prefs } from '../core/prefs';
import type { GymsRepository, ManagedGym } from '../gyms/gyms';
import { I18nContext, makeI18n } from '../i18n';
import { GymPickerPage } from '../pages/GymPickerPage';
import type { MembersRepository } from '../members/members';
import type { MediaRepository } from '../exercises/media';
import type { PlansRepository } from '../plans/plans';
import type { TemplatesRepository } from '../plans/templates';
import { TemplatesPage } from '../pages/TemplatesPage';
import { PlanPage } from '../pages/PlanPage';
import { AddMembersPage } from '../pages/AddMembersPage';
import { ExercisePage } from '../pages/ExercisePage';
import { ExercisesPage } from '../pages/ExercisesPage';
import { MemberPage } from '../pages/MemberPage';
import { MembersPage } from '../pages/MembersPage';
import { SignInPage } from '../pages/SignInPage';
import { Shell, type ShellProps } from '../ui/Shell';
import { ErrorView, ForbiddenView, LoadingView, NoGymView, NotFoundView, SessionEndedView } from '../ui/states';
import { navigate, useRoute } from './router';

export interface AppServices {
  readonly auth: AuthService;
  readonly gyms: GymsRepository;
  /** Turnstile, when a site key is configured; otherwise null. */
  readonly captcha: Captcha | null;
  readonly members: MembersRepository;
  /** The bitmap for the middle of the QR: the gym's logo, else the app icon. */
  readonly loadLogo: (logoPath: string | null) => Promise<ImageBitmap | null>;
  /** Exercise pictures and videos (D2). */
  readonly media: MediaRepository;
  /** Cloudinary cloud name of the picture library, or null (plain tiles). */
  readonly cloudName: string | null;
  /** Members' plans (D3). */
  readonly plans: PlansRepository;
  /** The gym's plan templates (D4). */
  readonly templates: TemplatesRepository;
}

type Session =
  | { readonly state: 'checking' }
  | { readonly state: 'signed_out' }
  | { readonly state: 'ended' } // was signed in, then the session went away
  | { readonly state: 'signed_in'; readonly user: SignedIn };

type Gyms =
  | { readonly state: 'loading' }
  | { readonly state: 'failed'; readonly failure: Failure }
  | { readonly state: 'ready'; readonly gyms: readonly ManagedGym[] };

export function App({ services }: { readonly services: AppServices }) {
  const [prefs, setPrefs] = useState<Prefs>(loadPrefs);
  const i18n = useMemo(() => makeI18n(prefs.lang), [prefs.lang]);
  const online = useOnline();
  const route = useRoute();
  const [session, setSession] = useState<Session>({ state: 'checking' });
  const [gyms, setGyms] = useState<Gyms>({ state: 'loading' });
  // Set while the person signs out on purpose, so it isn't shown as "session ended".
  const signingOut = useRef(false);

  // <html lang dir> and the theme follow the preferences.
  useEffect(() => {
    const root = document.documentElement;
    root.lang = prefs.lang;
    root.dir = i18n.dir;
    root.dataset.theme = prefs.theme;
    document.title = i18n.t('app.name');
    savePrefs(prefs);
  }, [prefs, i18n]);

  useEffect(() => {
    let alive = true;
    void services.auth.current().then((result) => {
      if (!alive) return;
      setSession(result.ok && result.value ? { state: 'signed_in', user: result.value } : { state: 'signed_out' });
    });
    const stop = services.auth.onSignedOut(() => {
      if (signingOut.current) return;
      setSession((s) => (s.state === 'signed_in' ? { state: 'ended' } : s));
    });
    return () => {
      alive = false;
      stop();
    };
  }, [services]);

  const loadGyms = useCallback(
    (user: SignedIn) => {
      setGyms({ state: 'loading' });
      void services.gyms.managedGyms(user.userId).then((result) => {
        if (!result.ok && result.failure.kind === 'session_ended') {
          setSession({ state: 'ended' });
          return;
        }
        setGyms(result.ok ? { state: 'ready', gyms: result.value } : { state: 'failed', failure: result.failure });
      });
    },
    [services],
  );

  useEffect(() => {
    if (session.state === 'signed_in') loadGyms(session.user);
  }, [session, loadGyms]);

  const signOut = useCallback(() => {
    signingOut.current = true;
    void services.auth.signOut().then(() => {
      signingOut.current = false;
      setSession({ state: 'signed_out' });
      navigate({ name: 'sign_in' }, true);
    });
  }, [services]);

  // A manager of exactly one gym goes straight to it (not during render).
  const onlyGymId =
    session.state === 'signed_in' && gyms.state === 'ready' && gyms.gyms.length === 1 && (route.name === 'home' || route.name === 'sign_in')
      ? gyms.gyms[0]?.id
      : undefined;
  useEffect(() => {
    if (onlyGymId) navigate({ name: 'members', gymId: onlyGymId }, true);
  }, [onlyGymId]);

  const shellBase: Omit<ShellProps, 'children' | 'gym' | 'gyms' | 'nav'> = {
    prefs,
    onPrefs: setPrefs,
    online,
    email: session.state === 'signed_in' ? session.user.email : null,
    onSignOut: session.state === 'signed_in' ? signOut : null,
  };

  const content = (() => {
    if (session.state === 'checking') return <Shell {...shellBase}><LoadingView /></Shell>;
    if (session.state === 'ended') {
      return (
        <Shell {...shellBase}>
          <SessionEndedView onSignIn={() => { setSession({ state: 'signed_out' }); navigate({ name: 'sign_in' }, true); }} />
        </Shell>
      );
    }
    if (session.state === 'signed_out') {
      return (
        <Shell {...shellBase}>
          <SignInPage
            auth={services.auth}
            captcha={services.captcha}
            online={online}
            onSignedIn={(user) => {
              setSession({ state: 'signed_in', user });
              navigate({ name: 'home' }, true);
            }}
          />
        </Shell>
      );
    }
    if (gyms.state === 'loading') return <Shell {...shellBase}><LoadingView /></Shell>;
    if (gyms.state === 'failed') {
      return <Shell {...shellBase}><ErrorView failure={gyms.failure} onRetry={() => { loadGyms(session.user); }} /></Shell>;
    }
    const list = gyms.gyms;
    if (list.length === 0) return <Shell {...shellBase}><NoGymView onSignOut={signOut} /></Shell>;

    switch (route.name) {
      case 'home':
      case 'sign_in':
      case 'gyms': {
        if (onlyGymId) return <Shell {...shellBase}><LoadingView /></Shell>;
        return (
          <Shell {...shellBase} gyms={list}>
            <GymPickerPage gyms={list} onPick={(gym) => { navigate({ name: 'members', gymId: gym.id }); }} />
          </Shell>
        );
      }
      case 'members':
      case 'member':
      case 'member_plan':
      case 'add_members': {
        const gym = list.find((g) => g.id === route.gymId);
        if (!gym) {
          return (
            <Shell {...shellBase} gyms={list}>
              <ForbiddenView onPickAnother={() => { navigate({ name: 'gyms' }); }} onSignOut={signOut} />
            </Shell>
          );
        }
        return (
          <Shell {...shellBase} gyms={list} gym={gym} nav="members">
            {route.name === 'members' && <MembersPage gym={gym} members={services.members} />}
            {route.name === 'member' && (
              <MemberPage gym={gym} memberId={route.memberId} members={services.members} loadLogo={services.loadLogo} />
            )}
            {route.name === 'member_plan' && (
              <PlanPage gym={gym} memberId={route.memberId} members={services.members} plans={services.plans} templates={services.templates} media={services.media} cloudName={services.cloudName} online={online} />
            )}
            {route.name === 'add_members' && (
              <AddMembersPage gym={gym} role={route.role} userId={session.user.userId} members={services.members} loadLogo={services.loadLogo} />
            )}
          </Shell>
        );
      }
      case 'templates': {
        const gym = list.find((g) => g.id === route.gymId);
        if (!gym) {
          return (
            <Shell {...shellBase} gyms={list}>
              <ForbiddenView onPickAnother={() => { navigate({ name: 'gyms' }); }} onSignOut={signOut} />
            </Shell>
          );
        }
        return (
          <Shell {...shellBase} gyms={list} gym={gym} nav="templates">
            <TemplatesPage gym={gym} templates={services.templates} online={online} />
          </Shell>
        );
      }
      case 'exercises':
      case 'exercise': {
        const gym = list.find((g) => g.id === route.gymId);
        if (!gym) {
          return (
            <Shell {...shellBase} gyms={list}>
              <ForbiddenView onPickAnother={() => { navigate({ name: 'gyms' }); }} onSignOut={signOut} />
            </Shell>
          );
        }
        return (
          <Shell {...shellBase} gyms={list} gym={gym} nav="exercises">
            {route.name === 'exercises' ? (
              <ExercisesPage gym={gym} media={services.media} cloudName={services.cloudName} />
            ) : (
              <ExercisePage key={route.exerciseId} gym={gym} exerciseId={route.exerciseId} media={services.media} cloudName={services.cloudName} online={online} />
            )}
          </Shell>
        );
      }
      case 'not_found':
        return (
          <Shell {...shellBase} gyms={list}>
            <NotFoundView onHome={() => { navigate({ name: 'home' }); }} />
          </Shell>
        );
    }
  })();

  return <I18nContext.Provider value={i18n}>{content}</I18nContext.Provider>;
}
