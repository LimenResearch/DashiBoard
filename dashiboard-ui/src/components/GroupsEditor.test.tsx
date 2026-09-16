import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, fireEvent, waitFor } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { GroupsEditor } from './GroupsEditor';
import { importCards, exportCards, emptyCards, addGroup, setGroup } from '../stores';
import type { Defs } from '../ir';
import payload from '../fixtures/card-ir.json';

// Confirm now asks the probe (Task 6), so every test that clicks it makes a request — mocked the
// same way `processing.test.tsx` mocks it, so the two files don't disagree about the shape of a
// probe reply.
const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  loadJSON: vi.fn(), downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
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
});

describe('GroupsEditor', () => {
  it('says the document defines none, rather than showing an empty area', async () => {
    const { container } = mount();
    expect(container.textContent).toContain('No groups defined');
  });

  it('adds a group, which is what makes the groups tab in every picker non-empty', async () => {
    const { getByText, container } = mount();
    fireEvent.click(getByText('Add group'));
    await flush();
    expect(nameFields(container).map((f) => f.value)).toEqual(['group']);
    expect(exportCards().groups).toEqual({ group: [] });
  });

  it('edits a group with the same picker a card field uses', async () => {
    addGroup('weather');
    const { container } = mount();
    await flush();
    // The picker asks direct-or-through rather than assuming, so selecting is two steps.
    const row = container.querySelector('[data-value="TEMP"]')!;
    fireEvent.click(row.querySelector('[role=switch]')!);
    await flush();
    fireEvent.click(container.querySelector('[data-value="TEMP"] [data-specify="direct"]')!);
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

  it('folds to one line naming the group, so six groups read as six lines', async () => {
    addGroup('weather');
    const { container } = mount();
    await flush();
    const details = container.querySelector('details') as HTMLDetailsElement;
    expect(details.open).toBe(false);
    expect(details.querySelector('summary')!.textContent).toContain('name');
    expect(details.querySelector('summary')!.textContent).toContain('weather');
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

  it('offers Confirm before Remove on a group too', async () => {
    addGroup('weather');
    const { container } = mount();
    await flush();
    const actions = [...container.querySelectorAll('summary button')].map((b) => b.textContent);
    expect(actions).toEqual(['Confirm', 'Remove']);
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
    // Folded, the dot is the only thing on screen, so it has to carry the warning.
    expect(container.querySelector('[data-state="incomplete"]')).not.toBeNull();
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
    //
    // A name of its own, not `weather`: `confirmations` is a module-level signal (persisted, but
    // read from `sessionStorage` only once, at import) and so outlives any one test in this file —
    // an earlier test already confirms `group:weather` at this exact signature, and reusing it
    // would make the "confirmed" check below true before this test's own Confirm click ever
    // resolves, racing the assertion against the pending probe instead of testing against it.
    addGroup('clouds');
    setGroup('clouds', [{ cols: 'TEMP' }]);
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(container.querySelector('[aria-label="confirmed"]')).not.toBeNull());
    setGroup('clouds', [{ cols: 'PRES' }]);
    await flush();
    expect(container.querySelector('[aria-label="confirmed"]')).toBeNull();
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
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline'
        ? { valid: false, kind: 'pipeline', cols: [], nodes: [], errors: ['group `g` has no columns'],
            issues: [{ pointer: '/groups/g', reason: 'empty', severity: 'error', found: null, allowed: null, missing: [], related: [], message: 'group `g` has no columns' }] }
        : []));
    importCards({ nodes: [], groups: { g: [] } });
    const { container, getAllByText } = render(() => <GroupsEditor defs={defs} />);
    fireEvent.click(getAllByText('Confirm')[0]);
    await waitFor(() => expect(container.textContent).toMatch(/has no columns/));
    expect(postRequest.mock.calls.some((c) => c[0] === 'probe-pipeline')).toBe(true);
  });
});

describe('a group cannot name itself', () => {
  it('leaves its own name out of its groups tab', async () => {
    // Measured server-side: a self-referencing group is rejected as a graph loop. So it is not
    // a choice to validate after the fact — it is not a choice.
    addGroup('weather'); // the fixture's `group` vocabulary is exactly ["weather"]
    const { container } = render(() => <GroupsEditor defs={defs} />);
    await flush();
    const tab = [...container.querySelectorAll('[role=tab]')].find(
      (t) => t.getAttribute('data-tab') === 'groups',
    )!;
    fireEvent.click(tab);
    await flush();
    // Its own name is not in the vocabulary it is offered, so the tab has nothing to list.
    expect(container.querySelectorAll('[data-value]')).toHaveLength(0);
    expect(container.textContent).toContain('none defined');
  });
});
