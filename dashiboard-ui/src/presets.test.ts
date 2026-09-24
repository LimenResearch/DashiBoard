import { describe, it, expect } from 'vitest';
import { presetFields } from './presets';
import { widgetFor, type Defs, type IRNode } from './ir';
import payload from './fixtures/card-ir.json';

const defs = payload.defs as Defs;
const cards = payload.cards as unknown as { [type: string]: IRNode };

describe('presetFields', () => {
  it('offers the selector fields at least two card types share, most shared first', () => {
    expect(presetFields(cards, defs).map((f) => [f.key, f.single]))
      .toEqual([['partition', true], ['group_by', false], ['order_by', false], ['weights', true]]);
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
