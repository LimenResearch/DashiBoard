import { describe, it, expect } from 'vitest';
import {
  carryShared,
  listText,
  parseList,
  conditionalOptions,
  defaultsFor,
  resolveRef,
  widgetFor,
  withoutOption,
  onlyOptions,
  type Defs,
  type IRNode,
} from './ir';
import payload from './fixtures/card-ir.json';

// Fixtures are the real shapes POST /get-card-ir serves, taken from an enumeration of
// every node the ten registered cards produce.
const defs: Defs = {
  variable: { type: 'string', enum: ['No', 'TEMP'] },
  variables: { type: 'array', default: [], items: { $ref: '#/$defs/variable' } },
  nonempty_variables: { type: 'array', minItems: 1, items: { $ref: '#/$defs/variable' } },
};

describe('resolveRef', () => {
  it('follows a $ref into $defs', () => {
    expect(resolveRef({ $ref: '#/$defs/variable' }, defs)).toEqual(defs.variable);
  });
  it('leaves a node without a $ref alone', () => {
    const node: IRNode = { type: 'string' };
    expect(resolveRef(node, defs)).toBe(node);
  });
  it('returns a typeless node for an unresolvable $ref rather than throwing', () => {
    expect(resolveRef({ $ref: '#/$defs/nope' }, defs)).toEqual({});
  });
});

describe('widgetFor', () => {
  it('maps a singular variable reference to a select over the column names', () => {
    expect(widgetFor({ $ref: '#/$defs/variable' }, defs)).toEqual({
      kind: 'select', options: ['No', 'TEMP'],
    });
  });

  it('maps a plural variable reference to a multiselect over the column names', () => {
    // this is the case the whole exercise started from: pick several of a known list
    expect(widgetFor({ $ref: '#/$defs/variables' }, defs)).toEqual({
      kind: 'multiselect', options: ['No', 'TEMP'], default: [],
    });
  });

  it('carries minItems from a nonempty plural reference', () => {
    expect(widgetFor({ $ref: '#/$defs/nonempty_variables' }, defs)).toEqual({
      kind: 'multiselect', options: ['No', 'TEMP'], minItems: 1,
    });
  });

  it('maps a bounded number', () => {
    expect(widgetFor({ type: 'number', minimum: 0, maximum: 1 }, defs)).toEqual({
      kind: 'number', integer: false, min: 0, max: 1,
    });
  });

  it('keeps exclusive bounds distinct from inclusive ones', () => {
    expect(widgetFor({ type: 'number', exclusiveMinimum: 0, default: 0.5 }, defs)).toEqual({
      kind: 'number', integer: false, exclusiveMin: 0, default: 0.5,
    });
  });

  it('maps an integer with an enum to a select, not a number field', () => {
    expect(widgetFor({ type: 'integer', enum: [1, 2] }, defs)).toEqual({
      kind: 'select', options: [1, 2],
    });
  });

  // Repeats are meant unless the list says it is a set.
  it('maps an array of enum-bearing integers to a list, and to a multiselect when it is a set', () => {
    expect(widgetFor(
      { type: 'array', minItems: 1, items: { type: 'integer', enum: [1, 2] } }, defs,
    )).toEqual({ kind: 'list', item: 'integer', options: [1, 2], minItems: 1 });
    expect(widgetFor(
      { type: 'array', minItems: 1, items: { type: 'integer', enum: [1, 2] }, uniqueItems: true }, defs,
    )).toEqual({ kind: 'multiselect', options: [1, 2], minItems: 1 });
  });

  it('maps a constrained string to text', () => {
    expect(widgetFor({ type: 'string', minLength: 1, default: 'hat' }, defs)).toEqual({
      kind: 'text', minLength: 1, default: 'hat',
    });
  });

  it('maps a tagged_object to a variant, keeping option order and the default', () => {
    const node: IRNode = {
      type: 'tagged_object',
      options: ['percentile', 'tiles'],
      default_option: 'percentile',
      objects: {
        percentile: { type: 'object', properties: [], additionalProperties: false, constraints: [] },
        tiles: { type: 'object', properties: [], additionalProperties: false, constraints: [] },
      },
    };
    const w = widgetFor(node, defs);
    expect(w.kind).toBe('variant');
    if (w.kind !== 'variant') throw new Error('unreachable');
    expect(w.options).toEqual(['percentile', 'tiles']);
    expect(w.default).toBe('percentile');
    expect(Object.keys(w.objects).sort()).toEqual(['percentile', 'tiles']);
  });

  it('maps an object to its ordered field entries', () => {
    const node: IRNode = {
      type: 'object',
      title: 'Rescale',
      additionalProperties: false,
      constraints: [],
      properties: [
        { key: 'method', required: true, value: { type: 'string' } },
        { key: 'suffix', required: false, value: { type: 'string', minLength: 1 } },
      ],
    };
    const w = widgetFor(node, defs);
    expect(w.kind).toBe('object');
    if (w.kind !== 'object') throw new Error('unreachable');
    expect(w.title).toBe('Rescale');
    expect(w.properties.map((p) => p.key)).toEqual(['method', 'suffix']);
    expect(w.properties.map((p) => p.required)).toEqual([true, false]);
  });

  it('maps an array of anything else to a repeater', () => {
    const items: IRNode = { type: 'object', properties: [] };
    expect(widgetFor({ type: 'array', items }, defs)).toEqual({ kind: 'repeater', items });
  });

  it('maps a boolean to a toggle', () => {
    // BooleanIR is in the IR vocabulary but no registered card has a Bool field yet, so this
    // does not appear in a served payload today. Covered so the switch stays exhaustive.
    expect(widgetFor({ type: 'boolean', default: true }, defs)).toEqual({
      kind: 'toggle', default: true,
    });
  });

  it('maps a typeless node to unknown rather than guessing', () => {
    // ArrayIR{Any}() serialises its items as {} -- glm and mixed_model formulas both do this,
    // and the Julia side carries a "make more specific" TODO for it.
    expect(widgetFor({}, defs)).toEqual({ kind: 'unknown' });
    expect(widgetFor({ type: 'array', items: {} }, defs)).toEqual({
      kind: 'repeater', items: {},
    });
  });
});

describe('the group dialect', () => {
  const gdefs: Defs = {
    col: { type: 'string', enum: ['No', 'TEMP'] },
    node: { type: 'string', enum: ['rescale'] },
    group: { type: 'string', enum: ['weather'] },
    variable: {
      type: 'object',
      additionalProperties: false,
      properties: [
        { key: 'nodes', required: false, value: { type: 'one_or_many', eltype: 'string', array: { type: 'array', items: { $ref: '#/$defs/node' } } } },
        { key: 'groups', required: false, value: { type: 'one_or_many', eltype: 'string', array: { type: 'array', items: { $ref: '#/$defs/group' } } } },
        { key: 'cols', required: false, value: { type: 'one_or_many', eltype: 'string', array: { type: 'array', items: { $ref: '#/$defs/col' } } } },
        { key: 'through', required: false, value: { type: 'array', default: [], items: { $ref: '#/$defs/node' } } },
      ],
      constraints: [{ oneOf: [{ required: ['nodes'] }, { required: ['groups'] }, { required: ['cols'] }] }],
    },
    variables: { type: 'array', items: { $ref: '#/$defs/variable' } },
  };

  it('maps one_or_many to a multiselect over the referenced enum', () => {
    const node = gdefs.variable.properties as { key: string; value: IRNode }[];
    const cols = node.find((p) => p.key === 'cols')!.value;
    expect(widgetFor(cols, gdefs)).toEqual({ kind: 'multiselect', options: ['No', 'TEMP'] });
  });

  it('recognises a selector object rather than four independent fields', () => {
    const w = widgetFor(gdefs.variable, gdefs);
    expect(w.kind).toBe('selector');
    if (w.kind !== 'selector') throw new Error('unreachable');
    // the kinds come from the oneOf inside the IR, so "exactly one" is data, not a convention
    expect(w.kinds).toEqual(['nodes', 'groups', 'cols']);
    expect(w.options.cols).toEqual(['No', 'TEMP']);
    expect(w.options.nodes).toEqual(['rescale']);
    expect(w.options.groups).toEqual(['weather']);
    // the chain control is a plain ordered list of nodes
    expect(widgetFor(w.through, gdefs)).toEqual({ kind: 'multiselect', options: ['rescale'], default: [] });
  });

  it('maps a variables field to a repeater over selectors', () => {
    const w = widgetFor({ $ref: '#/$defs/variables' }, gdefs);
    expect(w.kind).toBe('repeater');
    if (w.kind !== 'repeater') throw new Error('unreachable');
    expect(widgetFor(w.items, gdefs).kind).toBe('selector');
  });

  it('leaves an ordinary object alone', () => {
    const plain: IRNode = { type: 'object', properties: [], constraints: [] };
    expect(widgetFor(plain, gdefs).kind).toBe('object');
  });
});

describe('withoutOption', () => {
  const defs = {
    node: { type: 'string', enum: ['a', 'b', 'c'] },
    col: { type: 'string', enum: ['TEMP'] },
  } as Defs;

  it('drops one value from a vocabulary, leaving the rest of the defs alone', () => {
    const narrowed = withoutOption(defs, 'node', 'b');
    expect(narrowed.node.enum).toEqual(['a', 'c']);
    expect(narrowed.col).toBe(defs.col); // untouched, and not copied
    expect(defs.node.enum).toEqual(['a', 'b', 'c']); // the original is not mutated
  });

  it('is a no-op for a vocabulary that is absent or not an enum', () => {
    expect(withoutOption(defs, 'group', 'x')).toBe(defs);
    expect(withoutOption({ node: { type: 'object' } } as Defs, 'node', 'x').node.type).toBe('object');
  });
});

describe('defaultsFor', () => {
  const defs = {} as Defs;

  it('gives back a scalar default', () => {
    expect(defaultsFor({ type: 'string', default: 'rescaled' }, defs)).toBe('rescaled');
    expect(defaultsFor({ type: 'number', default: 0.5 }, defs)).toBe(0.5);
    expect(defaultsFor({ type: 'boolean', default: false }, defs)).toBe(false);
  });

  it('says nothing when a field has no default, rather than inventing one', () => {
    // A required field without a default is the user's to fill. Supplying a value here would make
    // an unanswered question look answered, which is the whole thing Confirm exists to catch.
    expect(defaultsFor({ type: 'string' }, defs)).toBeUndefined();
    expect(defaultsFor({ type: 'integer', minimum: 1 }, defs)).toBeUndefined();
  });

  it('collects an object from the properties that have one', () => {
    const node: IRNode = {
      type: 'object',
      properties: [
        { key: 'suffix', required: false, value: { type: 'string', default: 'rescaled' } },
        { key: 'inputs', required: true, value: { type: 'string' } },
      ],
    };
    expect(defaultsFor(node, defs)).toEqual({ suffix: 'rescaled' });
  });

  it('takes a variant only when the IR names a default option', () => {
    const withDefault: IRNode = {
      type: 'tagged_object',
      options: ['identity', 'dayofyear'],
      default_option: 'identity',
      objects: {
        identity: {
          type: 'object',
          properties: [{ key: 'max', required: false, value: { type: 'number', default: 1 } }],
        },
      },
    };
    expect(defaultsFor(withDefault, defs)).toEqual({ type: 'identity', max: 1 });
  });

  it('leaves a variant unset when the IR names no default option', () => {
    // `options` arrives from a Julia Dict, so its order carries no intent. Picking the first would
    // assert a choice nobody made, and one that could differ between two runs of the server.
    const noDefault: IRNode = {
      type: 'tagged_object',
      options: ['maxabs', 'log', 'zscore'],
      objects: {},
    };
    expect(defaultsFor(noDefault, defs)).toBeUndefined();
  });

  it('returns nothing for an object whose properties all lack defaults', () => {
    const node: IRNode = {
      type: 'object',
      properties: [{ key: 'inputs', required: true, value: { type: 'string' } }],
    };
    expect(defaultsFor(node, defs)).toBeUndefined();
  });
});

describe('onlyOptions', () => {
  it('keeps the allowed names of one vocabulary, in its own order, and leaves the rest', () => {
    const defs = { node: { type: 'string', enum: ['a', 'b', 'c'] }, col: { type: 'string', enum: ['x'] } } as Defs;
    const cut = onlyOptions(defs, 'node', ['c', 'a', 'zz']);
    expect(cut.node.enum).toEqual(['a', 'c']);
    expect(cut.col).toBe(defs.col);
    expect(onlyOptions(defs, 'missing', ['a'])).toBe(defs);
  });
});

describe('options that depend on a sibling', () => {
  const rule = (model: string, fields: string[]) => ({
    if: { properties: { model: { properties: { type: { const: model } } } }, required: ['model'] },
    then: { properties: { select: { items: { type: 'string', enum: fields } } } },
  });
  const card = { type: 'object', constraints: [rule('fuzzy', ['prediction', 'logvar']), rule('dense', ['prediction'])] };

  it('reads the options the chosen sibling allows', () => {
    expect(conditionalOptions(card, 'select', { model: { type: 'fuzzy' } })).toEqual(['prediction', 'logvar']);
    expect(conditionalOptions(card, 'select', { model: { type: 'dense' } })).toEqual(['prediction']);
  });
  it('says when a rule exists and none applies yet, and when there is no rule at all', () => {
    expect(conditionalOptions(card, 'select', {})).toBeNull();
    expect(conditionalOptions(card, 'suffix', { model: { type: 'fuzzy' } })).toBeUndefined();
  });
  // The fixture's own streamliner card: every model there yields one field.
  it('reads the rules the server sends', () => {
    expect(conditionalOptions(payload.cards.streamliner as IRNode, 'select', { model: { type: 'dense' } })).toEqual(['prediction']);
  });
});

describe('the streamliner funnel, as served', () => {
  const funnel = (payload.cards.streamliner.properties as { key: string; value: IRNode }[])
    .find((p) => p.key === 'funnel')!.value;
  const branch = () => {
    const w = widgetFor(funnel, {});
    if (w.kind !== 'variant') throw new Error('not a variant');
    return w.objects[''];
  };
  it('is a choice of one, whose branch names its fields', () => {
    const w = widgetFor(funnel, {});
    expect(w.kind).toBe('variant');
    if (w.kind !== 'variant') return;
    expect(w.options).toEqual(['']);
    expect(w.default).toBe('');
    const keys = (branch().properties as { key: string }[]).map((p) => p.key);
    expect(keys).toEqual(['order_by', 'inputs', 'input_transforms', 'targets', 'target_transforms', 'input_paths', 'target_paths']);
  });
  it('reads a map field with the list its keys come from', () => {
    const map = (branch().properties as { key: string; value: IRNode }[]).find((p) => p.key === 'input_transforms')!.value;
    expect(widgetFor(map, {})).toEqual({ kind: 'map', values: ['asinh', 'log', 'log1p', 'sqrt'], keysFrom: 'inputs' });
  });
  // The blank name is the default: saying it would be writing `type = ""`.
  it('starts a card without naming the default funnel', () => {
    const defaults = defaultsFor(payload.cards.streamliner as IRNode, payload.defs as Defs) as Record<string, unknown>;
    expect(JSON.stringify(defaults)).not.toContain('"type":""');
    expect('funnel' in defaults).toBe(false);
  });
  // A lone option is not a question, so a new card starts with it taken — and named, since
  // the server has no default to fall back on.
  it('starts a card with a lone option that is not the default already chosen', () => {
    const defaults = defaultsFor(payload.cards.streamliner as IRNode, payload.defs as Defs) as Record<string, unknown>;
    expect(defaults.training).toEqual({ type: 'batched' });
    expect('model' in defaults).toBe(false);           // two models: the author's to choose
  });
  // Both lists are always asked for; a path column is there to be kept, not asked for.
  it('requires both lists and leaves the path columns optional', () => {
    const required = Object.fromEntries((branch().properties as { key: string; required: boolean }[]).map((p) => [p.key, p.required]));
    expect(required.inputs).toBe(true);
    expect(required.targets).toBe(true);
    expect(required.input_paths).toBe(false);
    expect(required.target_paths).toBe(false);
  });
});

describe('a variant whose options are files', () => {
  it('says where they come from, so a form can show the file behind a name', () => {
    const model = (payload.cards.streamliner.properties as { key: string; value: IRNode }[]).find((p) => p.key === 'model')!.value;
    const w = widgetFor(model, {});
    expect(w.kind).toBe('variant');
    if (w.kind !== 'variant') return;
    expect(w.optionsFrom).toBe('model');
    const plain = widgetFor({ type: 'tagged_object', options: ['a'], objects: { a: { type: 'object', properties: [] } } }, {});
    expect(plain.kind === 'variant' && plain.optionsFrom).toBeUndefined();
  });
});

// Choosing another option of a variant keeps what both branches declare, so switching a funnel to
// `time` does not throw away its `order_by`, its columns or their transforms.
describe('switching a variant', () => {
  const defs = payload.defs as Defs;
  const funnel = (payload.cards.streamliner.properties as { key: string; value: IRNode }[])
    .find((p) => p.key === 'funnel')!.value as { objects: { [o: string]: IRNode } };
  const plain = funnel.objects[''];
  const dispatcher = {
    key: 'dispatcher', required: true,
    value: { type: 'object', properties: [{ key: 'input', required: false, value: { type: 'integer', default: 1 } }] },
  };
  const time: IRNode = { ...plain, properties: [dispatcher, ...(plain.properties as unknown[])] };
  const filled = {
    order_by: [{ cols: 'id' }], inputs: [{ cols: 'TEMP' }], targets: [{ cols: 'PRES' }],
    input_transforms: { TEMP: 'log' },
  };

  it('keeps the fields both branches declare, and adds the new branch\'s defaults', () => {
    const next = carryShared(filled, time, defs);
    expect(next.order_by).toEqual([{ cols: 'id' }]);
    expect(next.inputs).toEqual([{ cols: 'TEMP' }]);
    expect(next.targets).toEqual([{ cols: 'PRES' }]);
    expect(next.input_transforms).toEqual({ TEMP: 'log' });
    expect(next.dispatcher).toEqual({ input: 1 });
  });

  it('drops the fields the new branch lacks', () => {
    const back = carryShared({ ...filled, dispatcher: { input: 5 } }, plain, defs);
    expect('dispatcher' in back).toBe(false);
    expect(back.order_by).toEqual([{ cols: 'id' }]);
  });

  it('carries nothing between branches that share no field', () => {
    const method = (payload.cards.split.properties as { key: string; value: IRNode }[])
      .find((p) => p.key === 'method')!.value as { objects: { [o: string]: IRNode } };
    const next = carryShared({ percentile: 0.3 }, method.objects.tiles, defs);
    expect('percentile' in next).toBe(false);
  });

  // A nested choice the new branch does not offer is not carried: kmeans offers `sqeuclidean`,
  // dbscan does not.
  it('does not carry a nested option the new branch lacks', () => {
    const method = (payload.cards.cluster.properties as { key: string; value: IRNode }[])
      .find((p) => p.key === 'method')!.value as { objects: { [o: string]: IRNode } };
    const kept = carryShared({ dissimilarity: { type: 'euclidean' } }, method.objects.dbscan, defs);
    expect(kept.dissimilarity).toEqual({ type: 'euclidean' });
    const dropped = carryShared({ dissimilarity: { type: 'sqeuclidean' } }, method.objects.dbscan, defs);
    expect((dropped.dissimilarity as { type?: string } | undefined)?.type).not.toBe('sqeuclidean');
  });

  it('does not carry a value the new branch would refuse', () => {
    const a: IRNode = { type: 'object', properties: [{ key: 'how', required: false, value: { type: 'string', enum: ['x', 'y'] } }] };
    const b: IRNode = { type: 'object', properties: [{ key: 'how', required: false, value: { type: 'string', enum: ['z'], default: 'z' } }] };
    expect(carryShared(carryShared({}, a, defs), b, defs).how).toBe('z');
    expect(carryShared({ how: 'x' }, b, defs).how).toBe('z');
    expect(carryShared({ how: 'x' }, a, defs).how).toBe('x');
  });
});

// A list of plain values is typed, comma-separated, unless the schema marks it a set.
describe('lists of values', () => {
  const defs = payload.defs as Defs;
  const prop = (card: IRNode, key: string) => (card.properties as { key: string; value: IRNode }[]).find((p) => p.key === key)!.value;
  const branch = (variant: IRNode, option: string) => (variant as { objects: { [o: string]: IRNode } }).objects[option];

  it('draws a sequence as a list, with the allowed values when there is a fixed set', () => {
    const tiles = prop(branch(prop(payload.cards.split as IRNode, 'method'), 'tiles'), 'tiles');
    expect(widgetFor(tiles, defs)).toEqual({ kind: 'list', item: 'integer', options: [1, 2], minItems: 1 });
    const weights = prop(branch(prop(branch(prop(payload.cards.cluster as IRNode, 'method'), 'kmeans'), 'dissimilarity'), 'weighted_euclidean'), 'weights');
    expect(widgetFor(weights, defs)).toMatchObject({ kind: 'list', item: 'number' });
    expect((widgetFor(weights, defs) as { options?: unknown }).options).toBeUndefined();
    expect(widgetFor(prop(payload.cards.trivial as IRNode, 'outputs'), defs)).toMatchObject({ kind: 'list', item: 'string' });
  });

  it('keeps a set as on/off choices', () => {
    expect(widgetFor(prop(payload.cards.streamliner as IRNode, 'select'), defs).kind).toBe('multiselect');
  });

  it('leaves selectors and untyped lists alone', () => {
    expect(widgetFor(prop(payload.cards.rescale as IRNode, 'inputs'), defs).kind).toBe('repeater');
    const formula = prop(payload.cards.glm as IRNode, 'formula');
    expect(widgetFor(prop(formula, 'inputs'), defs).kind).toBe('repeater');
  });

  it('reads values separated by commas, spaces ignored, numbers as numbers', () => {
    expect(parseList('1, 1 ,2', 'integer', [1, 2])).toEqual({ values: [1, 1, 2] });
    expect(parseList('1,0.5,  2', 'number')).toEqual({ values: [1, 0.5, 2] });
    expect(parseList(' score , rank ', 'string')).toEqual({ values: ['score', 'rank'] });
    expect(parseList('', 'integer', [1, 2])).toEqual({ values: [] });
  });

  it('says which value it cannot read', () => {
    expect(parseList('1, 1, 3', 'integer', [1, 2])).toEqual({ error: '3 is not one of 1, 2' });
    expect(parseList('1, x', 'number')).toEqual({ error: 'x is not a number' });
    expect(parseList('1, 1.5', 'integer')).toEqual({ error: '1.5 is not a whole number' });
    expect(parseList('a,,b', 'string')).toEqual({ error: 'a value is missing between two commas' });
    // A comma just typed is a value on its way, not a fault.
    expect(parseList('1, ', 'integer', [1, 2])).toEqual({ incomplete: true });
  });

  it('writes a list back as the box shows it', () => {
    expect(listText([1, 1, 2])).toBe('1, 1, 2');
    expect(listText(undefined)).toBe('');
  });
});
