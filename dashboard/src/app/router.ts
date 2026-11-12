import { useEffect, useState } from 'preact/hooks';
import { isCustomId, isLibraryId } from '../exercises/catalog';
import { isGymId } from '../gyms/gyms';

/** A quick action that opens its dialog as the plan page loads. */
export type PlanAction = 'copy' | 'replace' | 'save_template';
const ACTION_PATH: Readonly<Record<PlanAction, string>> = { copy: 'copy', replace: 'replace', save_template: 'save-template' };
const ACTION_OF: Readonly<Record<string, PlanAction>> = { copy: 'copy', replace: 'replace', 'save-template': 'save_template' };

export type Route =
  | { readonly name: 'home' }
  | { readonly name: 'sign_in' }
  | { readonly name: 'gyms' }
  | { readonly name: 'members'; readonly gymId: string }
  | { readonly name: 'member'; readonly gymId: string; readonly memberId: string }
  | { readonly name: 'member_plan'; readonly gymId: string; readonly memberId: string; readonly open?: PlanAction | undefined }
  | { readonly name: 'add_members'; readonly gymId: string; readonly role: 'trainee' | 'captain' }
  | { readonly name: 'exercises'; readonly gymId: string }
  | { readonly name: 'templates'; readonly gymId: string }
  | { readonly name: 'settings'; readonly gymId: string }
  | { readonly name: 'exercise'; readonly gymId: string; readonly exerciseId: string }
  | { readonly name: 'not_found' };

/** Paths are fixed strings; a gym id must be a UUID, an exercise id one of the library. Anything else is not found. */
export function parsePath(pathname: string): Route {
  const path = pathname.replace(/\/+$/, '') || '/';
  if (path === '/') return { name: 'home' };
  if (path === '/sign-in') return { name: 'sign_in' };
  if (path === '/gyms') return { name: 'gyms' };
  const members = /^\/g\/([^/]+)\/members$/.exec(path) ?? /^\/g\/([^/]+)$/.exec(path);
  if (members?.[1] && isGymId(members[1])) return { name: 'members', gymId: members[1] };
  const add = /^\/g\/([^/]+)\/members\/(add|add-captain)$/.exec(path);
  if (add?.[1] && isGymId(add[1])) return { name: 'add_members', gymId: add[1], role: add[2] === 'add-captain' ? 'captain' : 'trainee' };
  const plan = /^\/g\/([^/]+)\/members\/([^/]+)\/plan(?:\/(copy|replace|save-template))?$/.exec(path);
  if (plan?.[1] && plan[2] && isGymId(plan[1]) && isGymId(plan[2])) {
    const open = plan[3] ? ACTION_OF[plan[3]] : undefined;
    return open ? { name: 'member_plan', gymId: plan[1], memberId: plan[2], open } : { name: 'member_plan', gymId: plan[1], memberId: plan[2] };
  }
  const member = /^\/g\/([^/]+)\/members\/([^/]+)$/.exec(path);
  if (member?.[1] && member[2] && isGymId(member[1]) && isGymId(member[2])) return { name: 'member', gymId: member[1], memberId: member[2] };
  const settings = /^\/g\/([^/]+)\/settings$/.exec(path);
  if (settings?.[1] && isGymId(settings[1])) return { name: 'settings', gymId: settings[1] };
  const templates = /^\/g\/([^/]+)\/templates$/.exec(path);
  if (templates?.[1] && isGymId(templates[1])) return { name: 'templates', gymId: templates[1] };
  const exercises = /^\/g\/([^/]+)\/exercises$/.exec(path);
  if (exercises?.[1] && isGymId(exercises[1])) return { name: 'exercises', gymId: exercises[1] };
  const exercise = /^\/g\/([^/]+)\/exercises\/([^/]+)$/.exec(path);
  if (exercise?.[1] && exercise[2] && isGymId(exercise[1]) && (isLibraryId(exercise[2]) || isCustomId(exercise[2]))) return { name: 'exercise', gymId: exercise[1], exerciseId: exercise[2] };
  return { name: 'not_found' };
}

export function pathOf(route: Route): string {
  switch (route.name) {
    case 'home':
      return '/';
    case 'sign_in':
      return '/sign-in';
    case 'gyms':
      return '/gyms';
    case 'members':
      return `/g/${route.gymId}/members`;
    case 'member':
      return `/g/${route.gymId}/members/${route.memberId}`;
    case 'member_plan':
      return `/g/${route.gymId}/members/${route.memberId}/plan${route.open ? `/${ACTION_PATH[route.open]}` : ''}`;
    case 'add_members':
      return `/g/${route.gymId}/members/${route.role === 'captain' ? 'add-captain' : 'add'}`;
    case 'exercises':
      return `/g/${route.gymId}/exercises`;
    case 'templates':
      return `/g/${route.gymId}/templates`;
    case 'settings':
      return `/g/${route.gymId}/settings`;
    case 'exercise':
      return `/g/${route.gymId}/exercises/${route.exerciseId}`;
    case 'not_found':
      return '/';
  }
}

// While codes are on screen (shown once), leaving asks first. A page sets the
// guard; navigate() and the browser's Back/Forward both go through it.
let leaveGuard: (() => boolean) | null = null;

export function setLeaveGuard(guard: (() => boolean) | null): void {
  leaveGuard = guard;
}

/** Leaves without asking (the page already asked in its own dialog). */
export function navigateNow(route: Route, replace = false): void {
  leaveGuard = null;
  navigate(route, replace);
}

const INTERNAL = { azmInternal: true } as const;

export function navigate(route: Route, replace = false): void {
  if (leaveGuard && !leaveGuard()) return;
  const path = pathOf(route);
  if (replace) window.history.replaceState(null, '', path);
  else window.history.pushState(null, '', path);
  window.dispatchEvent(new PopStateEvent('popstate', { state: INTERNAL }));
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parsePath(window.location.pathname));
  useEffect(() => {
    let current = window.location.pathname;
    const onPop = (event: PopStateEvent) => {
      const internal = (event.state as { azmInternal?: boolean } | null)?.azmInternal === true;
      if (!internal && leaveGuard && !leaveGuard()) {
        // Back/Forward while codes are shown: stay on this page.
        window.history.pushState(null, '', current);
        return;
      }
      current = window.location.pathname;
      setRoute(parsePath(current));
    };
    window.addEventListener('popstate', onPop);
    return () => {
      window.removeEventListener('popstate', onPop);
    };
  }, []);
  return route;
}

/** Same-origin links: intercept plain left clicks so the page doesn't reload. */
export function linkHandler(route: Route) {
  return (event: MouseEvent) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    navigate(route);
  };
}
