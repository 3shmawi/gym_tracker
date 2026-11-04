import { setLeaveGuard } from '../app/router';
import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import type { Failure } from '../core/failure';
import type { Member, MembersRepository } from '../members/members';

export type MembersState =
  | { readonly state: 'loading' }
  | { readonly state: 'failed'; readonly failure: Failure }
  | { readonly state: 'ready'; readonly members: readonly Member[] };

/** Loads a gym's members; `reload()` shows the skeleton, `refresh()` swaps the list quietly (after a write). */
export function useMembersList(repo: MembersRepository, gymId: string) {
  const [data, setData] = useState<MembersState>({ state: 'loading' });
  const token = useRef(0);

  const run = useCallback(
    async (quiet: boolean) => {
      const mine = ++token.current;
      if (!quiet) setData({ state: 'loading' });
      const result = await repo.list(gymId);
      if (mine !== token.current) return;
      if (result.ok) setData({ state: 'ready', members: result.value });
      else if (!quiet) setData({ state: 'failed', failure: result.failure });
    },
    [repo, gymId],
  );

  useEffect(() => {
    void run(false);
    return () => {
      token.current++;
    };
  }, [run]);

  return {
    data,
    reload: useCallback(() => run(false), [run]),
    refresh: useCallback(() => run(true), [run]),
  };
}

/** Warns before the tab closes or reloads while `active` (codes are on screen and shown once). */
export function useLeaveWarning(active: boolean, message: string): void {
  useEffect(() => {
    if (!active) return;
    setLeaveGuard(() => window.confirm(message));
    const onBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => {
      setLeaveGuard(null);
      window.removeEventListener('beforeunload', onBeforeUnload);
    };
  }, [active, message]);
}
