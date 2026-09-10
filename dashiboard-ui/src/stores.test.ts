import { describe, it, expect, beforeEach } from 'vitest';
import {
  emptyCards, importCards, exportCards, setCard, setCardField, addNode, removeNode,
  CARDS_STORE, type CardsStore,
} from './stores';
import { getCards } from './left-tabs/processing';

// The authored card half of a Config, in the post-9bd6c28 group vocabulary: plural selectors are
// arrays, singular ones are objects, and a selector value may be a string or a list.
const STORED: CardsStore = {
  nodes: [
    {
      id: 'rescale',
      card: {
        type: 'rescale',
        method: { type: 'zscore' },
        group_by: [{ cols: 'cbwd' }],
        partition: { nodes: 'partition' },
        inputs: [{ groups: 'weather' }, { cols: 'No' }],
      },
    },
  ],
  groups: { weather: [{ cols: ['PRES', 'TEMP'] }] },
};

describe('the document is the model', () => {
  beforeEach(() => importCards(emptyCards()));

  it('starts empty', () => {
    expect(exportCards()).toEqual({ nodes: [], groups: {} });
  });

  it('round-trips a stored document verbatim', () => {
    importCards(structuredClone(STORED));
    expect(exportCards()).toEqual(STORED);
  });

  it('preserves top-level keys it does not understand', () => {
    // section 2: what gets saved is the stored JSON, never a reconstruction. A future `version`
    // key must survive a UI that has never heard of it.
    const withExtra = { ...structuredClone(STORED), version: 'dashi/1' };
    importCards(withExtra);
    expect(exportCards()).toEqual(withExtra);
  });

  it('edits a card field in place and leaves the rest untouched', () => {
    importCards(structuredClone(STORED));
    setCardField(0, 'suffix', 'zscored');
    const after = exportCards();
    expect(after.nodes[0].card.suffix).toBe('zscored');
    expect(after.nodes[0].card.method).toEqual({ type: 'zscore' });
    expect(after.groups).toEqual(STORED.groups);
  });

  it('replaces a whole card, which is what an IRField edit produces', () => {
    importCards(structuredClone(STORED));
    setCard(0, { type: 'rescale', method: { type: 'log' }, suffix: 'logged' });
    expect(exportCards().nodes[0].card).toEqual({
      type: 'rescale', method: { type: 'log' }, suffix: 'logged',
    });
    expect(exportCards().nodes[0].id).toBe('rescale'); // the node wrapper survives
  });

  it('does not coerce singular and plural selectors into one shape', () => {
    importCards(structuredClone(STORED));
    const card = exportCards().nodes[0].card;
    expect(Array.isArray(card.group_by)).toBe(true); // plural -> array
    expect(Array.isArray(card.partition)).toBe(false); // singular -> object
  });

  it('adds and removes nodes', () => {
    addNode({ type: 'split' });
    expect(exportCards().nodes[0].card.type).toBe('split');
    expect(exportCards().nodes[0].id).toBeUndefined();
    addNode({ type: 'rescale' }, 'named');
    expect(exportCards().nodes[1].id).toBe('named');
    removeNode(0);
    expect(exportCards().nodes).toHaveLength(1);
    expect(exportCards().nodes[0].card.type).toBe('rescale');
  });

  it('exports a snapshot, not the reactive proxy', () => {
    importCards(structuredClone(STORED));
    const before = exportCards();
    setCardField(0, 'suffix', 'changed');
    expect(before.nodes[0].card.suffix).toBeUndefined();
  });
});

describe('getCards', () => {
  beforeEach(() => importCards(emptyCards()));

  it('returns the card half of the wire document, and nothing else', () => {
    importCards(structuredClone(STORED));
    const [state] = CARDS_STORE;
    const cards = getCards(state);
    // exactly the two keys evaluate-pipeline reads from this half
    expect(Object.keys(cards).sort()).toEqual(['groups', 'nodes']);
    expect(cards.nodes).toEqual(STORED.nodes);
    expect(cards.groups).toEqual(STORED.groups);
  });
});
