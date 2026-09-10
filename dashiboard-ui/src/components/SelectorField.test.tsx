import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { SelectorField } from './SelectorField';
import type { Defs, IRNode } from '../ir';
import payload from '../fixtures/card-ir.json';

const defs = payload.defs as Defs;
const itemNode = defs.variable as IRNode;

const sections = (c: HTMLElement) =>
  [...c.querySelectorAll('legend')].map((l) => l.textContent ?? '');
const sectionIn = (c: HTMLElement, legend: string) =>
  [...c.querySelectorAll('fieldset')].find(
    (f) => (f.querySelector('legend')?.textContent ?? '') === legend,
  )!;
const tabsIn = (c: HTMLElement, legend: string) =>
  [...sectionIn(c, legend).querySelectorAll('[role=tab]')] as HTMLButtonElement[];
/** The checkboxes of one kind. Only the open tab is on screen, so open it first. */
const boxesIn = (c: HTMLElement, legend: string, kind: string) => {
  const section = sectionIn(c, legend);
  const panel = section.querySelector(`[role=tabpanel][data-kind="${kind}"]`);
  if (panel === null) return [];
  return [...panel.querySelectorAll('input[type=checkbox]')] as HTMLInputElement[];
};
const chosenIn = (c: HTMLElement, legend: string, kind: string) =>
  boxesIn(c, legend, kind).filter((b) => b.checked).map((b) => b.value);

afterEach(cleanup);

describe('SelectorField', () => {
  it('always offers a Direct section, even when the field is empty', () => {
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={[]} onChange={() => {}} />
    ));
    expect(sections(container)).toEqual(['Direct']);
  });

  it('puts the kinds behind tabs, showing one at a time', () => {
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={[]} onChange={() => {}} />
    ));
    expect(tabsIn(container, 'Direct').map((t) => t.getAttribute('data-tab')))
      .toEqual(['cols', 'groups', 'nodes']);
    // one panel, not three: the whole point of a tab is that the others are not on screen
    expect(container.querySelectorAll('[role=tabpanel]')).toHaveLength(1);
    expect(container.querySelector('[role=tabpanel]')!.getAttribute('data-kind')).toBe('cols');
  });

  it('switches kind when a tab is clicked, and says when a vocabulary is empty', async () => {
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={[]} onChange={() => {}} />
    ));
    fireEvent.click(tabsIn(container, 'Direct').find((t) => t.getAttribute('data-tab') === 'groups')!);
    await flush();
    const panel = container.querySelector('[role=tabpanel]')!;
    expect(panel.getAttribute('data-kind')).toBe('groups');
    expect(panel.textContent).toContain('weather');
  });

  it('opens on a kind that has something to offer', () => {
    // No source loaded yet is the ordinary state on a fresh page. Opening on an empty `cols`
    // would show "none defined" while the nodes tab silently holds the only real choice.
    const noCols = { ...defs, col: { type: 'string', enum: [] } } as Defs;
    const { container } = render(() => (
      <SelectorField
        itemNode={itemNode} defs={noCols} label="inputs" value={[]} onChange={() => {}}
      />
    ));
    expect(container.querySelector('[role=tabpanel]')!.getAttribute('data-kind')).toBe('groups');
  });

  it('counts a hidden tab\'s selections, so switching away does not hide them', () => {
    const { container } = render(() => (
      <SelectorField
        itemNode={itemNode} defs={defs} label="inputs"
        value={[{ cols: ['PRES', 'TEMP'] }, { nodes: 'rescale' }]} onChange={() => {}}
      />
    ));
    const label = (kind: string) =>
      tabsIn(container, 'Direct').find((t) => t.getAttribute('data-tab') === kind)!.textContent;
    expect(label('cols')).toContain('2');
    expect(label('nodes')).toContain('1');
    expect(label('groups')).toBe('groups'); // nothing chosen, so no count
  });

  it('groups items by their pass-through chain', () => {
    // case C: same kind, different through — the two must not merge
    const value = [
      { cols: 'PRES', through: ['rescale'] },
      { cols: 'TEMP' },
    ];
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value} onChange={() => {}} />
    ));
    expect(sections(container)).toEqual(['Direct', 'Through rescale']);
    expect(chosenIn(container, 'Direct', 'cols')).toEqual(['TEMP']);
    expect(chosenIn(container, 'Through rescale', 'cols')).toEqual(['PRES']);
  });

  it('holds the same column twice when it is qualified differently', () => {
    // case E: the one a set-of-values layout cannot represent
    const value = [
      { cols: 'PRES', through: ['rescale'] },
      { cols: 'PRES' },
    ];
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value} onChange={() => {}} />
    ));
    expect(chosenIn(container, 'Direct', 'cols')).toEqual(['PRES']);
    expect(chosenIn(container, 'Through rescale', 'cols')).toEqual(['PRES']);
  });

  it('keeps chain order, since [a,b] names a different column from [b,a]', () => {
    const value = [{ cols: 'PRES', through: ['rescale', 'split'] }];
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value} onChange={() => {}} />
    ));
    expect(sections(container)).toEqual(['Direct', 'Through rescale → split']);
  });

  it('writes back one item per kind and chain, with the chain preserved', () => {
    let written: unknown = null;
    const value = [{ cols: 'TEMP' }];
    const { container } = render(() => (
      <SelectorField
        itemNode={itemNode} defs={defs} label="inputs" value={value}
        onChange={(items) => { written = items; }}
      />
    ));
    // a plain click adds, rather than replacing — which is the point of the change
    const no = boxesIn(container, 'Direct', 'cols').find((b) => b.value === 'No')!;
    no.checked = true;
    no.dispatchEvent(new Event('change', { bubbles: true }));
    expect(written).toEqual([{ cols: ['TEMP', 'No'] }]);
  });

  it('offers the nodes as pass-through candidates', () => {
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={[]} onChange={() => {}} />
    ));
    const builder = container.querySelector('[data-chain-builder]')!;
    expect([...builder.querySelectorAll('button')].map((b) => b.textContent))
      .toEqual(['rescale', 'split']);
  });
});

describe('the pass-through chain builder', () => {
  it('records the order nodes are clicked, since [a,b] names a different column from [b,a]', async () => {
    const { container, getByText } = render(() => (
      <SelectorField
        itemNode={itemNode} defs={defs} label="inputs" value={[{ cols: 'TEMP' }]}
        onChange={() => {}}
      />
    ));
    const builder = container.querySelector('[data-chain-builder]')!;
    const button = (name: string) =>
      [...builder.querySelectorAll('button')].find((b) => b.textContent === name)!;
    // click split first, then rescale — the reverse of the listed order
    fireEvent.click(button('split'));
    await flush();
    fireEvent.click(button('rescale'));
    await flush(); // Solid 2 defers signal updates; the assertion cannot share their tick
    expect(builder.textContent).toContain('split → rescale');
    fireEvent.click(getByText('add section'));
    await flush();
    expect(sections(container)).toContain('Through split → rescale');
  });

  it('opens a section without writing an empty item into the document', async () => {
    // The document is what the user is editing. A section they have chosen nothing in yet
    // would export as `{cols = [], through = [...]}` — valid, resolves to nothing, and pure
    // noise in their TOML. It belongs to the control until it holds a value.
    let written: unknown = null;
    const { container, getByText } = render(() => (
      <SelectorField
        itemNode={itemNode} defs={defs} label="inputs" value={[{ cols: 'TEMP' }]}
        onChange={(items) => { written = items; }}
      />
    ));
    const builder = container.querySelector('[data-chain-builder]')!;
    fireEvent.click([...builder.querySelectorAll('button')].find((b) => b.textContent === 'rescale')!);
    await flush();
    fireEvent.click(getByText('add section'));
    await flush();

    expect(sections(container)).toEqual(['Direct', 'Through rescale']);
    expect(written).toBeNull(); // opened, but the document is untouched

    const box = boxesIn(container, 'Through rescale', 'cols').find((b) => b.value === 'PRES')!;
    fireEvent.click(box);
    await flush();
    expect(written).toEqual([{ cols: ['TEMP'] }, { cols: ['PRES'], through: ['rescale'] }]);
  });
});
