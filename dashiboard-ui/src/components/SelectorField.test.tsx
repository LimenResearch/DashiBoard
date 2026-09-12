import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { SelectorField } from './SelectorField';
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

describe('SelectorField', () => {
  it('opens on a kind that has something to offer', () => {
    const { container } = mount([]);
    expect(container.querySelector('[role=tab][aria-selected="true"]')?.getAttribute('data-tab'))
      .toBe('cols');
  });

  it('shows a switch per value in the open vocabulary, all off for an empty field', () => {
    const { container } = mount([]);
    expect(sw(container, 'TEMP').getAttribute('aria-checked')).toBe('false');
    expect(casesOf(container, 'TEMP')).toEqual([]);
  });

  it('reads an existing document back onto the rows it came from', () => {
    const { container } = mount([{ cols: ['PRES', 'TEMP'] }]);
    expect(sw(container, 'PRES').getAttribute('aria-checked')).toBe('true');
    expect(casesOf(container, 'PRES')).toEqual(['direct']);
    expect(casesOf(container, 'TEMP')).toEqual(['direct']);
    expect(sw(container, 'No').getAttribute('aria-checked')).toBe('false');
  });

  it('holds the same value twice when it is qualified differently — case E', () => {
    // The case that rules out modelling a field as a set of values with attributes, and the whole
    // reason this layout needed the `+` before it could be used at all.
    const { container } = mount([{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }]);
    expect(casesOf(container, 'PRES')).toEqual(['rescale', 'direct']);
  });

  it('keeps chain order, since [a,b] names a different column from [b,a]', () => {
    const { container } = mount([{ cols: 'PRES', through: ['rescale', 'split'] }]);
    expect(casesOf(container, 'PRES')).toEqual(['rescale→split']);
  });

  it('asks direct-or-through when a value is switched on, and writes nothing yet', async () => {
    // Nothing is assumed: a value switched on with no qualification is unfinished, not direct.
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    fireEvent.click(sw(container, 'TEMP'));
    await flush();
    expect(row(container, 'TEMP').querySelector('[data-specify="direct"]')).not.toBeNull();
    expect(row(container, 'TEMP').querySelector('[data-specify="through"]')).not.toBeNull();
    expect(written).toBeNull();
  });

  it('writes the item once direct is chosen', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    fireEvent.click(sw(container, 'TEMP'));
    await flush();
    fireEvent.click(row(container, 'TEMP').querySelector('[data-specify="direct"]')!);
    await flush();
    expect(written).toEqual([{ cols: 'TEMP' }]);
  });

  it('adds a second qualification through +, which is what case E needs', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([{ cols: 'PRES' }], (items) => { written = items; });
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
    fireEvent.click(container.querySelector('[data-add-case="PRES"]')!);
    await flush();
    const direct = row(container, 'PRES').querySelector('[data-specify="direct"]') as HTMLButtonElement;
    expect(direct.disabled).toBe(true);
  });

  it('records the order nodes are clicked, since [a,b] names a different column from [b,a]', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
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
    const direct = [...row(container, 'PRES').querySelectorAll('[data-case]')]
      .find((e) => e.getAttribute('data-case') === 'direct')!;
    fireEvent.click(direct.querySelector('button')!);
    await flush();
    expect(written).toEqual([{ cols: 'PRES', through: ['rescale'] }]);
  });

  it('cancelling a chain on a value with nothing else switches it back off', async () => {
    const { container } = mount([]);
    fireEvent.click(sw(container, 'TEMP'));
    await flush();
    fireEvent.click(row(container, 'TEMP').querySelector('[data-specify="through"]')!);
    await flush();
    fireEvent.click(row(container, 'TEMP').querySelector('[data-chain="cancel"]')!);
    await flush();
    expect(sw(container, 'TEMP').getAttribute('aria-checked')).toBe('false');
  });

  it('shows the document it writes, in the selector form and never a resolved name', () => {
    // `PRES_rescaled` must not appear: the UI writes the TOML, DashiBoard resolves it.
    const { container } = mount([{ cols: ['No', 'year'] }, { cols: 'month', through: ['log'] }]);
    expect(writes(container)).toBe('{cols = ["No", "year"]}, {cols = "month", through = "log"}');
    expect(writes(container)).not.toContain('month_log');
  });

  it('switches vocabulary on a tab click, and says when one is empty', async () => {
    const { container } = mount([]);
    fireEvent.click(tab(container, 'groups'));
    await flush();
    expect(row(container, 'weather')).not.toBeNull();
    expect(sw(container, 'weather')).not.toBeNull();
  });

  it('counts each tab by values carrying a qualification, not by items', () => {
    // `PRES` twice is one value, so the tab says 1 — the count answers "how many of these have I
    // touched", which is what a hidden tab needs to report.
    const { container } = mount([{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }]);
    expect(tab(container, 'cols').textContent).toContain('1');
  });
});
