import { describe, it, expect } from 'vitest';
import { groupsFor, throughOptions, toOutputs } from './through';
import type { ProbeNode, ThroughOption } from './stores';

const carries = (
  group: string | null, cols: string[], suffix: string | null, number: number | null = null,
): ThroughOption => ({ group, cols, suffix, number });

const node = (id: string, outputs: string[], through: ThroughOption[] = []): ProbeNode =>
  ({ id, inputs: [], outputs, unproduced: [], through });

// `imp` renames what it is given; `zsc` only accepts what `imp` produced; `sp` accepts a different
// column; `pca` names its own outputs and so carries nothing.
const ALL = ['imp', 'zsc', 'sp', 'pca'];
const NODES = [
  node('imp', ['TEMP_imp', 'PRES_imp'], [carries(null, ['TEMP', 'PRES'], 'imp')]),
  node('zsc', ['TEMP_imp_z'], [carries(null, ['TEMP_imp'], 'z')]),
  node('sp', ['No_sp'], [carries(null, ['No'], 'sp')]),
  node('pca', ['component_1'], []),
];
const GROUPS = { weather: [{ cols: ['TEMP', 'PRES'] }], odd: [{ cols: 'No', through: ['sp'] }] };

describe('toOutputs', () => {
  it('appends the suffix, and nothing when there is none', () => {
    expect(toOutputs(carries(null, [], 'rescaled'), ['PRES'])).toEqual(['PRES_rescaled']);
    expect(toOutputs(carries(null, [], null), ['PRES'])).toEqual(['PRES']);
  });

  // The same example `Pipelines` pins: a numbered encoding over one column.
  it('numbers the result when the rule says how many', () => {
    expect(toOutputs(carries(null, [], 'gaussian', 3), ['date']))
      .toEqual(['date_gaussian_1', 'date_gaussian_2', 'date_gaussian_3']);
  });

  // The server broadcasts names against 1:number and flattens column-major, so the index is the
  // slower of the two. A UI that got this backwards would name real columns in the wrong order.
  it('varies the index slowest, as the server does', () => {
    expect(toOutputs(carries(null, [], null, 2), ['a', 'b'])).toEqual(['a_1', 'b_1', 'a_2', 'b_2']);
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
    const wide = [NODES[0], node('zsc', [], [carries(null, ['TEMP_imp', 'PRES_imp'], 'z')])];
    expect(throughOptions({ kind: 'nodes', value: 'imp', chain: [] }, ['zsc'], wide, {})).toEqual(['zsc']);
  });

  it('offers everything while the server has not described the nodes, or the value is unknown to it', () => {
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: [] }, ALL, [], GROUPS)).toEqual(ALL);
    expect(throughOptions({ kind: 'nodes', value: 'ghost', chain: [] }, ALL, NODES, GROUPS)).toEqual(ALL);
    expect(throughOptions({ kind: 'groups', value: 'odd', chain: [] }, ALL, NODES, GROUPS)).toEqual(ALL);
  });

  // A document that does not build is described by nothing, so the picker falls back to the whole
  // vocabulary — which must still not include the node whose output is the value, since a node
  // cannot carry what it wrote.
  it('never offers a node as a step through itself, even with nothing described', () => {
    expect(throughOptions({ kind: 'nodes', value: 'imp', chain: [] }, ALL, [], GROUPS))
      .toEqual(['zsc', 'sp', 'pca']);
  });

  it('keeps the order of the vocabulary it was given', () => {
    const both = [node('a', [], [carries(null, ['T'], 'a')]), node('b', [], [carries(null, ['T'], 'b')])];
    expect(throughOptions({ kind: 'cols', value: 'T', chain: [] }, ['b', 'a'], both, {})).toEqual(['b', 'a']);
  });
});

describe('a node with several products', () => {
  const fit = node('fit', ['Iws_hat', 'Iws_logvar'], [
    carries('prediction', ['Iws'], 'hat'),
    carries('logvar', ['Iws'], 'logvar'),
  ]);
  const after = node('after', [], [carries(null, ['Iws_logvar'], 'z')]);
  const row = (chain: string[]) => ({ kind: 'cols', value: 'Iws', chain });

  it('is offered once, as the node: a bare step means every product', () => {
    expect(throughOptions(row([]), ['fit', 'after'], [fit, after], {})).toEqual(['fit']);
  });

  it('names the products a step may be narrowed to', () => {
    expect(groupsFor('fit', row([]), [fit, after], {})).toEqual(['prediction', 'logvar']);
    expect(groupsFor('fit|logvar', row([]), [fit, after], {})).toEqual(['prediction']);
    // One unnamed product leaves nothing to choose.
    expect(groupsFor('after', { kind: 'cols', value: 'Iws_logvar', chain: [] }, [fit, after], {})).toEqual([]);
  });

  // A bare `fit` hands on both columns, and `after` accepts only one of them.
  it('carries every product on, so the next step must accept them all', () => {
    expect(throughOptions(row(['fit']), ['fit', 'after'], [fit, after], {})).toEqual([]);
    expect(throughOptions(row(['fit|logvar']), ['fit', 'after'], [fit, after], {})).toEqual(['after']);
  });

  it('never offers a node again once a step through it names products', () => {
    expect(throughOptions(row(['fit|logvar']), ['fit'], [fit], {})).toEqual([]);
  });

  it('applies each product to every carried column in turn, as the server does', () => {
    const wide = node('fit', [], [carries('p', ['a', 'b'], 'hat'), carries('q', ['a', 'b'], 'lv')]);
    const next = node('n', [], [carries(null, ['a_hat', 'b_hat', 'a_lv', 'b_lv'], 'z')]);
    const groups = { g: [{ cols: ['a', 'b'] }] };
    // `a` alone comes out as a_hat and a_lv, which `n` accepts.
    expect(throughOptions({ kind: 'cols', value: 'a', chain: ['fit'] }, ['n'], [wide, next], groups)).toEqual(['n']);
    // The whole group comes out as all four, in the server's order, which `n` also accepts …
    expect(throughOptions({ kind: 'groups', value: 'g', chain: ['fit'] }, ['n'], [wide, next], groups)).toEqual(['n']);
    // … and a node that takes only the first product's columns does not.
    const narrow = node('n', [], [carries(null, ['a_hat', 'b_hat'], 'z')]);
    expect(throughOptions({ kind: 'groups', value: 'g', chain: ['fit'] }, ['n'], [wide, narrow], groups)).toEqual([]);
  });
});
