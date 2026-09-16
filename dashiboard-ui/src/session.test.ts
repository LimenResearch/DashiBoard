import { describe, it, expect, beforeEach, vi } from 'vitest';
import { flush, reconcile } from 'solid-js';

// `session.ts` reads the gate flag once at module load into a signal (persist.ts's pattern:
// module-level state, not a per-render read), so a stale cached module would carry a stale
// answer across tests. `vi.resetModules()` forces every dynamic `import()` below to re-execute
// the module against the sessionStorage this test just set up, exactly as a fresh tab would.
beforeEach(() => {
  sessionStorage.clear();
  vi.resetModules();
});

describe('session', () => {
  it('has no previous session when the document is empty', async () => {
    const { hasPreviousSession } = await import('./session');
    const { importCards, emptyCards, LOADER_STORE } = await import('./stores');
    importCards(emptyCards()); LOADER_STORE[1](reconcile([])); await flush();
    expect(hasPreviousSession()).toBe(false);
  });
  it('has one when something was restored, until it is answered', async () => {
    const { hasPreviousSession, recoverSession, sessionSummary } = await import('./session');
    const { importCards } = await import('./stores');
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: { g: [] } }); await flush();
    expect(hasPreviousSession()).toBe(true);
    expect(sessionSummary()).toEqual({ columns: 0, groups: 1, cards: 1 });
    recoverSession();
    expect(hasPreviousSession()).toBe(false);
    expect(sessionStorage.getItem('dashi.gate')).toBe('answered');
  });
  it('resetSession removes exactly the dashi.* keys and reloads', async () => {
    const { resetSession } = await import('./session');
    sessionStorage.setItem('dashi.cards', '{}'); sessionStorage.setItem('dashi.tab', '"process"');
    sessionStorage.setItem('other', '1');
    const reload = vi.fn();
    resetSession(reload);
    expect(sessionStorage.getItem('dashi.cards')).toBeNull();
    expect(sessionStorage.getItem('dashi.tab')).toBeNull();
    expect(sessionStorage.getItem('other')).toBe('1');
    expect(reload).toHaveBeenCalledTimes(1);
  });
});
