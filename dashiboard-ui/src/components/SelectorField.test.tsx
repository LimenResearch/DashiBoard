import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup } from '@solidjs/testing-library';
import { SelectorField } from './SelectorField';
import type { Defs, IRNode } from '../ir';
import payload from '../fixtures/card-ir.json';

const defs = payload.defs as Defs;
const itemNode = defs.variable as IRNode;

const sections = (c: HTMLElement) =>
  [...c.querySelectorAll('legend')].map((l) => l.textContent ?? '');
const chosenIn = (c: HTMLElement, legend: string, kind: string) => {
  const set = [...c.querySelectorAll('fieldset')].find(
    (f) => (f.querySelector('legend')?.textContent ?? '') === legend,
  )!;
  const labels = [...set.querySelectorAll('label')];
  const idx = labels.findIndex((l) => l.textContent === kind);
  const select = set.querySelectorAll('select')[idx] as HTMLSelectElement;
  return [...select.selectedOptions].map((o) => o.value);
};

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
    const direct = [...container.querySelectorAll('fieldset')][0];
    const select = direct.querySelectorAll('select')[2] as HTMLSelectElement; // nodes, groups, cols
    [...select.options].forEach((o) => (o.selected = o.value === 'No' || o.value === 'TEMP'));
    select.dispatchEvent(new Event('change', { bubbles: true }));
    expect(written).toEqual([{ cols: ['No', 'TEMP'] }]);
  });

  it('offers the nodes as pass-through candidates', () => {
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={[]} onChange={() => {}} />
    ));
    const add = [...container.querySelectorAll('select')].at(-1) as HTMLSelectElement;
    expect([...add.options].map((o) => o.value)).toEqual(['rescale', 'split']);
  });
});
