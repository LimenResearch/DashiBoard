import { describe, it, expect, beforeEach, vi } from 'vitest';
import { flush, reconcile } from 'solid-js';

// `session.ts` itself reads the gate flag from `sessionStorage` on demand — `hasPreviousSession()`
// checks storage directly each call, with a `bump` signal only as JSX's tracked dependency — so
// it has no stale module-level state of its own. The module graph still needs resetting because
// `stores.ts`'s `CARDS_STORE`/`LOADER_STORE` are module-level `persisted` stores (persist.ts's
// pattern) that restore themselves from storage once, at import, and would otherwise carry a
// prior test's `importCards` across into this one. `vi.resetModules()` forces every dynamic
// `import()` below to re-execute both modules against the sessionStorage this test just set up,
// exactly as a fresh tab would.
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
    // The stores are filled *before* `./session` is imported, because that is what "restored"
    // means: `persist.ts` puts the document back at import time, and the gate reads it once,
    // there. Filling them afterwards is a document that grew during this session — the case the
    // test below pins.
    const { importCards } = await import('./stores');
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: { g: [] } }); await flush();
    const { hasPreviousSession, recoverSession, sessionSummary } = await import('./session');
    expect(hasPreviousSession()).toBe(true);
    expect(sessionSummary()).toEqual({ columns: 0, groups: 1, cards: 1 });
    recoverSession();
    expect(hasPreviousSession()).toBe(false);
    expect(sessionStorage.getItem('dashi.gate')).toBe('answered');
  });
  it('has none when the document only grew after load', async () => {
    // A fresh tab loads a file: the stores fill, but nothing was restored, so there is no
    // previous session to offer and no overlay whose "Start fresh" could wipe the new work.
    const { hasPreviousSession } = await import('./session');
    const { importCards } = await import('./stores');
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: { g: [] } }); await flush();
    expect(hasPreviousSession()).toBe(false);
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
