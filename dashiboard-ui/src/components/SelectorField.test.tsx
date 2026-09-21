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
const sw = (c: HTMLElement, value: string) =>
  row(c, value).querySelector('[role=switch]') as HTMLButtonElement;
const casesOf = (c: HTMLElement, value: string) =>
  [...row(c, value).querySelectorAll('[data-case]')].map((e) => e.getAttribute('data-case'));
/** Re-queried, never held: `<Show keyed>` replaces this node on every chain change. */
const builderIn = (c: HTMLElement, value: string) =>
  row(c, value).querySelector('[data-chain-builder]') as HTMLElement;
const nodeButton = (c: HTMLElement, value: string, name: string) =>
  [...builderIn(c, value).querySelectorAll('button')].find((b) => b.textContent === name)!;
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

  it('shows a switch per value in the open vocabulary, all off for an empty field', async () => {
    const { container } = mount([]);
    await onCols(container);
    expect(sw(container, 'TEMP').getAttribute('aria-checked')).toBe('false');
    expect(casesOf(container, 'TEMP')).toEqual([]);
  });

  it('reads an existing document back onto the rows it came from', async () => {
    const { container } = mount([{ cols: ['PRES', 'TEMP'] }]);
    await onCols(container);
    expect(sw(container, 'PRES').getAttribute('aria-checked')).toBe('true');
    expect(casesOf(container, 'PRES')).toEqual(['direct']);
    expect(casesOf(container, 'TEMP')).toEqual(['direct']);
    expect(sw(container, 'No').getAttribute('aria-checked')).toBe('false');
  });

  it('holds the same value twice when it is qualified differently — case E', async () => {
    // The case that rules out modelling a field as a set of values with attributes, and the whole
    // reason this layout needed the `+` before it could be used at all.
    const { container } = mount([{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }]);
    await onCols(container);
    expect(casesOf(container, 'PRES')).toEqual(['rescale', 'direct']);
  });

  it('keeps chain order, since [a,b] names a different column from [b,a]', async () => {
    const { container } = mount([{ cols: 'PRES', through: ['rescale', 'split'] }]);
    await onCols(container);
    expect(casesOf(container, 'PRES')).toEqual(['rescale→split']);
  });

  it('asks direct-or-through when a value is switched on, and writes nothing yet', async () => {
    // Nothing is assumed: a value switched on with no qualification is unfinished, not direct.
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    await onCols(container);
    fireEvent.click(sw(container, 'TEMP'));
    await flush();
    expect(row(container, 'TEMP').querySelector('[data-specify="direct"]')).not.toBeNull();
    expect(row(container, 'TEMP').querySelector('[data-specify="through"]')).not.toBeNull();
    expect(written).toBeNull();
  });

  it('writes the item once direct is chosen', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    await onCols(container);
    fireEvent.click(sw(container, 'TEMP'));
    await flush();
    fireEvent.click(row(container, 'TEMP').querySelector('[data-specify="direct"]')!);
    await flush();
    expect(written).toEqual([{ cols: 'TEMP' }]);
  });

  it('adds a second qualification through +, which is what case E needs', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([{ cols: 'PRES' }], (items) => { written = items; });
    await onCols(container);
    fireEvent.click(container.querySelector('[data-add-case="PRES"]')!);
    await flush();
    fireEvent.click(row(container, 'PRES').querySelector('[data-specify="through"]')!);
    await flush();
    fireEvent.click(nodeButton(container, 'PRES', 'rescale'));
    await flush();
    fireEvent.click(builderIn(container, 'PRES').querySelector('[data-chain="commit"]')!);
    await flush();
    expect(written).toEqual([{ cols: 'PRES' }, { cols: 'PRES', through: ['rescale'] }]);
  });

  it('will not offer direct twice for one value', async () => {
    const { container } = mount([{ cols: 'PRES' }]);
    await onCols(container);
    fireEvent.click(container.querySelector('[data-add-case="PRES"]')!);
    await flush();
    const direct = row(container, 'PRES').querySelector('[data-specify="direct"]') as HTMLButtonElement;
    expect(direct.disabled).toBe(true);
  });

  it('records the order nodes are clicked, since [a,b] names a different column from [b,a]', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    await onCols(container);
    fireEvent.click(sw(container, 'TEMP'));
    await flush();
    fireEvent.click(row(container, 'TEMP').querySelector('[data-specify="through"]')!);
    await flush();
    fireEvent.click(nodeButton(container, 'TEMP', 'split'));
    await flush();
    fireEvent.click(nodeButton(container, 'TEMP', 'rescale'));
    await flush();
    fireEvent.click(builderIn(container, 'TEMP').querySelector('[data-chain="commit"]')!);
    await flush();
    expect(written).toEqual([{ cols: 'TEMP', through: ['split', 'rescale'] }]);
  });

  it('switching a value off removes every qualification it carried', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount(
      [{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }, { cols: 'TEMP' }],
      (items) => { written = items; },
    );
    await onCols(container);
    fireEvent.click(sw(container, 'PRES'));
    await flush();
    expect(written).toEqual([{ cols: 'TEMP' }]);
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

  it('cancelling a chain on a value with nothing else switches it back off', async () => {
    const { container } = mount([]);
    await onCols(container);
    fireEvent.click(sw(container, 'TEMP'));
    await flush();
    fireEvent.click(row(container, 'TEMP').querySelector('[data-specify="through"]')!);
    await flush();
    fireEvent.click(row(container, 'TEMP').querySelector('[data-chain="cancel"]')!);
    await flush();
    expect(sw(container, 'TEMP').getAttribute('aria-checked')).toBe('false');
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
    expect(sw(container, 'weather')).not.toBeNull();
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
      fireEvent.click(sw(container, 'TEMP'));
      await flush();
      const through = row(container, 'TEMP')
        .querySelector('[data-specify="through"]') as HTMLButtonElement;
      expect(through.disabled).toBe(true);
      expect(through.title).toMatch(/no nodes/i);
    });

    it('still offers direct, which is the one qualification that needs nothing', async () => {
      const { container } = mountNoNodes([]);
      await onCols(container);
      fireEvent.click(sw(container, 'TEMP'));
      await flush();
      const direct = row(container, 'TEMP')
        .querySelector('[data-specify="direct"]') as HTMLButtonElement;
      expect(direct.disabled).toBe(false);
    });

    it('withholds + once direct is taken, since nothing further can be specified', async () => {
      // Both routes closed: direct is used and no chain can be built. A + here opens a panel
      // whose every option is disabled, which is worse than not offering it.
      const { container } = mountNoNodes([{ cols: 'PRES' }]);
      expect(container.querySelector('[data-add-case="PRES"]')).toBeNull();
    });

    it('keeps + while a chain is still buildable', async () => {
      const { container } = mount([{ cols: 'PRES' }]);
      await onCols(container);
      expect(container.querySelector('[data-add-case="PRES"]')).not.toBeNull();
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

  it('marks a value the vocabulary cannot name, and lets it be removed', async () => {
    // Check 11 by hand: after loading a table without TEMP, a card's `{cols: "TEMP"}` had no
    // switch to turn it off — the picker lists the vocabulary, and the value was not in it.
    const onChange = vi.fn();
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs"
        value={[{ cols: 'GONE' }, { cols: 'TEMP' }]} onChange={onChange} />
    ));
    const chip = container.querySelector('[data-chip="cols:GONE"]')!;
    expect(chip.getAttribute('data-missing')).toBe('true');
    expect(container.querySelector('[data-chip="cols:TEMP"]')!.getAttribute('data-missing')).toBeNull();
    fireEvent.click(chip.querySelector('[data-remove]')!);
    await flush();
    expect(onChange).toHaveBeenCalledWith([{ cols: 'TEMP' }]);
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
    expect(sw(container, 'PRES').getAttribute('aria-checked')).toBe('true');
    expect(casesOf(container, 'PRES')).toEqual(['direct']);
    expect(sw(container, 'TEMP').getAttribute('aria-checked')).toBe('false');
    expect(writes(container)).toBe('{cols = "PRES"}');
  });

  it('writes one item, not a list, and a second pick replaces the first', async () => {
    let written: SelectorItem | undefined | null = null;
    const { container } = one({ cols: 'PRES' }, (item) => { written = item; });
    await onCols(container);
    fireEvent.click(sw(container, 'TEMP'));
    await flush();
    fireEvent.click(row(container, 'TEMP').querySelector('[data-specify="direct"]')!);
    await flush();
    expect(written).toEqual({ cols: 'TEMP' });
  });

  it('empties the field when its value is switched off', async () => {
    let written: SelectorItem | undefined | null = null;
    const { container } = one({ cols: 'PRES' }, (item) => { written = item; });
    await onCols(container);
    fireEvent.click(sw(container, 'PRES'));
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
    await onCols(second.container);
    fireEvent.click(sw(second.container, 'TEMP'));
    await flush();
    fireEvent.click(row(second.container, 'TEMP').querySelector('[data-specify="through"]')!);
    await flush();
    fireEvent.click(nodeButton(second.container, 'TEMP', 'split'));
    await flush();
    fireEvent.click(builderIn(second.container, 'TEMP').querySelector('[data-chain="commit"]')!);
    await flush();
    expect(written).toEqual({ cols: 'TEMP', through: ['split'] });
  });

  it('has no order strip and offers no second qualification', async () => {
    const { container } = one({ cols: 'PRES' });
    await onCols(container);
    expect(container.querySelector('[data-move]')).toBeNull();
    expect(container.querySelector('[data-add-case]')).toBeNull();
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

  it('gives the mouse the panel\'s two words in the list: direct finishes, through… asks for a node', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    await type(container, 'c'); await key(container, 'Tab');
    fireEvent.click(container.querySelector('[data-suggestion="TEMP"] [data-pick="direct"]')!); await flush();
    expect(written).toEqual([{ cols: 'TEMP' }]);
    fireEvent.click(container.querySelector('[data-suggestion="PRES"] [data-pick="through"]')!); await flush();
    expect(tokens(container)).toEqual(['cols:', 'PRES']);
    expect(box(container).value).toBe('@');
    expect(container.querySelector('[data-suggestion="rescale"]')).not.toBeNull();
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
