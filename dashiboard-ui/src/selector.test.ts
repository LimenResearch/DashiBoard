import { describe, it, expect } from 'vitest';
import { asItems, collapse, expand, documentText, type SelectorItem } from './selector';

const KINDS = ['cols', 'groups', 'nodes'];

describe('expand', () => {
  it('splits a multi-value item into one row per value', () => {
    // Case A ≡ B: `[{cols: ["PRES","TEMP"]}]` and two single-value items resolve identically, so
    // the picker is free to work in rows and write back whichever form is tidier.
    expect(expand([{ cols: ['PRES', 'TEMP'] }], KINDS)).toEqual([
      { kind: 'cols', value: 'PRES', chain: [] },
      { kind: 'cols', value: 'TEMP', chain: [] },
    ]);
  });

  it('carries the chain onto every row it came from', () => {
    expect(expand([{ cols: ['PRES', 'TEMP'], through: ['rescale'] }], KINDS)).toEqual([
      { kind: 'cols', value: 'PRES', chain: ['rescale'] },
      { kind: 'cols', value: 'TEMP', chain: ['rescale'] },
    ]);
  });

  it('reads a singular selector as one row, not as a string to iterate', () => {
    expect(expand([{ nodes: 'rescale' }], KINDS)).toEqual([
      { kind: 'nodes', value: 'rescale', chain: [] },
    ]);
  });
});

describe('collapse', () => {
  it('merges a consecutive run of the same kind and chain', () => {
    expect(
      collapse([
        { kind: 'cols', value: 'No', chain: [] },
        { kind: 'cols', value: 'year', chain: [] },
      ]),
    ).toEqual([{ cols: ['No', 'year'] }]);
  });

  it('writes a lone value as a bare string rather than a one-element array', () => {
    expect(collapse([{ kind: 'cols', value: 'No', chain: [] }])).toEqual([{ cols: 'No' }]);
  });

  it('keeps a differing chain apart — case C', () => {
    expect(
      collapse([
        { kind: 'cols', value: 'PRES', chain: ['rescale'] },
        { kind: 'cols', value: 'TEMP', chain: [] },
      ]),
    ).toEqual([{ cols: 'PRES', through: ['rescale'] }, { cols: 'TEMP' }]);
  });

  it('keeps the same value twice when it is qualified differently — case E', () => {
    // The case that rules out modelling a field as a set of values with attributes.
    expect(
      collapse([
        { kind: 'cols', value: 'PRES', chain: ['rescale'] },
        { kind: 'cols', value: 'PRES', chain: [] },
      ]),
    ).toEqual([{ cols: 'PRES', through: ['rescale'] }, { cols: 'PRES' }]);
  });

  it('will not merge across an intervening item, since that would reorder the field', () => {
    // Only *consecutive* runs coalesce. Merging the two `cols` runs here would move `No` and
    // `Iws` next to each other and silently change which column each positional weight lands on.
    expect(
      collapse([
        { kind: 'cols', value: 'No', chain: [] },
        { kind: 'groups', value: 'weather', chain: [] },
        { kind: 'cols', value: 'Iws', chain: [] },
      ]),
    ).toEqual([{ cols: 'No' }, { groups: 'weather' }, { cols: 'Iws' }]);
  });

  it('round-trips through expand without changing the document', () => {
    const original: SelectorItem[] = [
      { cols: ['PRES', 'TEMP'], through: ['rescale'] },
      { cols: 'PRES' },
      { groups: 'weather' },
    ];
    expect(collapse(expand(original, KINDS))).toEqual([
      { cols: ['PRES', 'TEMP'], through: ['rescale'] },
      { cols: 'PRES' },
      { groups: 'weather' },
    ]);
  });
});

describe('documentText', () => {
  it('writes the selector form, never a resolved column name', () => {
    // The UI writes the TOML; DashiBoard resolves it. `month_log` must never appear here — that
    // would be a second implementation of the suffix rule (06-design.md, A10 and amended C2).
    expect(
      documentText([
        { kind: 'cols', value: 'No', chain: [] },
        { kind: 'cols', value: 'year', chain: [] },
        { kind: 'cols', value: 'month', chain: ['log'] },
      ]),
    ).toBe('{cols = ["No", "year"]}, {cols = "month", through = "log"}');
  });

  it('writes a multi-node chain as an array, since order is part of the name', () => {
    expect(documentText([{ kind: 'cols', value: 'PRES', chain: ['rescale', 'log'] }])).toBe(
      '{cols = "PRES", through = ["rescale", "log"]}',
    );
  });

  it('says the field is empty rather than rendering nothing', () => {
    expect(documentText([])).toBe('[]');
  });
});

describe('asItems', () => {
  it('treats anything that is not a list as an empty field', () => {
    expect(asItems(undefined)).toEqual([]);
    expect(asItems('PRES')).toEqual([]);
    expect(asItems({ cols: 'PRES' })).toEqual([]);
  });
});
