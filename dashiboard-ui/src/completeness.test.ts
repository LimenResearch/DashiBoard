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

  it('leaves a missing required field alone, because the schema already says it', () => {
    // The boundary this module exists to hold. `method` is required on a rescale card, so
    // construction fails and the probe reports it against the field with a pointer. A rule here
    // would be a second source of truth for the schema.
    expect(checkNode({ id: 'rescale', card: { type: 'rescale' } })).toEqual([]);
  });
});
