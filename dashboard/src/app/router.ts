import { useEffect, useState } from 'preact/hooks';
import { isGymId } from '../gyms/gyms';

export type Route =
  | { readonly name: 'home' }
  | { readonly name: 'sign_in' }
  | { readonly name: 'gyms' }
  | { readonly name: 'members'; readonly gymId: string }
  | { readonly name: 'member'; readonly gymId: string; readonly memberId: string }
  | { readonly name: 'add_members'; readonly gymId: string; readonly role: 'trainee' | 'captain' }
  | { readonly name: 'not_found' };

/** Paths are fixed strings; a gym id must be a UUID. Anything else is not found. */
export function parsePath(pathname: string): Route {
  const path = pathname.replace(/\/+$/, '') || '/';
  if (path === '/') return { name: 'home' };
  if (path === '/sign-in') return { name: 'sign_in' };
  if (path === '/gyms') return { name: 'gyms' };
  const members = /^\/g\/([^/]+)\/members$/.exec(path) ?? /^\/g\/([^/]+)$/.exec(path);
  if (members?.[1] && isGymId(members[1])) return { name: 'members', gymId: members[1] };
  const add = /^\/g\/([^/]+)\/members\/(add|add-captain)$/.exec(path);
  if (add?.[1] && isGymId(add[1])) return { name: 'add_members', gymId: add[1], role: add[2] === 'add-captain' ? 'captain' : 'trainee' };
  const member = /^\/g\/([^/]+)\/members\/([^/]+)$/.exec(path);
  if (member?.[1] && member[2] && isGymId(member[1]) && isGymId(member[2])) return { name: 'member', gymId: member[1], memberId: member[2] };
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
    case 'add_members':
      return `/g/${route.gymId}/members/${route.role === 'captain' ? 'add-captain' : 'add'}`;
    case 'not_found':
      return '/';
  }
}

export function navigate(route: Route, replace = false): void {
  const path = pathOf(route);
  if (replace) window.history.replaceState(null, '', path);
  else window.history.pushState(null, '', path);
  window.dispatchEvent(new PopStateEvent('popstate'));
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parsePath(window.location.pathname));
  useEffect(() => {
    const onPop = () => {
      setRoute(parsePath(window.location.pathname));
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
