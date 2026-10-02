import { describe, it, expect } from 'vitest';
import { plainColumns, pruneMap, refusedKeys, transformRows } from './transformRows';

describe('the rows of a transform map', () => {
  it('names the plain columns of a list', () => {
    expect(plainColumns([{ cols: ['A', 'B'] }, { groups: 'g' }, { cols: 'C', through: ['r'] }, { cols: 'D' }])).toEqual(['A', 'B', 'D']);
    expect(plainColumns(undefined)).toEqual([]);
  });
  it('follows the server once it has answered', () => {
    expect(transformRows(['A_z', 'B'], ['B'], { B: 'log' })).toEqual({ live: ['A_z', 'B'], stale: [] });
  });
  // A column just added by hand is not in the last answer yet, and still gets its row.
  it('adds a plain column the server has not seen yet', () => {
    expect(transformRows(['A_z'], ['B'], {})).toEqual({ live: ['A_z', 'B'], stale: [] });
  });
  // Unanswered, an entry cannot be called stale — but it is in the document, so it has a row
  // and can be put back to identity.
  it('falls back to the plain columns before that, with a row for whatever else is held', () => {
    expect(transformRows(null, ['B'], { A_z: 'log' })).toEqual({ live: ['B', 'A_z'], stale: [] });
  });
  // A document the server refuses for an entry is not described at all, so the refusal itself
  // is what says which entry is stale.
  it('sets apart an entry the server refused, answered or not', () => {
    expect(transformRows(null, ['B'], { B: 'log', GONE: 'sqrt' }, ['GONE'])).toEqual({ live: ['B'], stale: ['GONE'] });
    expect(transformRows(['B', 'GONE'], [], { GONE: 'sqrt' }, ['GONE'])).toEqual({ live: ['B'], stale: ['GONE'] });
  });
  it('sets apart an entry the list no longer reaches', () => {
    expect(transformRows(['B'], ['B'], { B: 'log', GONE: 'sqrt' })).toEqual({ live: ['B'], stale: ['GONE'] });
  });
});

describe('a column that leaves a list', () => {
  it('takes its entry with it', () => {
    expect(pruneMap({ A: 'log', B: 'sqrt' }, ['A', 'B'], ['A'])).toEqual({ A: 'log' });
  });
  it('leaves an entry for a column the list reaches some other way', () => {
    expect(pruneMap({ A_z: 'log' }, ['B'], [])).toEqual({ A_z: 'log' });
  });
  it('leaves no empty map behind', () => {
    expect(pruneMap({ B: 'sqrt' }, ['B'], [])).toBeUndefined();
    expect(pruneMap(undefined, ['B'], [])).toBeUndefined();
  });
});

describe('the entries the server refused', () => {
  const issue = (pointer: string, reason = 'transforms') => ({ pointer, reason });
  it('reads them off the pointers under one card\'s map', () => {
    const issues = [
      issue('/nodes/2/card/funnel/input_transforms/TEMP_z'),
      issue('/nodes/2/card/funnel/target_transforms/PRES'),
      issue('/nodes/1/card/funnel/input_transforms/OTHER'),
      issue('/nodes/2/card/funnel/input_transforms/a~1b'),
      issue('/nodes/2/card/funnel/input_transforms', 'enum'),
    ];
    expect(refusedKeys(issues, 2, 'input_transforms')).toEqual(['TEMP_z', 'a/b']);
    expect(refusedKeys(issues, 2, 'target_transforms')).toEqual(['PRES']);
    expect(refusedKeys(issues, 0, 'input_transforms')).toEqual([]);
  });
});
