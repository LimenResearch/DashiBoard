import { describe, it, expect } from 'vitest';
import { checkGroup, checkNode, checkFields, type Incompleteness } from './completeness';
import type { Defs, IRNode } from './ir';
import payload from './fixtures/card-ir.json';

const defs = payload.defs as Defs;
const cards = payload.cards as Record<string, IRNode>;

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

  it('says nothing about the card itself — that is `checkFields`\' question', () => {
    // `checkNode` asks one thing: can anything refer to this node. The card's own unanswered
    // fields are a separate walk over the IR, so a named card with an empty body passes here and
    // is caught there. Both run on Confirm; keeping them apart is what lets the id rule apply to
    // a card type this UI has never seen.
    expect(checkNode({ id: 'rescale', card: { type: 'rescale' } })).toEqual([]);
  });
});

// --- checkFields ---------------------------------------------------------------------------

describe('checkFields', () => {
  const cluster = cards.cluster;
  const rescale = cards.rescale;
  const at = (f: Incompleteness) => f.pointer;

  it('names every unanswered required field on an empty card, not just the first', () => {
    // The motivating case. A cluster card with nothing filled in is missing two things, and the
    // author should see both at once — see the module docstring for why the server cannot say so.
    const found = checkFields(cluster, defs, { type: 'cluster' }, '/nodes/0/card');
    expect(found.map(at)).toEqual(['/nodes/0/card/method', '/nodes/0/card/inputs']);
    // Pinned as strings because they are what the author reads, rendered after the field path:
    //   method — choose one of: dbscan, affinity_propagation, kmeans
    //   inputs — select at least one
    expect(found.map((f) => f.message)).toEqual([
      'choose one of: dbscan, affinity_propagation, kmeans',
      'select at least one',
    ]);
  });

  it('offers the choice instead of only naming the field', () => {
    const found = checkFields(cluster, defs, { type: 'cluster' }, '/nodes/0/card');
    expect(found[0].message).toBe('choose one of: dbscan, affinity_propagation, kmeans');
  });

  it('descends into the chosen branch and names what it still needs', () => {
    // Exactly what `defaultsFor` writes when dbscan is picked. `radius` is the one required field
    // dbscan declares no default for, so it is the only thing left to answer — and the pointer
    // addresses it inside `method`, which is where the control is drawn.
    const card = {
      type: 'cluster',
      method: {
        type: 'dbscan',
        dissimilarity: { type: 'euclidean' },
        min_neighbors: 1,
        min_cluster_size: 1,
      },
      inputs: [{ cols: 'TEMP' }],
    };
    const found = checkFields(cluster, defs, card, '/nodes/0/card');
    expect(found.map(at)).toEqual(['/nodes/0/card/method/radius']);
    expect(found[0].message).toBe('needs a number');
  });

  it('says nothing about a card whose required fields are all answered', () => {
    const card = {
      type: 'cluster',
      method: { type: 'dbscan', radius: 0.5, dissimilarity: { type: 'euclidean' } },
      inputs: [{ cols: 'TEMP' }],
    };
    expect(checkFields(cluster, defs, card, '/nodes/0/card')).toEqual([]);
  });

  it('objects to a present-but-empty list only when the IR sets a minimum', () => {
    // The boundary, and it is read from the IR rather than decided here: cluster's `inputs` is
    // `$defs/nonempty_variables` (minItems 1), rescale's is `$defs/variables` (no minimum). So
    // `inputs: []` is unfinished on one card and accepted on the other, and a rule of our own
    // invention — "a required list may not be empty" — would have been wrong about rescale.
    const clusterFound = checkFields(
      cluster, defs, { type: 'cluster', method: { type: 'kmeans', classes: 3 }, inputs: [] },
      '/nodes/0/card',
    );
    expect(clusterFound.map(at)).toEqual(['/nodes/0/card/inputs']);
    expect(clusterFound[0].message).toBe('select at least one');

    const rescaleFound = checkFields(
      rescale, defs, { type: 'rescale', method: { type: 'log' }, inputs: [] }, '/nodes/0/card',
    );
    expect(rescaleFound).toEqual([]);
  });

  it('treats an absent required list as unanswered even with no minimum', () => {
    // `required` is about the key existing. A fresh rescale card carries no `inputs` at all,
    // because the IR declares no default for it, and that is what the server rejects.
    const found = checkFields(rescale, defs, { type: 'rescale', method: { type: 'log' } }, '/nodes/0/card');
    expect(found.map(at)).toEqual(['/nodes/0/card/inputs']);
  });

  it('leaves optional fields alone, however empty', () => {
    // `suffix: ''` actually violates `minLength: 1`, and the server says so. That is the division
    // on purpose: this walk answers "did anyone fill it in", and an optional field left blank was
    // filled in with blank. Validity stays the server's.

    const card = {
      type: 'rescale',
      method: { type: 'log' },
      inputs: [{ cols: 'TEMP' }],
      targets: [],
      suffix: '',
    };
    expect(checkFields(rescale, defs, card, '/nodes/0/card')).toEqual([]);
  });

  it('says nothing about a field the IR does not describe', () => {
    // `ArrayIR{Any}()` serialises its items as `{}` — glm's formula. There is no way to know
    // whether such a field is answered, and guessing is how a check starts arguing with the user.
    const node: IRNode = {
      type: 'object',
      properties: [{ key: 'formula', required: true, value: {} }],
    };
    expect(checkFields(node, defs, {}, '/nodes/0/card')).toEqual([]);
  });

  it('escapes a pointer segment, so an odd field name still addresses one field', () => {
    const node: IRNode = {
      type: 'object',
      properties: [{ key: 'a/b~c', required: true, value: { type: 'string', minLength: 1 } }],
    };
    expect(checkFields(node, defs, {}, '/nodes/0/card')[0].pointer).toBe('/nodes/0/card/a~1b~0c');
  });

  it('reports an empty string only where the IR sets a minimum length', () => {
    const node: IRNode = {
      type: 'object',
      properties: [
        { key: 'strict', required: true, value: { type: 'string', minLength: 1 } },
        { key: 'loose', required: true, value: { type: 'string' } },
      ],
    };
    const found = checkFields(node, defs, { strict: '', loose: '' }, '/nodes/0/card');
    expect(found.map(at)).toEqual(['/nodes/0/card/strict']);
  });
});
