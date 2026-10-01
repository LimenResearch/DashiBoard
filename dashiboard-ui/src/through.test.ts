import { describe, it, expect } from 'vitest';
import { throughOptions, toOutputs } from './through';
import type { ProbeNode, ThroughOption } from './stores';

const carries = (cols: string[], suffix: string | null, number: number | null = null): ThroughOption =>
  ({ cols, suffix, number });

const node = (id: string, outputs: string[], through: ThroughOption[] = []): ProbeNode =>
  ({ id, inputs: [], outputs, unproduced: [], through });

// `imp` renames what it is given; `zsc` only accepts what `imp` produced; `sp` accepts a different
// column; `pca` names its own outputs and so carries nothing.
const ALL = ['imp', 'zsc', 'sp', 'pca'];
const NODES = [
  node('imp', ['TEMP_imp', 'PRES_imp'], [carries(['TEMP', 'PRES'], 'imp')]),
  node('zsc', ['TEMP_imp_z'], [carries(['TEMP_imp'], 'z')]),
  node('sp', ['No_sp'], [carries(['No'], 'sp')]),
  node('pca', ['component_1'], []),
];
const GROUPS = { weather: [{ cols: ['TEMP', 'PRES'] }], odd: [{ cols: 'No', through: ['sp'] }] };

describe('toOutputs', () => {
  it('appends the suffix, and nothing when there is none', () => {
    expect(toOutputs(carries([], 'rescaled'), ['PRES'])).toEqual(['PRES_rescaled']);
    expect(toOutputs(carries([], null), ['PRES'])).toEqual(['PRES']);
  });

  // The same example `Pipelines` pins: a numbered encoding over one column.
  it('numbers the result when the rule says how many', () => {
    expect(toOutputs(carries([], 'gaussian', 3), ['date']))
      .toEqual(['date_gaussian_1', 'date_gaussian_2', 'date_gaussian_3']);
  });

  // The server broadcasts names against 1:number and flattens column-major, so the index is the
  // slower of the two. A UI that got this backwards would name real columns in the wrong order.
  it('varies the index slowest, as the server does', () => {
    expect(toOutputs(carries([], null, 2), ['a', 'b'])).toEqual(['a_1', 'b_1', 'a_2', 'b_2']);
  });
});

describe('throughOptions', () => {
  it('offers only the nodes that accept the column', () => {
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: [] }, ALL, NODES, GROUPS)).toEqual(['imp']);
    expect(throughOptions({ kind: 'cols', value: 'No', chain: [] }, ALL, NODES, GROUPS)).toEqual(['sp']);
  });

  // The rule that used to be guessed from which columns a node reads: `pca` reads `TEMP` but
  // names its own outputs, so nothing passes through it however the chain arrived.
  it('never offers a node that names its own outputs', () => {
    const reader = node('pca', ['component_1'], []);
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: [] }, ['pca'], [reader], {})).toEqual([]);
  });

  it('continues a chain with the nodes that accept what the last step produced', () => {
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: ['imp'] }, ALL, NODES, GROUPS)).toEqual(['zsc']);
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: ['imp', 'zsc'] }, ALL, NODES, GROUPS)).toEqual([]);
  });

  // A node does not accept what it writes, so a repeated node is refused by the rule itself
  // rather than by a separate check.
  it('never offers a node twice', () => {
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: ['imp'] }, ['imp'], NODES, GROUPS)).toEqual([]);
  });

  it('offers a group the nodes that accept its plain columns', () => {
    expect(throughOptions({ kind: 'groups', value: 'weather', chain: [] }, ALL, NODES, GROUPS)).toEqual(['imp']);
  });

  // A node's value is *all* of its outputs, so a step must accept every one of them. The rule this
  // replaced asked only whether some node read something the value carried, and so offered `zsc`
  // here — while the pipeline refuses the chain, because `PRES_imp` cannot pass through `zsc` too.
  it('requires a step to accept every column the value carries', () => {
    expect(throughOptions({ kind: 'nodes', value: 'imp', chain: [] }, ALL, NODES, GROUPS)).toEqual([]);
    const wide = [NODES[0], node('zsc', [], [carries(['TEMP_imp', 'PRES_imp'], 'z')])];
    expect(throughOptions({ kind: 'nodes', value: 'imp', chain: [] }, ['zsc'], wide, {})).toEqual(['zsc']);
  });

  it('offers everything while the server has not described the nodes, or the value is unknown to it', () => {
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: [] }, ALL, [], GROUPS)).toEqual(ALL);
    expect(throughOptions({ kind: 'nodes', value: 'ghost', chain: [] }, ALL, NODES, GROUPS)).toEqual(ALL);
    expect(throughOptions({ kind: 'groups', value: 'odd', chain: [] }, ALL, NODES, GROUPS)).toEqual(ALL);
  });

  it('keeps the order of the vocabulary it was given', () => {
    const both = [node('a', [], [carries(['T'], 'a')]), node('b', [], [carries(['T'], 'b')])];
    expect(throughOptions({ kind: 'cols', value: 'T', chain: [] }, ['b', 'a'], both, {})).toEqual(['b', 'a']);
  });
});
