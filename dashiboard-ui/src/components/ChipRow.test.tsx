import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { SelectorField } from './SelectorField';
import type { Defs, IRNode } from '../ir';
import payload from '../fixtures/card-ir.json';

const defs = payload.defs as Defs;
const itemNode = defs.variable as IRNode;

const chipText = (c: HTMLElement) =>
  [...c.querySelectorAll('[data-chip]')].map((e) => e.getAttribute('data-chip') ?? '');

afterEach(cleanup);

describe('the chip row', () => {
  it('shows every value in document order, across kinds', () => {
    // section 12's positional `weights` rule depends on this order, so the row must reflect the
    // document rather than the panel layout.
    const value = [{ nodes: 'rescale' }, { cols: ['TEMP', 'PRES'] }];
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value} onChange={() => {}} />
    ));
    expect(chipText(container)).toEqual(['nodes:rescale', 'cols:TEMP', 'cols:PRES']);
  });

  it('shows a chip its pass-through chain, in order', () => {
    const value = [{ cols: 'PRES', through: ['rescale', 'split'] }];
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value} onChange={() => {}} />
    ));
    expect(chipText(container)).toEqual(['cols:PRES·rescale→split']);
  });

  it('distinguishes the same value under different qualifications', () => {
    // case E again, this time in the row rather than the panels
    const value = [{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }];
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value} onChange={() => {}} />
    ));
    expect(chipText(container)).toEqual(['cols:PRES·rescale', 'cols:PRES']);
  });

  it('reorders across kinds, which the panels alone cannot express', () => {
    let written: unknown = null;
    const value = [{ nodes: 'rescale' }, { cols: 'TEMP' }];
    const { container } = render(() => (
      <SelectorField
        itemNode={itemNode} defs={defs} label="inputs" value={value}
        onChange={(items) => { written = items; }}
      />
    ));
    const later = container.querySelectorAll('[data-move="later"]')[0] as HTMLButtonElement;
    fireEvent.click(later);
    // one item per chip: lossless, since one item with several values resolves the same way
    expect(written).toEqual([{ cols: 'TEMP' }, { nodes: 'rescale' }]);
  });

  it('carries the chain through a reorder', () => {
    let written: unknown = null;
    const value = [{ cols: 'TEMP' }, { cols: 'PRES', through: ['rescale'] }];
    const { container } = render(() => (
      <SelectorField
        itemNode={itemNode} defs={defs} label="inputs" value={value}
        onChange={(items) => { written = items; }}
      />
    ));
    fireEvent.click(container.querySelectorAll('[data-move="earlier"]')[1] as HTMLButtonElement);
    expect(written).toEqual([{ cols: 'PRES', through: ['rescale'] }, { cols: 'TEMP' }]);
  });

  it('offers a keyboard path, not only dragging', () => {
    const value = [{ cols: 'TEMP' }, { cols: 'PRES' }];
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs" value={value} onChange={() => {}} />
    ));
    const chips = [...container.querySelectorAll('[data-chip]')];
    expect(chips.every((c) => c.getAttribute('draggable') === 'true')).toBe(true);
    const earlier = container.querySelectorAll('[data-move="earlier"]');
    const later = container.querySelectorAll('[data-move="later"]');
    expect((earlier[0] as HTMLButtonElement).disabled).toBe(true); // first chip
    expect((later[1] as HTMLButtonElement).disabled).toBe(true); // last chip
  });
});
