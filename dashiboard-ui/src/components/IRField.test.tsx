import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup } from '@solidjs/testing-library';
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
    expect(kinds).toEqual(['cols', 'groups', 'nodes']); // display order, not the oneOf's
    const values = [...container.querySelectorAll('[data-value]')].map((e) =>
      e.getAttribute('data-value'),
    );
    expect(values).toContain('TEMP');
    expect(values).toContain('cbwd');
    // each value carries a switch, because it holds a *list* of qualifications rather than a flag
    expect(container.querySelectorAll('[role=switch]').length).toBe(values.length);
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
});
