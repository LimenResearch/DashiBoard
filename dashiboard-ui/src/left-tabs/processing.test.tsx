import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor, fireEvent } from '@solidjs/testing-library';
import { flush, reconcile } from 'solid-js';
import payload from '../fixtures/card-ir.json';
import {
  importCards, addGroup, setNodeId, setCardField, confirmDefinition, reportRunIssues, exportCards,
  forgetAllVerdicts, PROBE_STORE, emptyProbe,
} from '../stores';

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
  // `PROBE_STORE` is a module-level store, same as `CARDS_STORE` — `test.isolate: false` shares it
  // across every file in this run, and a test that seeds it (`reportRunIssues`, or a mocked
  // `probe-pipeline` reply carrying issues) must not leak that into the next test's render. See the
  // identical reset in `GroupsEditor.test.tsx` and `routes/index.test.tsx`.
  PROBE_STORE[1](reconcile(emptyProbe()));
  // Verdicts are a module-level signal too; clearing `sessionStorage` does not empty it.
  forgetAllVerdicts();
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

  it('runs for a groups-only document', async () => {
    // Groups first is the usual authoring order, and an empty group is a server-side finding —
    // so short-circuiting on "no cards" left a groups-only document with no live finding at all
    // until the first card existed (final review, 2026-09-16).
    vi.useFakeTimers();
    try {
      importCards({ nodes: [], groups: { g: [] } });
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);
      expect(probeCalls().length).toBe(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('stays quiet for a document with nothing in it', async () => {
    // Nothing to resolve, so nothing to ask: an empty document still answers locally.
    vi.useFakeTimers();
    try {
      importCards({ nodes: [], groups: {} });
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);
      expect(probeCalls().length).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });

  it('does not outlive the tab that scheduled it', async () => {
    // An edit schedules a probe 200 ms out. Unmounting inside that window used to leave the timer
    // running, so a POST went out for a tab that no longer exists — and with real timers it
    // landed in whatever ran next, which is what made the test above flaky on a slow worker.
    render(() => <Cards />);
    await waitFor(() => expect(irCalls()).toBe(1));
    await new Promise((r) => setTimeout(r, 250)); await flush();   // let the mount-time probe go
    const before = probeCalls().length;
    addGroup(); await flush();                                     // schedules a probe in 200 ms
    cleanup();                                                     // the tab goes away first
    await new Promise((r) => setTimeout(r, 300)); await flush();
    expect(probeCalls().length).toBe(before);
  });
});

describe('a warning from the probe', () => {
  it('renders in the warning style and does not block Confirm', async () => {
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(
        page === 'get-card-ir' ? structuredClone(payload)
        : page === 'probe-pipeline' ? { ...CLEAN_PROBE, issues: [{ pointer: '/nodes/0/card', reason: 'overwrites', severity: 'warning', found: null, allowed: null, missing: [], related: [], message: '`TEMP_z` already exists and will be replaced' }] }
        : page === 'validate-card' ? { valid: true, issues: [] }
        : [],
      ),
    );
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-issue-severity="warning"]')).not.toBeNull());
    expect(container.querySelector('[data-issue-severity="warning"]')!.className).toMatch(/warning/);
    // `getAllByText('Confirm')[0]` would press the groups editor's Confirm — it renders above the
    // cards and `beforeEach` seeds group `g`. The card's own Confirm carries this title.
    fireEvent.click(container.querySelector('button[title="mark this card deliberately finished"]')!);
    await waitFor(() => expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull());
  });
});

describe('a card whose probe could not be reached', () => {
  it('reads as "could not check", never as a clean card, and does not confirm', async () => {
    // `validate-card` still answers cleanly — the card's own schema is fine — but the whole-document
    // probe `confirmNode` asks next resolves to `null` (item 1's missing proxy route, mocked here
    // as `postRequest`'s own failure default).
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(
        page === 'get-card-ir' ? structuredClone(payload)
        : page === 'validate-card' ? { valid: true, issues: [] }
        : page === 'probe-pipeline' ? null
        : [],
      ),
    );
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('button[title="mark this card deliberately finished"]')).not.toBeNull());
    fireEvent.click(container.querySelector('button[title="mark this card deliberately finished"]')!);
    await waitFor(() => expect(container.textContent).toMatch(/could not reach/i));
    expect(container.querySelector('[data-state="confirmed"]')).toBeNull();
  });
});

describe('a card is amber until asked', () => {
  // Decided 2026-09-17: red is reserved for "you asked, and it was wrong". The continuous probe
  // keeps running (it feeds the resolved names, the warnings and the pointer next to Run) but its
  // errors no longer paint the card — no red finding, no red dot — until Confirm or a Run asks.
  // A verdict binds to the card's content, so an edit returns it to amber and drops its findings.
  const cardDot = (container: HTMLElement) =>
    [...container.querySelectorAll('details')]
      .find((d) => d.querySelector('[data-card-title]'))!
      .querySelector('[data-state]')!;
  const cardConfirm = (container: HTMLElement) =>
    container.querySelector('button[title="mark this card deliberately finished"]')!;
  const BROKEN = {
    pointer: '/nodes/0/card', reason: 'required', severity: 'error' as const, found: null, allowed: null,
    missing: ['inputs'], related: ['/nodes/0/card/inputs'], message: 'Schema Validation Error',
  };
  const mock = (probe: unknown, card: unknown) =>
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(
        page === 'get-card-ir' ? structuredClone(payload)
        : page === 'probe-pipeline' ? probe
        : page === 'validate-card' ? card
        : [],
      ),
    );

  it('shows no red before Confirm, even while the probe reports an error for it', async () => {
    mock({ ...CLEAN_PROBE, valid: false, issues: [BROKEN] }, { valid: false, issues: [BROKEN] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-title]')).not.toBeNull());
    // The continuous probe has answered once its verdict reached the store.
    await waitFor(() => expect(PROBE_STORE[0].valid).toBe(false));
    await flush();
    expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed');
    expect(cardDot(container).className).toMatch(/bg-warning/);
    expect(container.querySelector('[data-issue-severity="error"]')).toBeNull();
    expect(container.querySelector('[data-finding]')).toBeNull();
    expect(container.textContent).not.toMatch(/schema validation/i);
  });

  it('turns red with its findings on Confirm, and amber again on edit', async () => {
    mock(CLEAN_PROBE, { valid: false, issues: [BROKEN] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(cardConfirm(container)).not.toBeNull());
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('rejected'));
    expect(cardDot(container).className).toMatch(/bg-destructive/);
    expect(container.querySelector('[data-finding]')!.textContent).toMatch(/inputs.*needs a value/);
    setCardField(0, 'suffix', 'edited');
    await flush();
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed'));
    expect(container.querySelector('[data-finding]')).toBeNull();
  });

  it('turns green on a clean Confirm, and a live warning leaves it green', async () => {
    const warning = { ...BROKEN, reason: 'overwrites', severity: 'warning' as const, missing: [], related: [], message: '`TEMP_z` already exists' };
    mock({ ...CLEAN_PROBE, issues: [warning] }, { valid: true, issues: [] });
    const { container } = render(() => <Cards />);
    // The warning renders live, amber, before anyone asks — and the dot stays amber too.
    await waitFor(() => expect(container.querySelector('[data-issue-severity="warning"]')).not.toBeNull());
    expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed');
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('confirmed'));
    await waitFor(() => expect(container.querySelector('[data-issue-severity="warning"]')).not.toBeNull());
    expect(cardDot(container).getAttribute('data-state')).toBe('confirmed');
    expect(cardDot(container).className).toMatch(/bg-success/);
  });

  it('binds the verdict to the card as it was checked, not as it is when the reply lands', async () => {
    // Press Confirm, edit while `validate-card` is in flight, then let it answer clean: the verdict
    // is green on the content the server saw, and the edited card reads as unasked.
    let answerCard: (v: unknown) => void = () => {};
    postRequest.mockImplementation((page: string) =>
      page === 'get-card-ir' ? Promise.resolve(structuredClone(payload))
      : page === 'probe-pipeline' ? Promise.resolve(CLEAN_PROBE)
      : page === 'validate-card' ? new Promise((resolve) => { answerCard = resolve; })
      : Promise.resolve([]));
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(cardConfirm(container)).not.toBeNull());
    const checked = exportCards().nodes[0];
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(postRequest.mock.calls.some((c) => c[0] === 'validate-card')).toBe(true));
    setCardField(0, 'suffix', 'edited-in-flight');
    await flush();
    answerCard({ valid: true, issues: [] });
    const { verdictOf } = await import('../stores');
    await waitFor(() => expect(verdictOf('node:0', checked)?.verdict).toBe('confirmed'));
    expect(verdictOf('node:0', exportCards().nodes[0])).toBeNull();
    expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed');
  });

  it('a failed run before any Confirm turns the card red with the run\'s findings', async () => {
    mock(CLEAN_PROBE, { valid: true, issues: [] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-title]')).not.toBeNull());
    reportRunIssues([BROKEN]);
    await flush();
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('rejected'));
    expect(container.querySelector('[data-finding]')!.textContent).toMatch(/needs a value/);
  });

  it('leaves a confirmed card confirmed when the live probe only warns', async () => {
    const issueFor = (severity: 'error' | 'warning') => ({ ...BROKEN, reason: 'overwrites', severity, missing: [], related: [], message: '`TEMP_z` already exists' });
    confirmDefinition('node:0', exportCards().nodes[0]);
    const issue = issueFor('warning');
    reportRunIssues([issue]);
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(
        page === 'get-card-ir' ? structuredClone(payload)
        : page === 'probe-pipeline' ? { ...CLEAN_PROBE, issues: [issue] }
        : page === 'validate-card' ? { valid: true, issues: [] }
        : [],
      ),
    );
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-title]')).not.toBeNull());
    expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull();
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

describe('the card header', () => {
  it('wraps its actions and truncates its title rather than overflowing', async () => {
    // Check 8 by hand: `dimensionality_reduction : dimensionality_reduction` pushed Remove past
    // the column's edge. jsdom has no layout, so this pins the classes and the full-text title.
    importCards({ nodes: [{ id: 'dimensionality_reduction', card: { type: 'dimensionality_reduction' } }], groups: {} });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-title]')).not.toBeNull());
    const summary = container.querySelector('[data-card-title]')!.closest('summary')!;
    expect(summary.className).toMatch(/flex-wrap/);
    // The title unit is a flex container (icon/dot alignment) and stays un-truncated itself:
    // `text-overflow: ellipsis` only renders in a block/inline formatting context, so `truncate`
    // has to sit on the inner, non-flex text run instead — see `data-card-text` below.
    const title = container.querySelector('[data-card-title]')!;
    expect(title.className).toMatch(/min-w-0/);
    expect(title.className).not.toMatch(/truncate/);
    expect(title.getAttribute('title')).toBe('dimensionality_reduction : dimensionality_reduction');
    const text = container.querySelector('[data-card-text]')!;
    expect(text.className).toMatch(/truncate/);
    expect(text.className).not.toMatch(/flex/);
    expect(container.querySelector('[data-card-actions]')!.className).toMatch(/shrink-0/);
  });
});
