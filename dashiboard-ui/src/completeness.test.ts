import { describe, it, expect } from 'vitest';
import { checkNode, checkNames } from './completeness';

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

describe('checkNames', () => {
  // Two cards with one name is a document the server cannot build, and it says so with no
  // pointer (`Encountered nodes with equal \`id\``, measured 2026-09-17) — so no card could carry
  // it. The UI owns the rule since `setNodeId` refuses a taken name; an uploaded document is the
  // one way two cards still arrive with one name, and this places the finding on the later one.
  const card = { type: 'rescale' };
  it('marks every card after the first with a taken name, not the first', () => {
    expect(checkNames([{ id: 'a', card }, { id: 'b', card }, { id: 'a', card }, { id: 'a', card }]))
      .toEqual([
        { index: 2, finding: { message: 'There is already a card called "a".' } },
        { index: 3, finding: { message: 'There is already a card called "a".' } },
      ]);
  });
  it('counts a missing id as "", which only one card can be', () => {
    // `Pipelines.get_id` defaults a missing id to "", so two unnamed cards collide the same way.
    expect(checkNames([{ card }, { id: '', card }])).toEqual([
      { index: 1, finding: { message: 'There is already a card without a name.' } },
    ]);
  });
  it('finds nothing when names are distinct', () => {
    expect(checkNames([{ id: 'a', card }, { card }, { id: 'b', card }])).toEqual([]);
  });
});
