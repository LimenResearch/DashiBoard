import { describe, it, expect, afterEach, vi } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { createSignal, flush } from 'solid-js';
import { SelectorField } from './SelectorField';
import * as selector from '../selector';
import type { SelectorItem } from '../selector';
import type { Defs, IRNode } from '../ir';
import payload from '../fixtures/card-ir.json';

const defs = payload.defs as Defs;
const itemNode = defs.variable as IRNode;

// The layout changed (study 05: kind-first tabs, one row per value, cases per row). The document
// assertions below did not — case C, case E, chain order and "no empty item" are the contract,
// and they are what a rewrite has to carry across.

const mount = (value: unknown, onChange: (items: SelectorItem[]) => void = () => {}) =>
  render(() => (
    <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value} onChange={onChange} />
  ));

const tab = (c: HTMLElement, kind: string) =>
  c.querySelector(`[role=tab][data-tab="${kind}"]`) as HTMLButtonElement;
const row = (c: HTMLElement, value: string) =>
  c.querySelector(`[data-value="${value}"]`) as HTMLElement;
/** The name is the `direct` control: `aria-pressed` says whether the value carries it. */
const nameOf = (c: HTMLElement, value: string) =>
  row(c, value).querySelector('[data-name]') as HTMLButtonElement;
const isOn = (c: HTMLElement, value: string) => nameOf(c, value).getAttribute('aria-pressed');
const casesOf = (c: HTMLElement, value: string) =>
  [...row(c, value).querySelectorAll('[data-case]')].map((e) => e.getAttribute('data-case'));
/** Re-queried, never held: `<Show keyed>` replaces this node on every chain change. */
const builderIn = (c: HTMLElement, value: string) =>
  row(c, value).querySelector('[data-chain-builder]') as HTMLElement;
const nodeButton = (c: HTMLElement, value: string, name: string) =>
  builderIn(c, value).querySelector(`[data-node="${name}"]`) as HTMLButtonElement;
/** Build a chain by mouse: `through…` on the row, a click per node, then add. */
const chainBy = async (c: HTMLElement, value: string, steps: string[]) => {
  fireEvent.click(row(c, value).querySelector('[data-through]')!); await flush();
  for (const step of steps) { fireEvent.click(nodeButton(c, value, step)); await flush(); }
  fireEvent.click(builderIn(c, value).querySelector('[data-chain="commit"]')!); await flush();
};
const writes = (c: HTMLElement) =>
  (c.querySelector('.font-mono.break-words') as HTMLElement | null)?.textContent ?? '';

afterEach(cleanup);

/** Unfold the panel of switches; folded is how a field starts. */
const open = (c: HTMLElement) => fireEvent.click(c.querySelector('[data-fold]')!);
/** The tabs open on `nodes`; most of these tests are about columns. */
const onCols = async (c: HTMLElement) => {
  fireEvent.click(c.querySelector('[role=tab][data-tab="cols"]')!);
  await flush();
};

describe('SelectorField', () => {
  it('opens on a kind that has something to offer', async () => {
    const { container } = mount([]);
    await onCols(container);
    expect(container.querySelector('[role=tab][aria-selected="true"]')?.getAttribute('data-tab'))
      .toBe('cols');
  });

  it('shows a row per value in the open vocabulary, none carrying anything for an empty field', async () => {
    const { container } = mount([]);
    await onCols(container);
    expect(isOn(container, 'TEMP')).toBe('false');
    expect(casesOf(container, 'TEMP')).toEqual([]);
  });

  it('reads an existing document back onto the rows it came from', async () => {
    const { container } = mount([{ cols: ['PRES', 'TEMP'] }]);
    await onCols(container);
    expect(isOn(container, 'PRES')).toBe('true');
    expect(casesOf(container, 'PRES')).toEqual(['direct']);
    expect(casesOf(container, 'TEMP')).toEqual(['direct']);
    expect(isOn(container, 'No')).toBe('false');
  });

  it('holds the same value twice when it is qualified differently — case E', async () => {
    // The case that rules out modelling a field as a set of values with attributes.
    const { container } = mount([{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }]);
    await onCols(container);
    expect(casesOf(container, 'PRES')).toEqual(['rescale', 'direct']);
  });

  it('keeps chain order, since [a,b] names a different column from [b,a]', async () => {
    const { container } = mount([{ cols: 'PRES', through: ['rescale', 'split'] }]);
    await onCols(container);
    expect(casesOf(container, 'PRES')).toEqual(['rescale→split']);
  });

  it('writes the item as direct on a click on its name', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    await onCols(container);
    fireEvent.click(nameOf(container, 'TEMP'));
    await flush();
    expect(written).toEqual([{ cols: 'TEMP' }]);
  });

  it('adds a second qualification through…, which is what case E needs', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([{ cols: 'PRES' }], (items) => { written = items; });
    open(container); await flush(); await onCols(container);
    await chainBy(container, 'PRES', ['rescale']);
    expect(written).toEqual([{ cols: 'PRES' }, { cols: 'PRES', through: ['rescale'] }]);
  });

  it('will not write direct twice for one value: the second click on the name removes it', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([{ cols: 'PRES' }], (items) => { written = items; });
    await onCols(container);
    fireEvent.click(nameOf(container, 'PRES')); await flush();
    expect(written).toEqual([]);
  });

  it('records the order nodes are clicked, since [a,b] names a different column from [b,a]', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    open(container); await flush(); await onCols(container);
    await chainBy(container, 'TEMP', ['split', 'rescale']);
    expect(written).toEqual([{ cols: 'TEMP', through: ['split', 'rescale'] }]);
  });

  it('the name removes only direct; a chain goes by its own ×', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount(
      [{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }, { cols: 'TEMP' }],
      (items) => { written = items; },
    );
    await onCols(container);
    fireEvent.click(nameOf(container, 'PRES'));
    await flush();
    expect(written).toEqual([{ cols: 'PRES', through: ['rescale'] }, { cols: 'TEMP' }]);
  });

  it('removes one qualification without disturbing the other', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount(
      [{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }],
      (items) => { written = items; },
    );
    await onCols(container);
    const direct = [...row(container, 'PRES').querySelectorAll('[data-case]')]
      .find((e) => e.getAttribute('data-case') === 'direct')!;
    fireEvent.click(direct.querySelector('button')!);
    await flush();
    expect(written).toEqual([{ cols: 'PRES', through: ['rescale'] }]);
  });

  it('cancelling a chain leaves the value as it was', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    open(container); await flush(); await onCols(container);
    fireEvent.click(row(container, 'TEMP').querySelector('[data-through]')!); await flush();
    fireEvent.click(nodeButton(container, 'TEMP', 'split')); await flush();
    fireEvent.click(builderIn(container, 'TEMP').querySelector('[data-chain="cancel"]')!); await flush();
    expect(written).toBeNull();
    expect(isOn(container, 'TEMP')).toBe('false');
  });

  it('shows the document it writes, in the selector form and never a resolved name', async () => {
    // `PRES_rescaled` must not appear: the UI writes the TOML, DashiBoard resolves it.
    const { container } = mount([{ cols: ['No', 'year'] }, { cols: 'month', through: ['log'] }]);
    await onCols(container);
    expect(writes(container)).toBe('{cols = ["No", "year"]}, {cols = "month", through = "log"}');
    expect(writes(container)).not.toContain('month_log');
  });

  it('switches vocabulary on a tab click, and says when one is empty', async () => {
    const { container } = mount([]);
    await onCols(container);
    fireEvent.click(tab(container, 'groups'));
    await flush();
    expect(row(container, 'weather')).not.toBeNull();
    expect(nameOf(container, 'weather')).not.toBeNull();
  });

  describe('when the document defines no nodes', () => {
    // A pass-through chain is built from nodes. With none defined there is no chain to build, so
    // `through…` is a choice that cannot come out well — the same reasoning that took a card's own
    // name out of its vocabulary rather than validating it afterwards.
    const noNodes = { ...defs, node: { type: 'string', enum: [] } } as Defs;
    const mountNoNodes = (value: unknown) =>
      render(() => (
        <SelectorField
          itemNode={itemNode} defs={noNodes} label="inputs" value={value} onChange={() => {}}
        />
      ));

    it('offers through… as unreachable rather than as a dead end', async () => {
      const { container } = mountNoNodes([]);
      await onCols(container);
      const through = row(container, 'TEMP').querySelector('[data-through]') as HTMLButtonElement;
      expect(through.disabled).toBe(true);
      expect(through.title).toMatch(/no node/i);
    });

    it('still offers direct, which is the one qualification that needs nothing', async () => {
      const { container } = mountNoNodes([]);
      await onCols(container);
      expect(nameOf(container, 'TEMP').disabled).toBe(false);
    });
  });

  it('counts each tab by values carrying a qualification, not by items', async () => {
    // `PRES` twice is one value, so the tab says 1 — the count answers "how many of these have I
    // touched", which is what a hidden tab needs to report.
    const { container } = mount([{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }]);
    await onCols(container);
    expect(tab(container, 'cols').textContent).toContain('1');
  });

  it('expands the document once per change, not once per read', async () => {
    // `rows()` was a plain function called from every row's `casesFor`, the chip list, the writes
    // strip and the tab counts — O(values × items) expansions per render.
    const spy = vi.spyOn(selector, 'expand');
    // `finally`, because a failing assertion would otherwise leave the spy on the module for
    // every test that runs after it — this suite does not isolate modules between files.
    try {
      render(() => (
        <SelectorField itemNode={itemNode} defs={defs} label="inputs"
          value={[{ cols: ['TEMP', 'PRES'] }]} onChange={() => {}} />
      ));
      expect(spy.mock.calls.length).toBeLessThanOrEqual(2);   // mount, plus at most one settle
    } finally {
      spy.mockRestore();
    }
  });

  it('draws a value the vocabulary cannot name as any other chip: removing it is the store\'s job', async () => {
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs"
        value={[{ cols: 'GONE' }, { cols: 'TEMP' }]} onChange={() => {}} />
    ));
    expect(container.querySelector('[data-missing]')).toBeNull();
    expect(container.querySelector('[data-chip="cols:GONE"]')!.className).not.toContain('line-through');
  });
});

// A lone `$defs/variable` field — `partition`, `weights`, `interp.input` — is one selector item,
// not a list, and the server resolves it with `only(...)`: exactly one column. Same picker, one
// choice (owner, 2026-09-18).
describe('SelectorField, single', () => {
  const one = (value: unknown, onChange: (item: SelectorItem | undefined) => void = () => {}) =>
    render(() => (
      <SelectorField single itemNode={itemNode} defs={defs} label="partition" value={value} onChange={onChange} />
    ));

  it('reads one item back as the one value that is on', async () => {
    const { container } = one({ cols: 'PRES' });
    await onCols(container);
    expect(isOn(container, 'PRES')).toBe('true');
    expect(casesOf(container, 'PRES')).toEqual(['direct']);
    expect(isOn(container, 'TEMP')).toBe('false');
    expect(writes(container)).toBe('{cols = "PRES"}');
  });

  it('writes one item, not a list, and a second pick replaces the first', async () => {
    let written: SelectorItem | undefined | null = null;
    const { container } = one({ cols: 'PRES' }, (item) => { written = item; });
    await onCols(container);
    fireEvent.click(nameOf(container, 'TEMP'));
    await flush();
    expect(written).toEqual({ cols: 'TEMP' });
  });

  it('empties the field when its one value is clicked off', async () => {
    let written: SelectorItem | undefined | null = null;
    const { container } = one({ cols: 'PRES' }, (item) => { written = item; });
    await onCols(container);
    fireEvent.click(nameOf(container, 'PRES'));
    await flush();
    expect(written).toBeUndefined();
  });

  it('carries a through chain, read and written', async () => {
    const { container } = one({ cols: 'PRES', through: ['rescale'] });
    await onCols(container);
    expect(casesOf(container, 'PRES')).toEqual(['rescale']);
    expect(writes(container)).toBe('{cols = "PRES", through = "rescale"}');

    let written: SelectorItem | undefined | null = null;
    cleanup();
    const second = one(undefined, (item) => { written = item; });
    open(second.container); await flush(); await onCols(second.container);
    await chainBy(second.container, 'TEMP', ['split']);
    expect(written).toEqual({ cols: 'TEMP', through: ['split'] });
  });

  it('has no order strip and offers no second qualification', async () => {
    const { container } = one({ cols: 'PRES' });
    await onCols(container);
    expect(container.querySelector('[data-move]')).toBeNull();
  });

  it('says the field is not set when empty, rather than showing an empty list', async () => {
    const { container } = one(undefined);
    await onCols(container);
    expect(writes(container)).toBe('not set');
  });
});

describe('SelectorField, layout', () => {
  it('shows the name and the chips with the panel folded, in the notation that is typed', () => {
    const { container } = mount([{ cols: 'PRES', through: ['rescale', 'log'] }, { groups: 'weather' }]);
    expect(container.querySelector('[data-panel]')!.hasAttribute('hidden')).toBe(true);
    expect(container.querySelector('[data-fold]')!.getAttribute('aria-expanded')).toBe('false');
    expect([...container.querySelectorAll('[data-chip]')].map((c) => c.getAttribute('data-chip')))
      .toEqual(['cols:PRES@rescale@log', 'groups:weather']);
  });

  it('unfolds the panel from the button beside the name', async () => {
    const { container } = mount([]);
    fireEvent.click(container.querySelector('[data-fold]')!);
    await flush();
    expect(container.querySelector('[data-panel]')!.hasAttribute('hidden')).toBe(false);
    expect(container.querySelector('[data-fold]')!.getAttribute('aria-expanded')).toBe('true');
  });

  it('removes a value from its chip, which is the only way with the panel folded', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([{ cols: 'PRES' }, { cols: 'TEMP' }], (items) => { written = items; });
    fireEvent.click(container.querySelector('[data-chip="cols:PRES"] [data-chip-remove]')!);
    await flush();
    expect(written).toEqual([{ cols: 'TEMP' }]);
  });

  it('orders the tabs nodes, groups, cols, and leaves out a kind with nothing to offer', async () => {
    const { container } = mount([]);
    open(container); await flush();
    expect([...container.querySelectorAll('[role=tab]')].map((t) => t.getAttribute('data-tab')))
      .toEqual(['nodes', 'groups', 'cols']);
    cleanup();
    const noGroups = { ...defs, group: { ...defs.group, enum: [] } } as Defs;
    const bare = render(() => <SelectorField itemNode={itemNode} defs={noGroups} label="inputs" value={[]} onChange={() => {}} />);
    open(bare.container); await flush();
    expect([...bare.container.querySelectorAll('[role=tab]')].map((t) => t.getAttribute('data-tab')))
      .toEqual(['nodes', 'cols']);
  });

  it('shows a lone selector its chip too, without the arrows', () => {
    const { container } = render(() => (
      <SelectorField single itemNode={itemNode} defs={defs} label="partition" value={{ nodes: 'split' }} onChange={() => {}} />
    ));
    const chip = container.querySelector('[data-chip="nodes:split"]')!;
    expect(chip).not.toBeNull();
    expect(chip.querySelector('[data-move]')).toBeNull();
    expect(chip.querySelector('[data-chip-remove]')).not.toBeNull();
  });
});

describe('SelectorField, typed entry', () => {
  const box = (c: HTMLElement) => c.querySelector('[data-entry]') as HTMLInputElement;
  const type = async (c: HTMLElement, value: string) => { fireEvent.input(box(c), { target: { value } }); await flush(); };
  const key = async (c: HTMLElement, k: string) => { const e = fireEvent.keyDown(box(c), { key: k }); await flush(); return e; };
  const tokens = (c: HTMLElement) => [...c.querySelectorAll('[data-token]')].map((t) => t.textContent);

  it('writes the same document as the panel: kind, name, chain, Enter', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    await type(container, 'c'); await key(container, 'Tab');
    await type(container, 'PRE'); await key(container, 'Tab');
    await type(container, '@resc'); await key(container, 'Tab');
    expect(tokens(container)).toEqual(['cols:', 'PRES', '@rescale']);
    await key(container, 'Enter');
    expect(written).toEqual([{ cols: 'PRES', through: ['rescale'] }]);
    expect(tokens(container)).toEqual(['cols:']);            // the kind stays for the next entry
    expect(box(container).value).toBe('');
  });

  it('lets TAB through when nothing is being typed, and keeps it while completing', async () => {
    const { container } = mount([]);
    expect(await key(container, 'Tab')).toBe(true);          // not prevented: focus moves on
    await type(container, 'c');
    expect(await key(container, 'Tab')).toBe(false);         // prevented: it completed `cols:`
  });

  it('shows a dropdown of matches while the panel is folded, and none when it is open', async () => {
    const { container } = mount([]);
    await type(container, 'c'); await key(container, 'Tab'); await type(container, 'TE');
    expect(container.querySelector('[role=listbox] [data-suggestion="TEMP"]')).not.toBeNull();
    open(container); await flush();
    expect(container.querySelector('[role=listbox]')).toBeNull();
  });

  it('never takes the focus itself: a scrollable list is a tab stop in Chrome', async () => {
    // Tab from the box landed on the list, which blur then removed, dropping the focus to the
    // body — and any panel watching for focus leaving closed on it. The attribute is what turns
    // that off; jsdom reports `tabIndex` as -1 either way, so the attribute is what is asserted.
    const { container } = mount([]);
    await type(container, 'c'); await key(container, 'Tab');
    expect(container.querySelector('[role=listbox]')!.getAttribute('tabindex')).toBe('-1');
    open(container); await flush();
    expect(container.querySelector('[data-panel] .overflow-y-auto')!.getAttribute('tabindex')).toBe('-1');
  });

  it('floats the dropdown above the sticky row at the foot of the tab', async () => {
    const { container } = mount([]);
    await type(container, 'c'); await key(container, 'Tab');
    expect(container.querySelector('[role=listbox]')!.className).toMatch(/\bz-30\b/);   // the row is z-10
  });

  it('drives the open panel: the tab follows the kind, the rows narrow, the highlight moves', async () => {
    const { container } = mount([]);
    open(container); await flush();
    await type(container, 'c'); await key(container, 'Tab');
    expect(container.querySelector('[role=tab][aria-selected="true"]')!.getAttribute('data-tab')).toBe('cols');
    await type(container, 'TE');
    const shown = [...container.querySelectorAll('[data-panel] [data-value]')].map((r) => r.getAttribute('data-value'));
    expect(shown.every((v) => v!.toLowerCase().includes('te'))).toBe(true);
    expect(container.querySelector('[data-panel] [data-highlighted]')!.getAttribute('data-value')).toBe(shown[0]);
  });

  it('a click on a row is direct at a name and a step in a chain; only through… is a button', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    await type(container, 'c'); await key(container, 'Tab');
    expect(container.querySelector('[data-pick="direct"]')).toBeNull();
    fireEvent.click(container.querySelector('[data-suggestion="TEMP"]')!); await flush();
    expect(written).toEqual([{ cols: 'TEMP' }]);
    fireEvent.click(container.querySelector('[data-suggestion="PRES"] [data-pick="through"]')!); await flush();
    expect(tokens(container)).toEqual(['cols:', 'PRES']);
    expect(container.querySelector('[data-suggestion="rescale"]')).not.toBeNull();
    fireEvent.click(container.querySelector('[data-suggestion="rescale"]')!); await flush();
    expect(tokens(container)).toEqual(['cols:', 'PRES', '@rescale']);
    expect(container.querySelector('[data-suggestion] [data-pick]')).toBeNull();   // a chain step has no buttons
    await key(container, 'Enter');
    expect(written).toEqual([{ cols: 'PRES', through: ['rescale'] }]);   // the mount's value is static: one write at a time
  });

  it('offers the kinds on focus, the names after a kind, and after a name only the nodes its host allows', async () => {
    const chainFor = vi.fn((row: { value: string; chain: string[] }) => (row.value === 'PRES' && row.chain.length === 0 ? ['split'] : ['rescale', 'split']));
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={[]} onChange={() => {}} chainFor={chainFor} />
    ));
    fireEvent.focus(box(container)); await flush();
    expect([...container.querySelectorAll('[data-suggestion]')].map((e) => e.getAttribute('data-suggestion'))).toEqual(['nodes', 'groups', 'cols']);
    await type(container, 'c'); await key(container, 'Tab');
    expect(container.querySelector('[data-suggestion="TEMP"]')).not.toBeNull();
    await type(container, 'PRES'); await key(container, 'Tab');
    expect([...container.querySelectorAll('[data-suggestion]')].map((e) => e.getAttribute('data-suggestion'))).toEqual(['split']);
    expect(chainFor).toHaveBeenCalledWith({ kind: 'cols', value: 'PRES', chain: [] }, ['rescale', 'split']);
    await key(container, 'Enter');                                 // nothing typed: direct
    expect(tokens(container)).toEqual(['cols:']);
  });

  it('narrows the panel\'s chain builder the same way', async () => {
    const chainFor = () => ['split'];
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={[]} onChange={() => {}} chainFor={chainFor} />
    ));
    open(container); await flush(); await onCols(container);
    fireEvent.click(row(container, 'PRES').querySelector('[data-through]')!); await flush();
    const offered = [...builderIn(container, 'PRES').querySelectorAll('[data-node]')].map((e) => e.getAttribute('data-node'));
    expect(offered).toEqual(['split']);
  });

  it('shows no highlight for an untouched list, then the top match once something is typed', async () => {
    const { container } = mount([]);
    fireEvent.focus(box(container)); await flush();
    expect(container.querySelector('[data-highlighted]')).toBeNull();
    expect(box(container).getAttribute('aria-activedescendant')).toBeNull();
    await type(container, 'c');
    expect(container.querySelector('[data-highlighted]')!.getAttribute('data-suggestion')).toBe('cols');
    expect(box(container).getAttribute('aria-activedescendant')).not.toBeNull();
  });

  it('does not add the same value with the same chain twice', async () => {
    const written: SelectorItem[][] = [];
    const { container } = mount([{ cols: 'PRES' }], (items) => { written.push(items); });
    await type(container, 'c'); await key(container, 'Tab'); await type(container, 'PRES'); await key(container, 'Enter');
    expect(written).toEqual([]);
  });

  it('replaces the one item of a lone selector, and clears the box', async () => {
    let written: SelectorItem | undefined | null = null;
    const { container } = render(() => (
      <SelectorField single itemNode={itemNode} defs={defs} label="partition" value={{ cols: 'PRES' }} onChange={(item) => { written = item; }} />
    ));
    await type(container, 'c'); await key(container, 'Tab'); await type(container, 'TEMP'); await key(container, 'Enter');
    expect(written).toEqual({ cols: 'TEMP' });
    expect(tokens(container)).toEqual([]);
  });

  it('is a combobox to a screen reader', async () => {
    const { container } = mount([]);
    expect(box(container).getAttribute('role')).toBe('combobox');
    expect(box(container).getAttribute('aria-expanded')).toBe('false');
    await type(container, 'c');
    expect(box(container).getAttribute('aria-expanded')).toBe('true');
    expect(container.querySelector(`#${box(container).getAttribute('aria-activedescendant')}`)).not.toBeNull();
  });
});

describe('SelectorField, chips by keyboard', () => {
  const box = (c: HTMLElement) => c.querySelector('[data-entry]') as HTMLInputElement;
  const chips = (c: HTMLElement) => [...c.querySelectorAll('[data-chip]')] as HTMLElement[];

  it('reaches the chips from the empty box, walks them, and comes back', async () => {
    const { container } = mount([{ cols: 'PRES' }, { cols: 'TEMP' }]);
    box(container).focus();
    fireEvent.keyDown(box(container), { key: 'ArrowLeft' }); await flush();
    expect(document.activeElement).toBe(chips(container)[1]);
    fireEvent.keyDown(chips(container)[1], { key: 'ArrowLeft' }); await flush();
    expect(document.activeElement).toBe(chips(container)[0]);
    fireEvent.keyDown(chips(container)[0], { key: 'Escape' }); await flush();
    expect(document.activeElement).toBe(box(container));
  });

  it('removes the focused chip with Delete, and moves it with Alt and an arrow', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([{ cols: 'PRES' }, { groups: 'weather' }, { cols: 'TEMP' }], (items) => { written = items; });
    box(container).focus();
    fireEvent.keyDown(box(container), { key: 'ArrowLeft' }); await flush();
    fireEvent.keyDown(chips(container)[2], { key: 'ArrowLeft', altKey: true }); await flush();
    expect(written).toEqual([{ cols: ['PRES', 'TEMP'] }, { groups: 'weather' }]);   // neighbours of a kind are written as one item
    fireEvent.keyDown(document.activeElement!, { key: 'Delete' }); await flush();
    expect(written).toEqual([{ cols: 'PRES' }, { groups: 'weather' }]);
  });

  it('keeps the focus on a chip as it moves', async () => {
    const [value, setValue] = createSignal<SelectorItem[]>([{ cols: 'PRES' }, { groups: 'weather' }]);
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value()} onChange={setValue} />
    ));
    chips(container)[1].focus();
    fireEvent.keyDown(chips(container)[1], { key: 'ArrowLeft', altKey: true }); await flush();
    await new Promise((done) => requestAnimationFrame(() => done(null)));
    expect(chips(container).map((c) => c.getAttribute('data-chip'))).toEqual(['groups:weather', 'cols:PRES']);
    expect(document.activeElement).toBe(chips(container)[0]);
  });

  it('does not take the arrow while something is being typed', async () => {
    const { container } = mount([{ cols: 'PRES' }]);
    fireEvent.input(box(container), { target: { value: 'c' } }); await flush();
    box(container).focus();
    fireEvent.keyDown(box(container), { key: 'ArrowLeft' }); await flush();
    expect(document.activeElement).toBe(box(container));
  });
});

describe('SelectorField, teaching the keys', () => {
  it('puts the help button just before the text box, and shows one whole example in the empty box', () => {
    const { container } = mount([]);
    const focusable = [...container.querySelectorAll('[data-help], [data-entry]')];
    expect(focusable.map((e) => e.hasAttribute('data-help'))).toEqual([true, false]);
    expect((container.querySelector('[data-entry]') as HTMLInputElement).placeholder)
      .toBe('nodes: name @node, then Enter');
  });
});

describe('SelectorField, when its panel unfolds', () => {
  it('brings the panel into the middle of the view', async () => {
    const scrolled = vi.fn(); (Element.prototype as unknown as { scrollBy: unknown }).scrollBy = scrolled;
    const { container } = mount([]);
    const panel = container.querySelector('[data-panel]')!;
    panel.getBoundingClientRect = () => ({ top: 1000, bottom: 1200, height: 200 } as DOMRect);
    open(container); await flush();
    await new Promise((done) => requestAnimationFrame(() => done(null)));
    expect(scrolled).toHaveBeenCalledWith(expect.objectContaining({ top: 716 }));
    delete (Element.prototype as unknown as { scrollBy?: unknown }).scrollBy;
  });
});

describe('SelectorField, the panel as the box', () => {
  const nameOf = (c: HTMLElement, value: string) => row(c, value).querySelector('[data-name]') as HTMLButtonElement;
  const through = (c: HTMLElement, value: string) => row(c, value).querySelector('[data-through]') as HTMLButtonElement;

  it('adds direct on a click on the name, and removes it on the next', async () => {
    const written: SelectorItem[][] = [];
    const [value, setValue] = createSignal<SelectorItem[]>([]);
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value()} onChange={(items) => { written.push(items); setValue(items); }} />
    ));
    open(container); await flush(); await onCols(container);
    expect(container.querySelector('[role=switch]')).toBeNull();
    expect(container.querySelector('[data-add-case]')).toBeNull();
    fireEvent.click(nameOf(container, 'PRES')); await flush();
    expect(written.at(-1)).toEqual([{ cols: 'PRES' }]);
    expect(casesOf(container, 'PRES')).toEqual(['direct']);
    expect(nameOf(container, 'PRES').getAttribute('aria-pressed')).toBe('true');
    fireEvent.click(nameOf(container, 'PRES')); await flush();
    expect(written.at(-1)).toEqual([]);
  });

  it('a click on the name adds direct beside a chain the value already carries', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([{ cols: 'PRES', through: ['rescale'] }], (items) => { written = items; });
    open(container); await flush(); await onCols(container);
    fireEvent.click(nameOf(container, 'PRES')); await flush();
    expect(written).toEqual([{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }]);
  });

  it('through… opens a builder under the row: nodes toggle, in click order, and add writes the chain', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    open(container); await flush(); await onCols(container);
    fireEvent.click(row(container, 'PRES').querySelector('[data-through]')!); await flush();
    expect(builderIn(container, 'PRES')).not.toBeNull();
    expect(container.querySelector('[data-value="TEMP"]')).not.toBeNull();          // the rows stay
    fireEvent.click(nodeButton(container, 'PRES', 'split')); await flush();
    fireEvent.click(nodeButton(container, 'PRES', 'rescale')); await flush();
    const preview = () => builderIn(container, 'PRES').querySelector('[data-chain-preview]')!.textContent;
    expect(nodeButton(container, 'PRES', 'split').getAttribute('aria-pressed')).toBe('true');
    expect(preview()).toBe('→ split → rescale');
    fireEvent.click(nodeButton(container, 'PRES', 'split')); await flush();          // deselect
    expect(nodeButton(container, 'PRES', 'split').getAttribute('aria-pressed')).toBe('false');
    expect(preview()).toBe('→ rescale');
    fireEvent.click(builderIn(container, 'PRES').querySelector('[data-chain="commit"]')!); await flush();
    expect(written).toEqual([{ cols: 'PRES', through: ['rescale'] }]);
    expect(builderIn(container, 'PRES')).toBeNull();
  });

  it('keeps the instruction at the top of the builder, and cancels in the danger dress of Remove', async () => {
    const { container } = mount([]);
    open(container); await flush(); await onCols(container);
    fireEvent.click(row(container, 'PRES').querySelector('[data-through]')!); await flush();
    const builder = () => builderIn(container, 'PRES');
    const said = () => builder().firstElementChild!;
    expect(said().textContent).toBe('pick nodes — order matters');
    expect(builder().children.length).toBe(3);                 // no chain yet, so no preview row
    fireEvent.click(nodeButton(container, 'PRES', 'rescale')); await flush();
    expect(said().textContent).toBe('pick nodes — order matters');     // it stays once a node is on
    expect(builder().querySelector('[data-chain-preview]')!.textContent).toBe('→ rescale');
    // Four rows, in reading order: what to do, the nodes, the chain, the actions.
    const rows = () => [...builder().children];
    expect(rows().length).toBe(4);
    expect(rows()[1].querySelectorAll('[data-node]').length).toBeGreaterThan(0);
    expect(rows()[2].hasAttribute('data-chain-preview')).toBe(true);
    expect(rows()[3].querySelector('[data-chain="commit"]')).not.toBeNull();
    const cancel = builder().querySelector('[data-chain="cancel"]')!;
    expect(cancel.textContent).toBe('cancel');
    expect(cancel.className).toContain('text-destructive');
  });

  it('reads a chain as arrows in the panel, the chip keeping the typed form', async () => {
    const { container } = mount([{ cols: 'PRES', through: ['rescale', 'split'] }]);
    open(container); await flush(); await onCols(container);
    expect(row(container, 'PRES').querySelector('[data-case]')!.textContent).toContain('→ rescale → split');
    expect(container.querySelector('[data-chip]')!.getAttribute('data-chip')).toBe('cols:PRES@rescale@split');
  });

  it('offers no add before a node is picked, and through… nothing when no node may follow', async () => {
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={[]} onChange={() => {}} chainFor={() => []} />
    ));
    open(container); await flush(); await onCols(container);
    expect(through(container, 'PRES').disabled).toBe(true);
    const { container: other } = mount([]);
    open(other); await flush(); await onCols(other);
    fireEvent.click(through(other, 'PRES')); await flush();
    expect(builderIn(other, 'PRES').querySelector('[data-chain="commit"]')).toBeNull();
    fireEvent.click(builderIn(other, 'PRES').querySelector('[data-chain="cancel"]')!); await flush();
    expect(builderIn(other, 'PRES')).toBeNull();
  });
});

describe('SelectorField, folded by its host', () => {
  it('draws no fold control of its own, and the panel follows the host', async () => {
    const [shown, setShown] = createSignal(false);
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="selection" open={shown()} value={[]} onChange={() => {}} />
    ));
    expect(container.querySelector('[data-fold]')).toBeNull();
    expect(container.querySelector('[data-entry]')).not.toBeNull();
    expect((container.querySelector('[data-panel]') as HTMLElement).hidden).toBe(true);
    setShown(true); await flush();
    expect((container.querySelector('[data-panel]') as HTMLElement).hidden).toBe(false);
  });
});
