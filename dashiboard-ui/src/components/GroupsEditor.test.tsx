import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, fireEvent, waitFor } from '@solidjs/testing-library';
import { flush, reconcile } from 'solid-js';
import { GroupsEditor } from './GroupsEditor';
import {
  importCards, exportCards, emptyCards, addGroup, removeGroup, setGroup, forgetAllVerdicts,
  isConfirmed, PROBE_STORE, emptyProbe, rejectFromIssues, confirmDefinition, recordVerdict, documentVerdict,
} from '../stores';
import type { Defs } from '../ir';
import payload from '../fixtures/card-ir.json';

// Confirm now asks the probe (Task 6), so every test that clicks it makes a request — mocked the
// same way `processing.test.tsx` mocks it, so the two files don't disagree about the shape of a
// probe reply.
const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
}));

const defs = payload.defs as Defs;
const mount = () => render(() => <GroupsEditor defs={defs} />);
const nameFields = (c: HTMLElement) =>
  [...c.querySelectorAll('input[aria-label="group name"]')] as HTMLInputElement[];

afterEach(cleanup);
beforeEach(() => {
  // A clean probe by default — most of this file's tests never open the network tab, so a reply
  // with no issues lets Confirm succeed exactly as it did when `checkGroup` decided that locally.
  postRequest.mockReset();
  postRequest.mockImplementation(() => Promise.resolve([]));
  importCards(emptyCards());
  // The verdicts (`stores.ts`) are a module-level signal that reads `sessionStorage` once, at
  // import — so they outlive every test in this file no matter what `importCards` resets, and a
  // name two tests both confirm would let the second inherit the first's mark before its own
  // Confirm ever runs. `PROBE_STORE` is a module-level store too: a test that seeds it (a failed
  // run's issues, say) must not leak that into the next test's render.
  forgetAllVerdicts();
  PROBE_STORE[1](reconcile(emptyProbe()));
});

describe('GroupsEditor', () => {
  it('says the document defines none, rather than showing an empty area', async () => {
    const { container } = mount();
    expect(container.textContent).toContain('No groups defined');
  });


  it('edits a group with the same picker a card field uses', async () => {
    addGroup('weather');
    const { container } = mount();
    await flush();
    // The picker asks direct-or-through rather than assuming, so selecting is two steps.
    fireEvent.click(container.querySelector('[role=tab][data-tab="cols"]')!);
    await flush();
    fireEvent.click(container.querySelector('[data-value="TEMP"] [data-name]')!);
    await flush();
    expect(exportCards().groups.weather).toEqual([{ cols: 'TEMP' }]);
  });

  it('renames a group, carrying its selectors with it', async () => {
    addGroup('g');
    setGroup('g', [{ cols: 'TEMP' }]);
    const { container } = mount();
    await flush();
    const field = nameFields(container)[0];
    field.value = 'weather';
    fireEvent.change(field);
    await flush();
    expect(exportCards().groups).toEqual({ weather: [{ cols: 'TEMP' }] });
  });

  it('refuses a rename onto an existing group, and puts the old name back', async () => {
    // Silently merging would discard one group's selectors, and the field would keep showing the
    // name the user typed — so the document and the screen would disagree.
    addGroup('a');
    setGroup('a', [{ cols: 'TEMP' }]);
    addGroup('b');
    const { container } = mount();
    await flush();
    const field = nameFields(container)[1];
    field.value = 'a';
    fireEvent.change(field);
    await flush();
    expect(Object.keys(exportCards().groups)).toEqual(['a', 'b']);
    expect(exportCards().groups.a).toEqual([{ cols: 'TEMP' }]);
    expect(nameFields(container)[1].value).toBe('b'); // reverted on screen too
    expect(container.textContent).toMatch(/already/i);
  });

  // The refusal used to be one banner above the whole list, which scrolls away from the group
  // being renamed and does not say which group it is about. It is read where it was caused, as a
  // card's is (owner, 2026-09-17).
  const refuse = async (container: HTMLElement, at: number, text: string) => {
    const field = nameFields(container)[at];
    field.value = text;
    fireEvent.change(field);
    await flush();
  };

  it('says why inside the group that was refused', async () => {
    addGroup('a');
    addGroup('b');
    const { container } = mount();
    await flush();
    await refuse(container, 1, 'a');
    const said = container.querySelectorAll('[data-name-error]');
    expect(said.length).toBe(1);
    expect(said[0].textContent).toContain('"a"');
    expect(said[0].closest('details')).toBe(nameFields(container)[1].closest('details'));
  });

  it('stacks the refusal with the group\'s other banners, under the line that holds the name', async () => {
    // Seen in a browser, 2026-09-17: the refusal sat under the field while "group `b` has no
    // columns" sat above it — two red banners with the field between them, reading as two
    // different kinds of thing. One stack, above the field.
    addGroup('a');
    addGroup('b');
    recordVerdict('group:b', [], 'rejected', [{ message: 'group `b` has no columns' }]);
    const { container } = mount();
    await flush();
    await refuse(container, 1, 'a');
    const group = nameFields(container)[1].closest('details')!;
    const finding = group.querySelector('[data-finding]')!;
    const said = group.querySelector('[data-name-error]')!;
    expect(finding.nextElementSibling).toBe(said);
    expect(nameFields(container)[1].closest('summary')).not.toBeNull();   // the name is in the line above them
  });

  it('says a group needs a name inside that group too', async () => {
    addGroup('a');
    addGroup('b');
    const { container } = mount();
    await flush();
    await refuse(container, 0, '');
    const said = container.querySelectorAll('[data-name-error]');
    expect(said.length).toBe(1);
    expect(said[0].textContent).toMatch(/needs a name/i);
    expect(said[0].closest('details')).toBe(nameFields(container)[0].closest('details'));
  });

  it('stops saying so once the group takes a free name', async () => {
    addGroup('a');
    addGroup('b');
    const { container } = mount();
    await flush();
    await refuse(container, 1, 'a');
    await refuse(container, 1, 'c');
    expect(Object.keys(exportCards().groups)).toEqual(['a', 'c']);
    expect(container.querySelector('[data-name-error]')).toBeNull();
    expect(container.textContent).not.toMatch(/already/i);
  });

  it('stops saying so when the group settles on the name it already has', async () => {
    // A new name rebuilds the row (the list is keyed by name), which takes the message with it.
    // Keeping the name does not: `renameGroup` says yes to a group's own name, the row stays, and
    // only the handler clearing the message removes it. The spaces make it a `change` at all.
    addGroup('a');
    addGroup('b');
    const { container } = mount();
    await flush();
    await refuse(container, 1, 'a');
    expect(container.querySelector('[data-name-error]')).not.toBeNull();
    await refuse(container, 1, ' b ');
    expect(Object.keys(exportCards().groups)).toEqual(['a', 'b']);
    expect(container.querySelector('[data-name-error]')).toBeNull();
  });

  it('folds to one line naming the group, so six groups read as six lines', async () => {
    addGroup('weather');
    const { container } = mount();
    await flush();
    const details = container.querySelector('details') as HTMLDetailsElement;
    expect(details.open).toBe(false);
    expect(details.querySelector('summary')!.textContent).toContain('Group');
    expect((details.querySelector('summary input') as HTMLInputElement).value).toBe('weather');
  });

  it('removes from the folded line without expanding it on the way out', async () => {
    // A click inside `<summary>` toggles the disclosure unless the handler says it handled the
    // event. Without that, deleting a group opens it first — briefly, and then it is gone.
    addGroup('weather');
    addGroup('other');
    const { getAllByText } = mount();
    await flush();
    fireEvent.click(getAllByText('Remove')[0]);
    await flush();
    expect(Object.keys(exportCards().groups)).toEqual(['other']);
    // The guard itself is pinned in Disclosure.test.tsx, where the element survives the click and
    // its open state can actually be observed. Asserting it here checked the *surviving* group,
    // which was never clicked — vacuously true, and it let a mutation through.
  });

  it('offers Confirm before Remove on a group too, at its foot and on screen when folded', async () => {
    addGroup('weather');
    const { container } = mount();
    await flush();
    const actions = container.querySelector('[data-group-actions]')!;
    expect([...actions.querySelectorAll('button')].map((b) => b.textContent)).toEqual(['Confirm', 'Clear', 'Remove']);
    // Under everything the group shows, so a keyboard user reaches them after the last field
    // rather than walking back to the top; outside what folds, so they never disappear.
    expect(actions.closest('details')).toBeNull();
    expect(actions.parentElement!.lastElementChild).toBe(actions);
    expect(actions.compareDocumentPosition(container.querySelector('[data-entry]')!) & Node.DOCUMENT_POSITION_PRECEDING).toBeTruthy();
  });

  it('refuses to confirm an empty group, and says what to do', async () => {
    // Legal server-side — `weather = []` constructs — so this is the server's to say now (Task 6):
    // Confirm asks the probe and the empty-group finding comes back exactly as
    // `empty_group_issues` phrases it, rather than as `checkGroup`'s own wording.
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline'
        ? { valid: false, kind: 'pipeline', cols: [], nodes: [], errors: ['group `weather` has no columns'],
            issues: [{ pointer: '/groups/weather', reason: 'empty', severity: 'error', found: null, allowed: null, missing: [], related: [], message: 'group `weather` has no columns' }] }
        : []));
    addGroup('weather');
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(container.textContent).toMatch(/no columns/i));
    expect(container.querySelector('[aria-label="confirmed"]')).toBeNull();
    // Folded, the dot is the only thing on screen, so it has to carry the answer.
    expect(container.querySelector('[data-state="rejected"]')).not.toBeNull();
  });

  it('confirms a group that selects something, and shows it on the folded line', async () => {
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(container.querySelector('[aria-label="confirmed"]')).not.toBeNull());
  });

  it('un-confirms itself when the group is edited afterwards', async () => {
    // The signature changes, so the confirmation stops matching. A flag would have gone stale and
    // claimed the author had finished something they then changed.
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(container.querySelector('[aria-label="confirmed"]')).not.toBeNull());
    setGroup('weather', [{ cols: 'PRES' }]);
    await flush();
    expect(container.querySelector('[aria-label="confirmed"]')).toBeNull();
  });

  it('confirms what was probed, not what the group became while the probe was in flight', async () => {
    // A deferred reply, held open on purpose: the request is a round trip, and an edit landing in
    // that window is a real possibility, not a contrived one. `state.groups[name]` read once the
    // probe answers would capture the *edited* content and confirm a group nobody asked to probe.
    let resolveProbe!: (value: unknown) => void;
    const pending = new Promise((resolve) => { resolveProbe = resolve; });
    postRequest.mockImplementation((page: string) =>
      page === 'probe-pipeline' ? pending : Promise.resolve([]));
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    const { getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await flush();
    // Edited while the request is still in flight — before the probe has answered anything.
    setGroup('weather', []);
    await flush();
    resolveProbe({ valid: true, kind: 'pipeline', cols: [], nodes: [], errors: [], issues: [] });
    // Three, not two: `confirmDefinition` is a functional updater now (it chains off the previous
    // updater's return rather than off a read — see `stores.ts`), and that costs one more `flush()`
    // to settle than a plain value set did, on top of `askProbe`'s own async unwrap. Real usage
    // notices nothing — Solid schedules its own flush automatically; only a test driving the
    // scheduler by hand has to ask for the extra tick.
    await flush();
    await flush();
    await flush();
    // Confirmed against what was actually sent to the probe...
    expect(isConfirmed('group:weather', [{ cols: 'TEMP' }])).toBe(true);
    // ...not against what the group turned into before the answer came back.
    expect(isConfirmed('group:weather', exportCards().groups.weather)).toBe(false);
  });

  it('removes a group', async () => {
    addGroup('a');
    const { getByText } = mount();
    await flush();
    fireEvent.click(getByText('Remove'));
    await flush();
    expect(exportCards().groups).toEqual({});
  });

  it('shows the server\'s finding for an empty group after Confirm', async () => {
    // The envelope verbatim, with no `nodes` key: the empty-group early return is
    // `(; valid = false, kind, cols, errors, issues)`. Mocking `nodes: []` here — a key the
    // server never sends on a failure — is how `usableProbe` discarding these replies survived
    // every UI test (final review, 2026-09-16).
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline'
        ? { valid: false, kind: 'pipeline', cols: [], errors: ['group `g` has no columns'],
            issues: [{ pointer: '/groups/g', reason: 'empty', severity: 'error', found: null, allowed: null, missing: [], related: [], message: 'group `g` has no columns' }] }
        : []));
    importCards({ nodes: [], groups: { g: [] } });
    const { container, getAllByText } = render(() => <GroupsEditor defs={defs} />);
    fireEvent.click(getAllByText('Confirm')[0]);
    await waitFor(() => expect(container.textContent).toMatch(/has no columns/));
    expect(postRequest.mock.calls.some((c) => c[0] === 'probe-pipeline')).toBe(true);
  });

  it('reads a failed probe as "could not check", never as a clean group', async () => {
    // `postRequest` resolves to `null` on any failure (item 1) — including a proxy route that
    // doesn't exist, which is exactly how this went unnoticed in the browser. Confirm must not
    // read that silence as "no issues found".
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline' ? null : []));
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(container.textContent).toMatch(/could not reach/i));
    expect(isConfirmed('group:weather', exportCards().groups.weather)).toBe(false);
    expect(container.querySelector('[data-state="rejected"]')).not.toBeNull();
  });

  it('shows one finding, not the failed run\'s copy and Confirm\'s copy both', async () => {
    // A run can fail on this group before Confirm is ever clicked (`rejectFromIssues`), which
    // records a rejected verdict here. Confirm then asks the same question itself and gets the
    // identical answer back — one verdict replaces the other, it does not stack.
    const issue = {
      pointer: '/groups/g', reason: 'empty', severity: 'error' as const, found: null,
      allowed: null, missing: [], related: [], message: 'group `g` has no columns',
    };
    // Confirm's reply is worded differently from the run's, so the assertion below can tell
    // "replaced" from "the reply has not landed yet".
    const reworded = { ...issue, message: 'group `g` selects nothing' };
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline'
        ? { valid: false, kind: 'pipeline', cols: [], nodes: [], errors: [reworded.message], issues: [reworded] }
        : []));
    importCards({ nodes: [], groups: { g: [] } });
    await flush(); // a verdict binds to the document as it is *after* the staged write lands
    rejectFromIssues([issue]);
    const { container, getAllByText } = render(() => <GroupsEditor defs={defs} />);
    expect(container.textContent.split('has no columns').length - 1).toBe(1);
    fireEvent.click(getAllByText('Confirm')[0]);
    await waitFor(() => expect(container.textContent).toMatch(/selects nothing/));
    expect(container.querySelector('[data-state="rejected"]')).not.toBeNull();
    expect(container.textContent).not.toMatch(/has no columns/);
    expect(container.querySelectorAll('[data-finding]')).toHaveLength(1);
  });
  it('a failed run rejects the group, even over an existing confirmation', async () => {
    // A Run is the author asking, exactly like Confirm: its answer replaces the older mark.
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    confirmDefinition('group:weather', [{ cols: 'TEMP' }]);
    await flush(); // the run's verdict binds to the group as it is once the staged writes land
    rejectFromIssues([{
      pointer: '/groups/weather', reason: 'empty', severity: 'error', found: null,
      allowed: null, missing: [], related: [], message: 'group `weather` has no columns',
    }]);
    const { container } = mount();
    await flush();
    expect(container.querySelector('[data-state="rejected"]')).not.toBeNull();
    expect(container.textContent).toMatch(/has no columns/);
  });

  it('shows no red before Confirm, even while the probe reports an error for it', async () => {
    // Decided 2026-09-17: red is reserved for "you asked, and it was wrong". The continuous probe
    // writes to `PROBE_STORE` only — never a verdict — so its error paints nothing on the group.
    importCards({ nodes: [], groups: { g: [] } });
    PROBE_STORE[1]((d) => {
      d.valid = false;
      d.issues = [{ pointer: '/groups/g', reason: 'empty', severity: 'error', found: null, allowed: null, missing: [], related: [], message: 'group `g` has no columns' }];
    });
    await flush();
    const { container } = mount();
    await flush();
    expect(container.querySelector('[data-state]')!.getAttribute('data-state')).toBe('unconfirmed');
    expect(container.querySelector('[data-state]')!.className).toMatch(/bg-warning/);
    expect(container.textContent).not.toMatch(/has no columns/);
  });

  it('turns red with the finding on Confirm, amber on edit, green when fixed', async () => {
    const EMPTY = { valid: false, kind: 'pipeline', cols: [], errors: ['group `g` has no columns'],
      issues: [{ pointer: '/groups/g', reason: 'empty', severity: 'error', found: null, allowed: null, missing: [], related: [], message: 'group `g` has no columns' }] };
    importCards({ nodes: [], groups: { g: [] } });
    postRequest.mockImplementation((page: string) => Promise.resolve(page === 'probe-pipeline' ? EMPTY : []));
    const { container, getAllByText } = mount();
    fireEvent.click(getAllByText('Confirm')[0]);
    await waitFor(() => expect(container.querySelector('[data-state="rejected"]')).not.toBeNull());
    expect(container.querySelector('[data-state="rejected"]')!.className).toMatch(/bg-destructive/);
    expect(container.textContent).toMatch(/has no columns/);
    setGroup('g', [{ cols: 'TEMP' }]);
    await flush();
    await waitFor(() => expect(container.querySelector('[data-state="unconfirmed"]')).not.toBeNull());
    expect(container.textContent).not.toMatch(/has no columns/);
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline' ? { valid: true, cols: ['TEMP'], nodes: [], errors: [], issues: [] } : []));
    fireEvent.click(getAllByText('Confirm')[0]);
    await waitFor(() => expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull());
    expect(container.querySelector('[data-state="confirmed"]')!.className).toMatch(/bg-success/);
  });

  it('leaves a confirmed group confirmed when the live probe only warns', async () => {
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    confirmDefinition('group:weather', [{ cols: 'TEMP' }]);
    rejectFromIssues([{
      pointer: '/groups/weather', reason: 'overwrites', severity: 'warning', found: null,
      allowed: null, missing: [], related: [], message: '`TEMP_z` already exists',
    }]);
    const { container } = mount();
    await flush();
    expect(container.querySelector('[aria-label="confirmed"]')).not.toBeNull();
  });
});

describe('a group cannot name itself', () => {
  it('leaves its own name out of its groups tab', async () => {
    // Measured server-side: a self-referencing group is rejected as a graph loop. So it is not
    // a choice to validate after the fact — it is not a choice.
    addGroup('weather'); // the fixture's `group` vocabulary is exactly ["weather"]
    const { container } = render(() => <GroupsEditor defs={defs} />);
    await flush();
    // Its own name is the only group there is, and it is not on offer to itself: a kind with
    // nothing to offer has no tab at all.
    const tabs = [...container.querySelectorAll('[role=tab]')].map((t) => t.getAttribute('data-tab'));
    expect(tabs).not.toContain('groups');
    expect(tabs).toContain('cols');
  });
});

describe('Confirm on a document that cannot build', () => {
  // The same rule as a card's Confirm: a fault with no item pointer is the document's, and the
  // group that was asked carries it.
  it('leaves the group amber and records the fault on the document', async () => {
    // Revised 2026-09-18: a loop is nobody's item. It is said once, next to Run.
    const LOOP = 'The input graph contains at least one loop: a, b';
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline'
        ? { valid: false, kind: 'pipeline', cols: [], errors: [LOOP],
            issues: [{ pointer: '', reason: 'loop', severity: 'error', found: null, allowed: null,
              missing: [], related: ['/nodes/0', '/nodes/1'], message: LOOP }] }
        : []));
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(documentVerdict()).not.toBeNull());
    expect(documentVerdict()!.findings).toEqual([{ message: LOOP }]);
    expect(container.querySelector('[data-state="rejected"]')).toBeNull();
    expect(container.querySelector('[data-state="confirmed"]')).toBeNull();
    expect(container.querySelector('[data-finding]')).toBeNull();
  });

  it('confirms green when the only fault is pointed at a card', async () => {
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline'
        ? { valid: false, kind: 'pipeline', cols: [],
            errors: ['1 schema validation error:\nSchema Validation Error for card in node 1'],
            issues: [{ pointer: '/nodes/0/card', reason: 'required', severity: 'error', found: null,
              allowed: null, missing: ['method'], related: ['/nodes/0/card/method'], message: 'Schema Validation Error for card in node 1' }] }
        : []));
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull());
  });
});

describe('an answer that arrives after its group is gone', () => {
  it('is dropped: a new group of the same name is not marked for a question nobody asked of it', async () => {
    // Confirm on an empty group, the group removed while the server is still answering, a new
    // group added — which gets the same default name and the same empty content. The late
    // answer used to land on it: red, "has no columns", with no Confirm pressed (measured
    // 2026-09-17 and again 2026-09-21). Content cannot tell the two apart — `[]` is `[]` — so
    // the guard is on the removal itself. It needs a slow server to show: a remote deployment,
    // or the first seconds after a restart.
    let answer!: (v: unknown) => void;
    postRequest.mockImplementation(() => new Promise((resolve) => { answer = resolve; }));
    const name = addGroup();
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(answer).toBeDefined());
    removeGroup(name);
    await flush();
    answer({ valid: false, kind: 'pipeline', cols: [], errors: [`group \`${name}\` has no columns`],
      issues: [{ pointer: `/groups/${name}`, reason: 'empty', severity: 'error', found: null, allowed: null,
        missing: [], related: [], message: `group \`${name}\` has no columns` }] });
    await new Promise((r) => setTimeout(r, 20));
    await flush();
    expect(addGroup()).toBe(name);
    await flush();
    await new Promise((r) => setTimeout(r, 20));
    expect(container.querySelector('[data-state]')!.getAttribute('data-state')).toBe('unconfirmed');
    expect(container.querySelector('[data-finding]')).toBeNull();
  });
});

describe('clearing a group', () => {
  it('empties its selection, leaving the group and its name', async () => {
    importCards({ nodes: [], groups: { weather: [{ cols: 'TEMP' }] } });
    const { container } = mount();
    await flush();
    const actions = [...container.querySelectorAll('[data-group-actions] button')];
    expect(actions.map((b) => b.textContent)).toEqual(['Confirm', 'Clear', 'Remove']);
    expect(actions[1].className).toContain('text-warning');
    fireEvent.click(actions[1]); await flush();
    expect(exportCards().groups).toEqual({ weather: [] });
  });
});

describe('what a group is offered', () => {
  const offered = (c: HTMLElement) =>
    [...c.querySelectorAll('[data-selector] [data-panel] [data-value]')].map((e) => e.getAttribute('data-value'));

  it('leaves out what depends on the group once the server has said what', async () => {
    const rescale = { type: 'rescale', method: { type: 'zscore' }, inputs: [] };
    importCards({ nodes: [{ id: 'up', card: rescale }, { id: 'down', card: { ...rescale, inputs: [{ groups: 'g' }] } }], groups: { g: [] } });
    const withNodes = { ...defs, node: { ...defs.node, enum: ['up', 'down'] } } as Defs;
    const { container } = render(() => <GroupsEditor defs={withNodes} />);
    await flush();
    expect(offered(container)).toEqual(['up', 'down']);
    PROBE_STORE[1]((d) => { d.referable = { nodes: [], groups: { g: { nodes: ['up'], groups: [] } } }; });
    await flush();
    expect(offered(container)).toEqual(['up']);
  });
});

describe('a group, as it is laid out', () => {
  it('is named in its own line, with no second name field', async () => {
    addGroup('weather');
    const { container } = mount();
    await flush();
    const field = nameFields(container)[0];
    expect(field.closest('summary')).not.toBeNull();
    expect([...container.querySelectorAll('label')].map((l) => l.textContent)).not.toContain('name');
  });

  it('keeps the chips and the text box on screen when folded; its one fold control opens the panel', async () => {
    addGroup('weather');
    const { container } = mount();
    await flush();
    const group = container.querySelector('details')!;
    expect(group.open).toBe(false);
    const entry = container.querySelector('[data-entry]')!;
    expect(entry.closest('details')).toBeNull();                 // not inside what folds
    expect(container.querySelector('[data-selector-name]')!.textContent).toBe('selection*');
    expect(container.querySelector('[data-fold]')).toBeNull();
    expect((container.querySelector('[data-panel]') as HTMLElement).hidden).toBe(true);
    group.open = true; fireEvent(group, new Event('toggle')); await flush();
    expect((container.querySelector('[data-panel]') as HTMLElement).hidden).toBe(false);
  });
});
