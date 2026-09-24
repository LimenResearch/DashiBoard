import { describe, it, expect } from 'vitest';
import { throughOptions } from './through';
import type { ProbeNode } from './stores';

const node = (id: string, inputs: string[], outputs: string[]): ProbeNode => ({ id, inputs, outputs, unproduced: [] });
const ALL = ['imp', 'zsc', 'sp', 'other'];
const NODES = [
  node('imp', ['TEMP', 'PRES'], ['TEMP_imp', 'PRES_imp']),
  node('zsc', ['TEMP_imp'], ['TEMP_imp_z']),
  node('sp', ['No'], ['No_sp']),
  node('other', ['x'], ['y']),
];
const GROUPS = { weather: [{ cols: ['TEMP', 'PRES'] }], odd: [{ cols: 'No', through: ['sp'] }] };

describe('throughOptions', () => {
  it('offers a column only the nodes that read it', () => {
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: [] }, ALL, NODES, GROUPS)).toEqual(['imp']);
    expect(throughOptions({ kind: 'cols', value: 'No', chain: [] }, ALL, NODES, GROUPS)).toEqual(['sp']);
  });

  it('continues a chain with the nodes that read what the last step produced', () => {
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: ['imp'] }, ALL, NODES, GROUPS)).toEqual(['zsc']);
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: ['imp', 'zsc'] }, ALL, NODES, GROUPS)).toEqual([]);
  });

  it('offers a group the nodes that read one of its plain columns, and a node those that read its outputs', () => {
    expect(throughOptions({ kind: 'groups', value: 'weather', chain: [] }, ALL, NODES, GROUPS)).toEqual(['imp']);
    expect(throughOptions({ kind: 'nodes', value: 'imp', chain: [] }, ALL, NODES, GROUPS)).toEqual(['zsc']);
  });

  it('offers everything while the server has not described the nodes, or the value is unknown to it', () => {
    expect(throughOptions({ kind: 'cols', value: 'TEMP', chain: [] }, ALL, [], GROUPS)).toEqual(ALL);
    expect(throughOptions({ kind: 'nodes', value: 'ghost', chain: [] }, ALL, NODES, GROUPS)).toEqual(ALL);
    expect(throughOptions({ kind: 'groups', value: 'odd', chain: [] }, ALL, NODES, GROUPS)).toEqual(ALL);
  });

  it('keeps the order of the vocabulary it was given', () => {
    const both = [node('a', ['T'], []), node('b', ['T'], [])];
    expect(throughOptions({ kind: 'cols', value: 'T', chain: [] }, ['b', 'a'], both, {})).toEqual(['b', 'a']);
  });

  it('never offers a node the chain already passes through', () => {
    const loop = [node('a', ['T', 'T_a'], ['T_a']), node('b', ['T_a'], ['T_a_b'])];
    expect(throughOptions({ kind: 'cols', value: 'T', chain: ['a'] }, ['a', 'b'], loop, {})).toEqual(['b']);
    expect(throughOptions({ kind: 'cols', value: 'T', chain: ['a'] }, ['a', 'b'], [], {})).toEqual(['b']);
  });
});
