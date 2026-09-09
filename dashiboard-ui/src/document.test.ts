import { describe, it, expect, beforeEach } from 'vitest';
import {
  emptyConfig, importConfig, exportConfig,
  setCardField, setCard, addNode, removeNode,
} from './root';

// A document in the post-9bd6c28 group vocabulary: plural selectors are arrays,
// singular ones are objects, and a selector value may be a string or a list.
const STORED = {
  filters: [{ type: 'interval', col: 'TEMP', min: 0, max: 10 }],
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
  beforeEach(() => importConfig(emptyConfig()));

  it('starts empty', () => {
    expect(exportConfig()).toEqual({ filters: [], nodes: [], groups: {} });
  });

  it('round-trips a stored document verbatim', () => {
    importConfig(structuredClone(STORED));
    expect(exportConfig()).toEqual(STORED);
  });

  it('preserves top-level keys it does not understand', () => {
    // section 2: the saved document is the stored JSON, never a reconstruction. A future
    // `version` key must survive a UI that has never heard of it.
    const withExtra = { ...structuredClone(STORED), version: 'dashi/1', provenance: { by: 'x' } };
    importConfig(withExtra);
    expect(exportConfig()).toEqual(withExtra);
  });

  it('edits a card field in place and leaves the rest of the document identical', () => {
    importConfig(structuredClone(STORED));
    setCardField(0, 'suffix', 'zscored');

    const after = exportConfig();
    expect(after.nodes[0].card.suffix).toBe('zscored');
    expect(after.nodes[0].card.method).toEqual({ type: 'zscore' });
    expect(after.groups).toEqual(STORED.groups);
    expect(after.filters).toEqual(STORED.filters);
  });

  it('does not coerce singular and plural selectors into one shape', () => {
    importConfig(structuredClone(STORED));
    const card = exportConfig().nodes[0].card;
    expect(Array.isArray(card.group_by)).toBe(true); // plural -> array
    expect(Array.isArray(card.partition)).toBe(false); // singular -> object
  });

  it('adds and removes nodes', () => {
    addNode({ type: 'split', method: { type: 'percentile', percentile: 0.9 } });
    // read through exportConfig, not the proxy: an untracked index read on a Solid 2 store is
    // not the documented way to read the document as data.
    expect(exportConfig().nodes).toHaveLength(1);
    expect(exportConfig().nodes[0].card.type).toBe('split');
    expect(exportConfig().nodes[0].id).toBeUndefined();
    addNode({ type: 'rescale' }, 'named');
    expect(exportConfig().nodes[1].id).toBe('named');
    removeNode(0);
    expect(exportConfig().nodes).toHaveLength(1);
    expect(exportConfig().nodes[0].card.type).toBe('rescale');
  });

  it('replaces a whole card, which is what a form edit produces', () => {
    importConfig(structuredClone(STORED));
    setCard(0, { type: 'rescale', method: { type: 'log' }, suffix: 'logged' });
    const card = exportConfig().nodes[0].card;
    expect(card).toEqual({ type: 'rescale', method: { type: 'log' }, suffix: 'logged' });
    expect(exportConfig().nodes[0].id).toBe('rescale'); // the node wrapper survives
    expect(exportConfig().groups).toEqual(STORED.groups);
  });

  it('exports a plain object, not the reactive proxy', () => {
    importConfig(structuredClone(STORED));
    const a = exportConfig();
    setCardField(0, 'suffix', 'changed');
    expect(a.nodes[0].card.suffix).toBeUndefined(); // the earlier export is a snapshot
  });
});
