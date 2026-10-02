import { describe, it, expect } from 'vitest';
import { mergePresets, presetFields, presetsFor } from './presets';
import { widgetFor, type Defs, type IRNode } from './ir';
import payload from './fixtures/card-ir.json';

const defs = payload.defs as Defs;
const cards = payload.cards as unknown as { [type: string]: IRNode };

describe('presetFields', () => {
  it('offers the selector fields at least two card types share, most shared first', () => {
    expect(presetFields(cards, defs).map((f) => [f.key, f.single]))
      .toEqual([['partition', true], ['order_by', false], ['group_by', false], ['weights', true]]);
  });

  it('leaves out what a card operates on, however common', () => {
    const keys = presetFields(cards, defs).map((f) => f.key);
    for (const core of ['inputs', 'targets', 'input']) expect(keys).not.toContain(core);
  });

  it('leaves out fields that are not selectors', () => {
    const keys = presetFields(cards, defs).map((f) => f.key);
    for (const other of ['method', 'suffix', 'output', 'n_components', 'formula', 'outputs']) {
      expect(keys).not.toContain(other);
    }
  });

  it('leaves out a selector field only one card type has', () => {
    // A preset is for what cards share. No such field exists in today's IR, so this builds one.
    const selector: IRNode = { $ref: '#/$defs/variable' };
    const property = (key: string) => ({ key, value: selector, required: false });
    const card = (...keys: string[]) => ({ type: 'object', properties: keys.map(property) }) as IRNode;
    expect(presetFields({ a: card('shared', 'lonely'), b: card('shared') }, defs).map((f) => f.key))
      .toEqual(['shared']);
  });

  it('hands SelectorField the item node of the field, whichever shape it has', () => {
    // What `SelectorField` takes as `itemNode`: one selector item, whether the field is one
    // value or a list of them.
    for (const field of presetFields(cards, defs)) {
      expect([field.key, widgetFor(field.node, defs).kind]).toEqual([field.key, 'selector']);
    }
  });

  it('never reports a field as both one value and a list', () => {
    // A field of two shapes has no one shape to store. None today; a future one fails here.
    const shapes: Record<string, Set<boolean>> = {};
    for (const card of Object.values(cards)) {
      for (const p of (card.properties ?? []) as { key: string; value: IRNode }[]) {
        const two = { type: 'object', properties: [p] } as IRNode;
        const found = presetFields({ a: two, b: two }, defs);
        if (found.length === 0) continue;
        (shapes[p.key] ??= new Set()).add(found[0].single);
      }
    }
    for (const [key, kinds] of Object.entries(shapes)) expect([key, kinds.size]).toEqual([key, 1]);
  });
});

describe('a shared field inside a variant\'s branch', () => {
  const order = [{ cols: 'id' }];
  it('counts as the same field', () => {
    // Without the streamliner's funnel `order_by` is still shared; with it, by one type more.
    expect(presetFields(cards, defs).map((f) => f.key)).toContain('order_by');
    const top = { type: 'object', properties: [{ key: 'order_by', required: false, value: { $ref: '#/$defs/variables' } }] };
    const inside = { type: 'object', properties: [{ key: 'funnel', required: true, value: {
      type: 'tagged_object', options: [''], default_option: '', objects: { '': top },
    } }] };
    expect(presetFields({ a: top, b: inside }, defs).map((f) => f.key)).toEqual(['order_by']);
  });
  it('is filled where the card declares it', () => {
    const fields = presetFields(cards, defs);
    expect(presetsFor(fields, cards.split, { order_by: order }, defs)).toEqual({ order_by: order });
    expect(presetsFor(fields, cards.streamliner, { order_by: order }, defs)).toEqual({ funnel: { order_by: order } });
  });
  it('still leaves out what a card operates on, wherever it is', () => {
    expect(presetFields(cards, defs).map((f) => f.key)).not.toContain('inputs');
    expect(presetFields(cards, defs).map((f) => f.key)).not.toContain('targets');
  });
  it('is laid over the branch\'s own defaults, not in place of them', () => {
    const fields = presetFields(cards, defs);
    const preset = presetsFor(fields, cards.streamliner, { order_by: order, partition: { cols: 'p' } }, defs);
    expect(mergePresets({ suffix: 'hat', funnel: { row_number: '_r' } }, preset, fields))
      .toEqual({ suffix: 'hat', partition: { cols: 'p' }, funnel: { row_number: '_r', order_by: order } });
    // A field's own value replaces the default whole, even when it is an object.
    expect(mergePresets({ partition: { cols: 'old', through: ['r'] } }, { partition: { cols: 'p' } }, fields))
      .toEqual({ partition: { cols: 'p' } });
  });
});
