import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, cleanup, fireEvent, waitFor } from '@solidjs/testing-library';
import { flush, reconcile } from 'solid-js';

// `App`'s `Router` is built from `virtual:file-routes` with browser history, which is fragile to
// render under jsdom (controller's resolution to the brief's layout risk) — so the gate and the
// nav button are their own components, mounted directly here without a router.
//
// Both `SessionGate` and `StartOver` statically import `../session`, which reads the gate flag
// from `sessionStorage` on demand (`hasPreviousSession()` checks storage directly; `bump` is only
// JSX's tracked dependency) — so `session.ts` carries no stale state of its own between tests. The
// module graph still needs resetting because `../stores`'s `CARDS_STORE`/`LOADER_STORE` are
// module-level `persisted` stores that restore themselves from storage once, at import, and would
// otherwise carry a prior test's `importCards` into this one (same reason as session.test.ts).
// `vi.resetModules()` plus a dynamic `import()` of the component under test, per case, gives each
// test a fresh module graph reading the sessionStorage that test just set up — no test-only reset
// hook needed.
beforeEach(() => {
  sessionStorage.clear();
  vi.resetModules();
});
afterEach(cleanup);

describe('SessionGate', () => {
  it('gates a restored session and lets Recover dismiss it', async () => {
    const { importCards } = await import('../stores');
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: {} });
    await flush();

    const { SessionGate } = await import('./SessionGate');
    const { container, getByText } = render(() => <SessionGate />);
    await waitFor(() => expect(container.querySelector('[data-session-gate]')).not.toBeNull());
    expect(container.textContent).toMatch(/1 card/);

    fireEvent.click(getByText('Recover'));
    await flush();
    expect(container.querySelector('[data-session-gate]')).toBeNull();
  });

  it('does not gate an empty document', async () => {
    const { importCards, emptyCards } = await import('../stores');
    importCards(emptyCards());
    await flush();

    const { SessionGate } = await import('./SessionGate');
    const { container } = render(() => <SessionGate />);
    await flush();
    expect(container.querySelector('[data-session-gate]')).toBeNull();
  });

  it('does not gate a document that grew during this session', async () => {
    // A fresh tab has no `dashi.gate` and nothing restored. The first Load used to raise the
    // overlay — "A previous session is here: 12 columns loaded · 0 groups · 0 cards" — over a
    // session that was never previous, where "Start fresh" would have wiped what had just been
    // loaded. The gate is a fact about load time, so it is decided once (final review, 2026-09-16).
    const { LOADER_STORE } = await import('../stores');
    const { hasPreviousSession } = await import('../session');

    const { SessionGate } = await import('./SessionGate');
    const { container } = render(() => <SessionGate />);
    await flush();

    LOADER_STORE[1](reconcile([
      { name: 'TEMP', type: 'numerical' as const, eltype: 'float', summary: { min: 0, max: 1 } },
    ]));
    await flush();

    expect(container.querySelector('[data-session-gate]')).toBeNull();
    expect(hasPreviousSession()).toBe(false);
  });

  it('Start over asks before clearing', async () => {
    const { importCards } = await import('../stores');
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: {} });
    await flush();
    const { recoverSession } = await import('../session');
    recoverSession();

    const { StartOver } = await import('./StartOver');
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const { getByText } = render(() => <StartOver />);
    fireEvent.click(getByText('Start over'));
    expect(confirm).toHaveBeenCalled();
    expect(sessionStorage.getItem('dashi.cards')).not.toBeNull();   // declined → untouched
    confirm.mockRestore();
  });
});
