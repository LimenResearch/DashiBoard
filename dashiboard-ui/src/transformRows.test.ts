import { describe, it, expect } from 'vitest';
import { plainColumns, pruneMap, transformRows } from './transformRows';

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
  it('falls back to the plain columns before that, and calls nothing stale', () => {
    expect(transformRows(null, ['B'], { GONE: 'log' })).toEqual({ live: ['B'], stale: [] });
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
