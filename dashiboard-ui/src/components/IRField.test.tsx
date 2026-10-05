import { describe, it, expect, afterEach, vi } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { IRField } from './IRField';
import { defaultsFor, type Defs, type IRNode } from '../ir';
import payload from '../fixtures/card-ir.json';

const defs = payload.defs as Defs;
const cards = payload.cards as Record<string, IRNode>;

afterEach(cleanup);

describe('IRField', () => {
  it('renders one labelled control per property, in declaration order', () => {
    const node: IRNode = {
      type: 'object',
      title: 'Rescale',
      properties: [
        { key: 'suffix', required: true, value: { type: 'string', minLength: 1 } },
        { key: 'target_suffix', required: false, value: { type: 'string' } },
      ],
    };
    const { container } = render(() => (
      <IRField node={node} defs={defs} label="rescale" value={{}} onChange={() => {}} />
    ));
    // exact, not substring: 'target_suffix' contains 'suffix', so a substring check would
    // pass even with the order reversed.
    const labels = [...container.querySelectorAll('label')].map((l) => l.textContent ?? '');
    expect(labels).toEqual(['suffix*', 'target_suffix']);
    // The marker follows the name rather than leading it — an annotation on the field, not the
    // first character of its label. Asserted because it is the kind of thing a later tidy moves
    // back without noticing it was a decision.
    expect(labels[0].startsWith('*')).toBe(false);
    expect(labels[0].endsWith('*')).toBe(true);
  });

  it('passes numeric bounds through to the input', () => {
    const node: IRNode = { type: 'number', minimum: 0, maximum: 1 };
    const { container } = render(() => (
      <IRField node={node} defs={defs} label="percentile" value={0.5} onChange={() => {}} />
    ));
    const input = container.querySelector('input') as HTMLInputElement;
    expect(input.type).toBe('number');
    expect(input.min).toBe('0');
    expect(input.max).toBe('1');
  });

  it('reports a text edit as a string', () => {
    let seen: unknown = null;
    const { container } = render(() => (
      <IRField
        node={{ type: 'string' }} defs={defs} label="suffix"
        value="hat" onChange={(v) => { seen = v; }}
      />
    ));
    const input = container.querySelector('input') as HTMLInputElement;
    input.value = 'zscored';
    input.dispatchEvent(new Event('change', { bubbles: true }));
    expect(seen).toBe('zscored');
  });

  it('reports a numeric enum choice as a number, not a string', () => {
    // IntegerIR(enum = [1, 2]) on the tiles card: the document must carry 1, not "1".
    let seen: unknown = null;
    const { container } = render(() => (
      <IRField
        node={{ type: 'integer', enum: [1, 2] }} defs={defs} label="tiles"
        value={1} onChange={(v) => { seen = v; }}
      />
    ));
    const select = container.querySelector('select') as HTMLSelectElement;
    select.value = '2';
    select.dispatchEvent(new Event('change', { bubbles: true }));
    expect(seen).toBe(2);
    expect(typeof seen).toBe('number');
  });

  it('renders a variables reference as the selector picker, not a flat list', () => {
    const { container } = render(() => (
      <IRField
        node={{ $ref: '#/$defs/variables' }} defs={defs} label="inputs"
        value={[]} onChange={() => {}}
      />
    ));
    // A tab per selector kind, and the open one lists its vocabulary a value at a time.
    const kinds = [...container.querySelectorAll('[role=tab]')].map((e) =>
      e.getAttribute('data-tab'),
    );
    expect(kinds).toEqual(['nodes', 'groups', 'cols']); // display order, not the oneOf's
    const values = [...container.querySelectorAll('[data-value]')].map((e) =>
      e.getAttribute('data-value'),
    );
    // The open tab is `nodes`, the first with something to offer; it lists that vocabulary.
    expect(values).toEqual(['rescale', 'split']);
    // each value carries a switch, because it holds a *list* of qualifications rather than a flag
    expect(container.querySelectorAll('[data-name]').length).toBe(values.length);
  });

  it('shows only the chosen variant subform', () => {
    const method = (cards.split as { properties: { key: string; value: IRNode }[] })
      .properties.find((p) => p.key === 'method')!.value;
    const { container } = render(() => (
      <IRField
        node={method} defs={defs} label="method"
        value={{ type: 'percentile', percentile: 0.9 }} onChange={() => {}}
      />
    ));
    const labels = [...container.querySelectorAll('label')].map((l) => l.textContent ?? '');
    expect(labels.some((l) => l.includes('percentile'))).toBe(true);
    expect(labels.some((l) => l.includes('tiles'))).toBe(false); // the other branch stays hidden
  });

  it('carries the chosen branch\'s own defaults, not just its name', () => {
    // The bug this was written for: picking `dbscan` wrote `{type: "dbscan"}` and left
    // `dissimilarity` unset, even though Pipelines declares Euclidean as its default. The field
    // then rendered `choose…` for something the author had never been asked about.
    //
    // Read from the real IR rather than a hand-built node, because the first half of the fix was in
    // Julia — `IR_from_type` compared a default *instance* against a `Dict` of *types*, so
    // `default_option` came out `nothing` for every defaulted variant and no frontend change could
    // have recovered it.
    const method = (cards.cluster as { properties: { key: string; value: IRNode }[] })
      .properties.find((p) => p.key === 'method')!.value;
    let seen: unknown = null;
    const { container } = render(() => (
      <IRField
        node={method} defs={defs} label="method"
        value={{}} onChange={(v) => { seen = v; }}
      />
    ));
    const select = container.querySelector('select') as HTMLSelectElement;
    select.value = 'dbscan';
    select.dispatchEvent(new Event('change', { bubbles: true }));
    // All three kinds of declared default at once: `dissimilarity` from a `default_option`,
    // the two integers from a scalar `default`. `radius` is absent because dbscan declares no
    // default for it — which is the point of the distinction: what is left unset after this is
    // exactly what the author still has to answer.
    expect(seen).toEqual({
      type: 'dbscan',
      dissimilarity: { type: 'euclidean' },
      min_neighbors: 1,
      min_cluster_size: 1,
    });
    expect(seen).not.toHaveProperty('radius');
  });

  it('leaves a variant unchosen when the IR names no default', () => {
    // `cluster.method` itself has no `default_option`, so there is nothing to inherit and
    // guessing `options[0]` would pick whatever order a Julia `Dict` happened to have.
    const method = (cards.cluster as { properties: { key: string; value: IRNode }[] })
      .properties.find((p) => p.key === 'method')!.value;
    expect((method as { default_option?: string }).default_option).toBeUndefined();
    expect(defaultsFor(method, defs)).toBeUndefined();
  });

  it('draws a parameterless branch as nothing at all', () => {
    // `pca` is an object with no properties and `additionalProperties: false` — a method that
    // takes no settings. It was rendering as a second `method` disclosure, nested inside the
    // first, that opened onto nothing. 18 branches across rescale, window_function, cluster's
    // `dissimilarity` and this card are parameterless, so it was most of the form.
    const method = (cards.dimensionality_reduction as { properties: { key: string; value: IRNode }[] })
      .properties.find((p) => p.key === 'method')!.value;
    const { container } = render(() => (
      <IRField
        node={method} defs={defs} label="method"
        value={{ type: 'pca' }} onChange={() => {}}
      />
    ));
    // One disclosure — the variant's own. Nothing folds open onto an empty panel.
    expect(container.querySelectorAll('details')).toHaveLength(1);
    const summaries = [...container.querySelectorAll('summary')].map((e) => e.textContent);
    expect(summaries).toEqual(['method']);
    // And nothing *instead* of the fold either: `pca` is closed, so "takes no settings" is the
    // truth. Asserted because treating every empty object as undescribed would also leave one
    // disclosure standing, and would pass the two checks above while saying the wrong thing.
    expect(container.textContent).not.toMatch(/not described/i);
    expect(container.querySelectorAll('input, select')).toHaveLength(1); // the `type` chooser
  });

  it('puts a branch\'s fields at the variant\'s own level, not one deeper under a repeated name', () => {
    // The same defect with the branch non-empty: the fields were wrapped in a second disclosure
    // carrying the *same* label, so `radius` sat a level below `type` under a heading that said
    // `method` twice. Indentation is how this form conveys structure, so a level that means
    // nothing is a level that misleads.
    const method = (cards.cluster as { properties: { key: string; value: IRNode }[] })
      .properties.find((p) => p.key === 'method')!.value;
    const { container } = render(() => (
      <IRField
        node={method} defs={defs} label="method"
        value={{ type: 'dbscan', dissimilarity: { type: 'euclidean' } }} onChange={() => {}}
      />
    ));
    // `method` and `dissimilarity`, each once: the two things that actually fold.
    expect([...container.querySelectorAll('summary')].map((e) => e.textContent))
      .toEqual(['method', 'dissimilarity']);
    // `radius` is a sibling of the `type` row, inside the `method` disclosure.
    // `radius*` — required, and the marker is part of the label's text (see the first test).
    const radius = [...container.querySelectorAll('label')].find((l) => l.textContent === 'radius*')!;
    expect(radius.closest('details')).toBe(container.querySelector('details'));
  });

  it('says an open object is undescribed rather than drawing it as having no settings', () => {
    // `properties: []` means two different things, and the difference is `additionalProperties`.
    // Closed, it is a method that takes no settings — draw nothing. Open, as streamliner's
    // `model` and `training` are, the IR simply does not describe the field: the server accepts
    // arbitrary keys there and requires them. An empty fold would claim there is nothing to fill
    // in, which is the opposite of true.
    const { container } = render(() => (
      <IRField
        node={{ type: 'object', properties: [], additionalProperties: true }}
        defs={defs} label="model" value={undefined} onChange={() => {}}
      />
    ));
    expect(container.textContent).toMatch(/not described/i);
    expect(container.querySelector('details')).toBeNull();
  });

  it('says so plainly when the IR does not describe a field', () => {
    const { container } = render(() => (
      <IRField node={{}} defs={defs} label="inputs" value={null} onChange={() => {}} />
    ));
    expect(container.textContent).toMatch(/not described/i);
    expect(container.querySelector('input')).toBeNull(); // no textarea pretending otherwise
  });

  it('gives every control an id unique to its card', () => {
    // `id={props.label}` made two cards of one type produce duplicate ids, so a `<label for>`
    // in the second card focused the first card's input.
    const { container } = render(() => (
      <>
        <IRField node={cards.rescale} defs={defs} label="rescale" idPrefix="node-0" value={{}} onChange={() => {}} />
        <IRField node={cards.rescale} defs={defs} label="rescale" idPrefix="node-1" value={{}} onChange={() => {}} />
      </>
    ));
    const ids = [...container.querySelectorAll('[id]')].map((e) => e.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids).toContain('node-0-rescale-suffix');
    expect(ids).toContain('node-1-rescale-suffix');
    // and each label points at its own card's control
    const label = container.querySelector('label[for="node-1-rescale-suffix"]') as HTMLLabelElement;
    expect(label).not.toBeNull();
    expect(label.control?.id).toBe('node-1-rescale-suffix');
  });
});

// A lone `$defs/variable` property — `partition`, `weights`, `gaussian_encoding.input`,
// `interp.input` — had no case here, so the form drew nothing for it: two required fields could
// not be filled in at all, and the rest could not be set (measured 2026-09-17, ten fields across
// the fixture). Drawn as the same picker as `inputs`, holding one item.
describe('IRField, a lone selector', () => {
  const mountCard = (type: string, value: unknown, onChange: (v: unknown) => void = () => {}) =>
    render(() => (
      <IRField node={cards[type]} defs={defs} label={type} value={value} onChange={onChange} />
    ));
  const labels = (c: HTMLElement) =>
    [...c.querySelectorAll('label, summary, [data-selector-name]')].map((l) => (l.textContent ?? '').trim());

  it('draws rescale\'s partition, which the form used to leave out', () => {
    const { container } = mountCard('rescale', { type: 'rescale' });
    expect(labels(container).some((l) => l.startsWith('partition'))).toBe(true);
  });

  it('draws interp\'s input as required', () => {
    const { container } = mountCard('interp', { type: 'interp' });
    expect(labels(container)).toContain('input*');
  });

  it('writes the pick as one item under the property, and reads it back', async () => {
    let written: Record<string, unknown> | null = null;
    const { container } = mountCard('rescale', { type: 'rescale', suffix: 'z' }, (v) => { written = v as Record<string, unknown>; });
    // The partition picker is the one whose `writes` strip says nothing is set yet.
    const picker = [...container.querySelectorAll('[data-selector]')]
      .find((p) => p.querySelector('[data-selector-name]')!.textContent === 'partition')!;
    expect(picker).toBeDefined();
    fireEvent.click(picker.querySelector('[role=tab][data-tab="cols"]')!);
    await flush();
    fireEvent.click(picker.querySelector('[data-value="PRES"] [data-name]')!);
    await flush();
    expect(written).toEqual({ type: 'rescale', suffix: 'z', partition: { cols: 'PRES' } });

    cleanup();
    const back = mountCard('rescale', { type: 'rescale', partition: { cols: 'PRES', through: ['rescale'] } });
    // The chip says it, in the typed notation, with the panel folded.
    expect(back.container.querySelector('[data-chip="cols:PRES@rescale"]')).not.toBeNull();
  });
});

// One field's options depending on another's value: a streamliner's `select` offers the fields of
// the model chosen, and is not drawn while there is nothing to choose between.
describe('IRField, options that depend on a sibling', () => {
  const rule = (model: string, fields: string[]) => ({
    if: { properties: { model: { properties: { type: { const: model } } } }, required: ['model'] },
    then: { properties: { select: { items: { type: 'string', enum: fields } } } },
  });
  const branch = { type: 'object', properties: [], additionalProperties: false };
  const node: IRNode = {
    type: 'object',
    properties: [
      { key: 'model', required: true, value: { type: 'tagged_object', options: ['fuzzy', 'dense'], objects: { fuzzy: branch, dense: branch } } },
      { key: 'select', required: false, value: { type: 'array', items: { type: 'string', minLength: 1 }, minItems: 1 } },
    ],
    constraints: [rule('fuzzy', ['prediction', 'logvar']), rule('dense', ['prediction'])],
  };
  const mountWith = (value: unknown, onChange: (v: unknown) => void = () => {}) =>
    render(() => <IRField node={node} defs={defs} label="fit" idPrefix="n" value={value} onChange={onChange} />);
  // Every option is a pill, on or off: nothing to scroll, and what is taken reads at a glance.
  const pills = (c: HTMLElement) => [...c.querySelectorAll<HTMLButtonElement>('#n-fit-select [data-option]')];
  const taken = (c: HTMLElement) => pills(c).map((p) => p.getAttribute('aria-pressed') === 'true');

  it('offers the chosen model\'s fields, all taken while none is named', () => {
    const { container } = mountWith({ model: { type: 'fuzzy' } });
    expect(pills(container).map((p) => p.getAttribute('data-option'))).toEqual(['prediction', 'logvar']);
    expect(taken(container)).toEqual([true, true]);
  });

  it('shows what the document names', () => {
    const { container } = mountWith({ model: { type: 'fuzzy' }, select: ['logvar'] });
    expect(taken(container)).toEqual([false, true]);
  });

  it('draws nothing for a model with one field, or before a model is chosen', () => {
    expect(pills(mountWith({ model: { type: 'dense' } }).container)).toEqual([]);
    cleanup();
    expect(pills(mountWith({}).container)).toEqual([]);
  });

  // Left in place it would be refused by the server at a control the form no longer draws.
  it('drops a selection the newly chosen model cannot honour', async () => {
    let written: unknown = null;
    const { container } = mountWith({ model: { type: 'fuzzy' }, select: ['logvar'] }, (v) => { written = v; });
    const variant = container.querySelector('#n-fit-model-variant') as HTMLSelectElement;
    variant.value = 'dense';
    fireEvent.change(variant); await flush();
    expect(written).toEqual({ model: { type: 'dense' } });
  });

  it('keeps a selection the newly chosen model still has', async () => {
    let written: unknown = null;
    const { container } = mountWith({ model: { type: 'fuzzy' }, select: ['prediction'] }, (v) => { written = v; });
    const variant = container.querySelector('#n-fit-model-variant') as HTMLSelectElement;
    variant.value = 'dense';
    fireEvent.change(variant); await flush();
    expect(written).toEqual({ model: { type: 'dense' }, select: ['prediction'] });
  });

  it('writes an explicit list once the selection changes', async () => {
    let written: unknown = null;
    const { container } = mountWith({ model: { type: 'fuzzy' } }, (v) => { written = v; });
    fireEvent.click(pills(container)[0]); await flush();
    expect(written).toEqual({ model: { type: 'fuzzy' }, select: ['logvar'] });
  });

  // The order written is the order offered, whichever pill was pressed last.
  it('writes what is taken in the order it is offered', async () => {
    let written: unknown = null;
    const { container } = mountWith({ model: { type: 'fuzzy' }, select: ['logvar'] }, (v) => { written = v; });
    fireEvent.click(pills(container)[0]); await flush();
    expect(written).toEqual({ model: { type: 'fuzzy' }, select: ['prediction', 'logvar'] });
  });
});

describe('IRField, a variant with one option', () => {
  const branch = { type: 'object', properties: [{ key: 'width', required: true, value: { type: 'integer' } }], additionalProperties: false };
  const one: IRNode = { type: 'tagged_object', options: [''], objects: { '': branch }, default_option: '' };
  const two: IRNode = { type: 'tagged_object', options: ['', 'time'], objects: { '': branch, time: branch }, default_option: '' };
  const mountVariant = (node: IRNode, value: unknown, onChange: (v: unknown) => void = () => {}) =>
    render(() => <IRField node={node} defs={defs} label="funnel" idPrefix="n" value={value} onChange={onChange} />);

  it('draws the branch and no chooser', () => {
    const { container } = mountVariant(one, undefined);
    expect(container.querySelector('#n-funnel-variant')).toBeNull();
    expect(container.querySelector('#n-funnel-funnel-width')).not.toBeNull();
    expect(container.textContent).not.toMatch(/choose/);
  });

  it('writes the branch\'s fields without a type', async () => {
    let written: unknown = null;
    const { container } = mountVariant(one, undefined, (v) => { written = v; });
    const input = container.querySelector('#n-funnel-funnel-width') as HTMLInputElement;
    input.value = '3'; fireEvent.change(input); await flush();
    expect(written).toEqual({ width: 3 });
  });

  it('calls the blank option "default" when there is a choice, and draws its branch unasked', () => {
    const { container } = mountVariant(two, undefined);
    const chooser = container.querySelector('#n-funnel-variant') as HTMLSelectElement;
    expect([...chooser.options].map((o) => [o.value, o.textContent])).toEqual([['', 'default'], ['time', 'time']]);
    expect(chooser.className).not.toMatch(/border-warning/);
    expect(container.querySelector('#n-funnel-funnel-width')).not.toBeNull();
  });

  it('names another option when it is chosen, and the default by leaving the name out', async () => {
    let written: unknown = null;
    const { container } = mountVariant(two, { width: 2 }, (v) => { written = v; });
    const chooser = container.querySelector('#n-funnel-variant') as HTMLSelectElement;
    chooser.value = 'time'; fireEvent.change(chooser); await flush();
    expect(written).toEqual({ type: 'time' });
    cleanup();
    const again = mountVariant(two, { type: 'time', width: 2 }, (v) => { written = v; });
    const back = again.container.querySelector('#n-funnel-variant') as HTMLSelectElement;
    back.value = ''; fireEvent.change(back); await flush();
    expect(written).toEqual({});
  });

  // One option that takes no settings is nothing to show at all.
  it('draws nothing for a lone option with no fields', () => {
    const empty: IRNode = { type: 'tagged_object', options: [''], objects: { '': { type: 'object', properties: [], additionalProperties: false } }, default_option: '' };
    const { container } = render(() => <IRField node={empty} defs={defs} label="loader" idPrefix="n" value={undefined} onChange={() => {}} />);
    expect(container.textContent).toBe('');
  });

  // A document may name an option this server does not have. Hiding the chooser would hide the
  // only place that can be put right.
  it('shows the chooser, and the name, when the document names something else', async () => {
    let written: unknown = null;
    const { container } = mountVariant(one, { type: 'time', width: 2 }, (v) => { written = v; });
    const chooser = container.querySelector('#n-funnel-variant') as HTMLSelectElement;
    expect(chooser).not.toBeNull();
    expect(chooser.className).toMatch(/border-warning/);
    expect(chooser.selectedOptions[0].textContent).toMatch(/time/);
    expect(container.querySelector('#n-funnel-funnel-width')).toBeNull();
    chooser.value = ''; fireEvent.change(chooser); await flush();
    expect(written).toEqual({});
  });

  // A lone option that has to be named is asked for when a loaded value does not name it.
  it('asks for a lone option a loaded value does not name', () => {
    const named: IRNode = { type: 'tagged_object', options: ['batched'], objects: { batched: branch } };
    expect(mountVariant(named, undefined).container.querySelector('#n-funnel-variant')).toBeNull();
    cleanup();
    const { container } = mountVariant(named, { width: 1 });
    expect((container.querySelector('#n-funnel-variant') as HTMLSelectElement).className).toMatch(/border-warning/);
  });

  it('still asks when there is a choice and no default', () => {
    const open: IRNode = { type: 'tagged_object', options: ['a', 'b'], objects: { a: branch, b: branch } };
    const { container } = mountVariant(open, undefined);
    expect((container.querySelector('#n-funnel-variant') as HTMLSelectElement).className).toMatch(/border-warning/);
    expect(container.querySelector('#n-funnel-funnel-width')).toBeNull();
  });
});

describe('IRField, a field a sibling makes required', () => {
  const node: IRNode = {
    type: 'object',
    properties: [
      { key: 'inputs', required: false, value: { type: 'string' } },
      { key: 'loader', required: false, value: { type: 'tagged_object', options: ['', 'file'], objects: { '': { type: 'object', properties: [] }, file: { type: 'object', properties: [] } }, default_option: '' } },
    ],
    constraints: [{ if: { properties: { loader: { properties: { type: { const: '' } } } } }, then: { required: ['inputs'] } }],
  };
  const starred = (value: unknown) => {
    const { container } = render(() => <IRField node={node} defs={defs} label="funnel" idPrefix="n" value={value} onChange={() => {}} />);
    return container.querySelector('label[for="n-funnel-inputs"]')!.textContent!.includes('*');
  };
  it('marks it while the rule holds, and not otherwise', () => {
    expect(starred({})).toBe(true);
    cleanup();
    expect(starred({ loader: { type: 'file' } })).toBe(false);
  });
});

// A map field draws a row per column of the list it belongs to: what the server says the list
// resolves to, and what the author wrote plainly.
describe('IRField, a map beside its list', () => {
  const node: IRNode = {
    type: 'object',
    properties: [
      { key: 'inputs', required: false, value: { $ref: '#/$defs/variables' } },
      { key: 'input_transforms', required: false, value: { type: 'map', values: { type: 'string', enum: ['log', 'sqrt'] }, keys_from: 'inputs' } },
    ],
  };
  const rows = (c: HTMLElement) => [...c.querySelectorAll('[data-row]')].map((r) => r.getAttribute('data-row'));
  const mountMap = (value: unknown, extra: Record<string, unknown> = {}, onChange: (v: unknown) => void = () => {}) =>
    render(() => <IRField node={node} defs={defs} label="funnel" idPrefix="n" value={value} onChange={onChange} {...extra} />);

  it('lists what the server resolved', () => {
    const { container } = mountMap({ inputs: [{ groups: 'g' }] }, { listsFor: (name: string) => (name === 'inputs' ? ['TEMP', 'PRES'] : null) });
    expect(rows(container)).toEqual(['TEMP', 'PRES']);
  });

  it('lists the plain columns before the server has answered', () => {
    const { container } = mountMap({ inputs: [{ cols: ['TEMP'] }, { groups: 'g' }] });
    expect(rows(container)).toEqual(['TEMP']);
  });

  it('writes the choice into the map', async () => {
    let written: unknown = null;
    const value = { inputs: [{ cols: ['TEMP', 'PRES'] }] };
    const { container } = mountMap(value, {}, (v) => { written = v; });
    const control = container.querySelector('[data-row="PRES"] select') as HTMLSelectElement;
    control.value = 'log'; fireEvent.change(control); await flush();
    expect(written).toEqual({ ...value, input_transforms: { PRES: 'log' } });
  });

  it('shows no transform for a categorical column, and marks an entry the list has lost', () => {
    const { container } = mountMap(
      { inputs: [{ cols: 'TEMP' }], input_transforms: { GONE: 'log' } },
      { listsFor: () => ['TEMP', 'cbwd'], isCategorical: (column: string) => column === 'cbwd' },
    );
    expect(container.querySelector('[data-row="cbwd"] select')).toBeNull();
    expect(container.querySelector('[data-row="GONE"]')!.hasAttribute('data-stale')).toBe(true);
  });
});

// A variant whose options are files — a model, a training — is picked like a file, with the
// chosen file shown; its branch, the settings the file leaves open, is drawn as for any variant.
describe('IRField, a variant whose options are files', () => {
  const branch = { type: 'object', properties: [{ key: 'features', required: true, value: { type: 'integer' } }], additionalProperties: false };
  const node: IRNode = { type: 'tagged_object', options: ['dense', 'fuzzy'], objects: { dense: branch, fuzzy: branch }, options_from: 'model' };
  const texts = { dense: 'name = "basic"\n' };

  it('draws the picker with the file, and still writes the type and the branch', async () => {
    let written: unknown = null;
    const refresh = vi.fn();
    const { container } = render(() => (
      <IRField node={node} defs={defs} label="model" idPrefix="n" value={{ type: 'dense', features: 2 }} onChange={(v) => { written = v; }}
        configurationText={(kind, name) => (kind === 'model' ? texts[name as keyof typeof texts] ?? null : null)} refreshConfigurations={refresh} />
    ));
    expect(container.querySelector('details[data-configuration] pre')!.textContent).toBe(texts.dense);
    const features = container.querySelector('#n-model-model-features') as HTMLInputElement;
    features.value = '3'; fireEvent.change(features); await flush();
    expect(written).toEqual({ type: 'dense', features: 3 });
    const select = container.querySelector('#n-model-variant') as HTMLSelectElement;
    select.value = 'fuzzy'; fireEvent.change(select); await flush();
    expect(written).toEqual({ type: 'fuzzy' });
    fireEvent.click(container.querySelector('button[aria-label="refresh the model list"]')!);
    expect(refresh).toHaveBeenCalled();
  });

  // A configuration that leaves nothing open still has a file worth reading, and a list worth
  // refreshing: it is not "nothing to show" the way a lone option with no settings is.
  it('shows the lone file even when it leaves no setting open', () => {
    const bare = { type: 'object', properties: [], additionalProperties: false };
    const lone: IRNode = { type: 'tagged_object', options: ['fuzzy'], objects: { fuzzy: bare }, options_from: 'model' };
    const { container } = render(() => (
      <IRField node={lone} defs={defs} label="model" idPrefix="n" value={{ type: 'fuzzy' }} onChange={() => {}}
        configurationText={() => 'name = "fuzzy"\n'} />
    ));
    expect(container.querySelector('details[data-configuration] pre')!.textContent).toBe('name = "fuzzy"\n');
    expect(container.querySelector('button[aria-label="refresh the model list"]')).not.toBeNull();
  });

  it('shows the lone file without a chooser', () => {
    const lone: IRNode = { ...node, options: ['dense'], objects: { dense: branch } };
    const { container } = render(() => (
      <IRField node={lone} defs={defs} label="model" idPrefix="n" value={{ type: 'dense' }} onChange={() => {}}
        configurationText={() => texts.dense} />
    ));
    expect(container.querySelector('#n-model-variant')).toBeNull();
    expect(container.querySelector('details[data-configuration] pre')!.textContent).toBe(texts.dense);
  });
});
