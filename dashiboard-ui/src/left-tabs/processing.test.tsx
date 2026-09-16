import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import payload from '../fixtures/card-ir.json';
import { importCards, addGroup, setNodeId } from '../stores';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  loadJSON: vi.fn(), downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
}));

import { Cards } from './processing';

const CLEAN_PROBE = { valid: true, cols: [], nodes: [], errors: [], issues: [] };

beforeEach(() => {
  sessionStorage.clear();
  postRequest.mockReset();
  postRequest.mockImplementation((page: string, body: unknown) =>
    Promise.resolve(
      page === 'get-card-ir'
        ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                   const full = structuredClone(payload) as Record<string, unknown>;
                   return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
      : page === 'probe-pipeline' ? CLEAN_PROBE
      : page === 'validate-card' ? { valid: true, issues: [] }
      : [],
    ),
  );
  importCards({
    nodes: [{ id: 'r', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [] } }],
    groups: { g: [] },
  });
});
afterEach(cleanup);

const irCalls = () => postRequest.mock.calls.filter((c) => c[0] === 'get-card-ir').length;

describe('an IR refetch', () => {
  it('leaves the card form and the groups editor in place', async () => {
    // Adding a group changes the vocabulary, which refetches the IR. The payload is a new object
    // every time, and three `<Show keyed>`s were keyed on it — so every card form and the whole
    // groups editor were torn down and rebuilt, folding open groups and losing picker state.
    // Measured 2026-09-15 by exactly this comparison.
    const { container } = render(() => <Cards />);
    const q = (sel: string) => container.querySelector(sel);
    await waitFor(() => { if (!q('#node-0-rescale-method-variant') && !q('#method-variant')) throw new Error('form not up'); });

    const before = {
      select: q('#method-variant') ?? q('#node-0-rescale-method-variant'),
      groupInput: q('#group-name-g'),
      groupPicker: q('[data-tabs="kinds"]'),
    };
    const groupDetails = [...container.querySelectorAll('details')].find((d) =>
      d.querySelector('#group-name-g'),
    )!;
    groupDetails.open = true;

    const n = irCalls();
    addGroup();
    await waitFor(() => expect(irCalls()).toBe(n + 1));
    await flush();
    await new Promise((r) => setTimeout(r, 30));
    await flush();

    expect(q('#method-variant') ?? q('#node-0-rescale-method-variant')).toBe(before.select);
    expect(q('#group-name-g')).toBe(before.groupInput);
    expect(q('[data-tabs="kinds"]')).toBe(before.groupPicker);
    expect(groupDetails.open).toBe(true);
  });
});

describe('the continuous probe', () => {
  const probeCalls = () => postRequest.mock.calls.filter((c) => c[0] === 'probe-pipeline');

  it('coalesces a burst of edits into one request', async () => {
    // It fired one POST per committed edit. Every keystroke that commits — every field, every
    // chip — became a document-wide resolve on the server.
    vi.useFakeTimers();
    try {
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);   // settle the mount-time probe
      const n = probeCalls().length;
      setNodeId(0, 'a'); await flush();
      setNodeId(0, 'ab'); await flush();
      setNodeId(0, 'abc'); await flush();
      await vi.advanceTimersByTimeAsync(100);
      expect(probeCalls().length).toBe(n);        // still inside the quiet window
      await vi.advanceTimersByTimeAsync(200);
      expect(probeCalls().length).toBe(n + 1);    // one request for three edits
    } finally {
      vi.useRealTimers();
    }
  });

  it('discards a reply that arrives after a newer request was sent', async () => {
    // Replies are async and the server is not obliged to answer in order. Without a guard the
    // slow answer to the *old* document overwrote the fast answer to the new one.
    vi.useFakeTimers();
    const pending: Array<(v: unknown) => void> = [];
    postRequest.mockImplementation((page: string, body: { nodes?: { id: string }[] }) => {
      if (page === 'get-card-ir') return Promise.resolve(structuredClone(payload));
      if (page === 'probe-pipeline') {
        return new Promise((resolve) => pending.push((v) => resolve({ ...CLEAN_PROBE, cols: [body.nodes?.[0]?.id ?? ''] , ...(v as object) })));
      }
      return Promise.resolve([]);
    });
    try {
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);
      const { PROBE_STORE } = await import('../stores');
      setNodeId(0, 'first'); await flush(); await vi.advanceTimersByTimeAsync(250);
      setNodeId(0, 'second'); await flush(); await vi.advanceTimersByTimeAsync(250);
      expect(pending.length).toBeGreaterThanOrEqual(2);
      const [old, fresh] = pending.slice(-2);
      fresh({}); await flush(); await vi.advanceTimersByTimeAsync(0);
      old({});   await flush(); await vi.advanceTimersByTimeAsync(0);
      expect(PROBE_STORE[0].cols).toEqual(['second']);   // the old reply did not win
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('the card IR', () => {
  it('is fetched whole once, then only its vocabulary', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(irCalls()).toBe(1));
    const first = postRequest.mock.calls.find((c) => c[0] === 'get-card-ir')![1] as { include?: string[] };
    expect(first.include ?? ['defs', 'cards']).toEqual(expect.arrayContaining(['cards']));

    addGroup();
    await waitFor(() => expect(irCalls()).toBe(2));
    const second = postRequest.mock.calls.filter((c) => c[0] === 'get-card-ir')[1][1] as { include?: string[] };
    expect(second.include).toEqual(['defs']);
    // and the form still renders, from the cached cards
    await waitFor(() => expect(container.querySelector('#node-0-rescale-method-variant')).not.toBeNull());
  });
});
