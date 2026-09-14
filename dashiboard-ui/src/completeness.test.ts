import { describe, it, expect } from 'vitest';
import { checkGroup, checkNode } from './completeness';

describe('checkGroup', () => {
  it('objects to a group that selects nothing', () => {
    // `weather = []` constructs fine server-side — measured — so this is ours to say or nobody's.
    expect(checkGroup([])).toHaveLength(1);
    expect(checkGroup([])[0].message).toMatch(/at least one/i);
  });

  it('says nothing about a group that selects something', () => {
    expect(checkGroup([{ cols: 'TEMP' }])).toEqual([]);
    expect(checkGroup([{ cols: ['PRES', 'TEMP'] }, { nodes: 'rescale' }])).toEqual([]);
  });
});

describe('checkNode', () => {
  it('objects to a card nothing can refer to', () => {
    expect(checkNode({ card: { type: 'rescale' } })).toHaveLength(1);
    expect(checkNode({ id: '', card: { type: 'rescale' } })).toHaveLength(1);
    expect(checkNode({ id: '   ', card: { type: 'rescale' } })).toHaveLength(1);
  });

  it('says nothing about a named card', () => {
    expect(checkNode({ id: 'rescale', card: { type: 'rescale' } })).toEqual([]);
  });

  it('says nothing about the card itself — that is `checkFields`\' question', () => {
    // `checkNode` asks one thing: can anything refer to this node. The card's own unanswered
    // fields are a separate walk over the IR, so a named card with an empty body passes here and
    // is caught there. Both run on Confirm; keeping them apart is what lets the id rule apply to
    // a card type this UI has never seen.
    expect(checkNode({ id: 'rescale', card: { type: 'rescale' } })).toEqual([]);
  });
});
