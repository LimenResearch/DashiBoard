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
const boxesIn = (c: HTMLElement, legend: string, kind: string) => {
  const set = [...c.querySelectorAll('fieldset')].find(
    (f) => (f.querySelector('legend')?.textContent ?? '') === legend,
  )!;
  const group = set.querySelector(`[data-kind="${kind}"]`)!;
  return [...group.querySelectorAll('input[type=checkbox]')] as HTMLInputElement[];
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
    let written: unknown = null;
    const { container, getByText } = render(() => (
      <SelectorField
        itemNode={itemNode} defs={defs} label="inputs" value={[{ cols: 'TEMP' }]}
        onChange={(items) => { written = items; }}
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
    expect(written).toEqual([
      { cols: 'TEMP' },
      { cols: [], through: ['split', 'rescale'] },
    ]);
  });
});
