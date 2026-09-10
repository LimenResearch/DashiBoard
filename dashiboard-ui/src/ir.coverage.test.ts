import { describe, it, expect } from 'vitest';
import { widgetFor, resolveRef, type Defs, type IRNode, type Widget } from './ir';
import payload from './fixtures/card-ir.json';

// A contract test between the Julia IR and this renderer. The fixture is the real payload
// POST /get-card-ir serves for the ten registered cards; regenerate it with
//   julia --project=Pipelines/test  (see the dump in the commit message)
// If Julia starts emitting a node type this mapping does not handle, this fails rather than
// silently rendering nothing. Decisions section 13 calls this seam the one most likely to be
// got wrong.

const defs = payload.defs as Defs;
const cards = payload.cards as Record<string, IRNode>;

/** Every node this renderer would actually be asked to draw. */
function renderTargets(node: IRNode, out: IRNode[] = []): IRNode[] {
  out.push(node);
  const w: Widget = widgetFor(node, defs);
  if (w.kind === 'object') {
    for (const p of w.properties) renderTargets(p.value, out);
  } else if (w.kind === 'variant') {
    for (const option of Object.values(w.objects)) renderTargets(option, out);
  } else if (w.kind === 'repeater') {
    renderTargets(w.items, out);
  }
  return out;
}

describe('the mapping covers the IR Julia actually serves', () => {
  it('sees all ten registered cards', () => {
    expect(Object.keys(cards)).toHaveLength(10);
  });

  it('maps every card to an object with a human title', () => {
    for (const [key, card] of Object.entries(cards)) {
      const w = widgetFor(card, defs);
      expect(w.kind, key).toBe('object');
      if (w.kind !== 'object') throw new Error('unreachable');
      expect(typeof w.title, key).toBe('string');
      expect(w.properties.length, key).toBeGreaterThan(0);
    }
  });

  it('leaves nothing unmapped except genuinely unconstrained nodes', () => {
    const unknown: string[] = [];
    for (const [key, card] of Object.entries(cards)) {
      for (const node of renderTargets(card)) {
        if (widgetFor(node, defs).kind !== 'unknown') continue;
        // The only acceptable `unknown` is a node the IR does not constrain at all, i.e. `{}`.
        // A node carrying a `type` we do not handle is a gap, and names itself here.
        expect(Object.keys(resolveRef(node, defs)), `${key}: ${JSON.stringify(node)}`).toEqual([]);
        unknown.push(key);
      }
    }
    // glm and mixed_model formulas use ArrayIR{Any}(), whose items serialise as {}. mixed_model
    // is not registered by default, so glm is the only one here — and Pipelines carries a
    // "make more specific" TODO for exactly this.
    expect([...new Set(unknown)]).toEqual(['glm']);
  });

  it('resolves a variables field to a repeater over selectors', () => {
    // The group dialect: a field is an ordered list of selector *items*, not a flat list of
    // column names. The columns are one kind's vocabulary inside the item.
    const w = widgetFor({ $ref: '#/$defs/variables' }, defs);
    expect(w.kind).toBe('repeater');
    if (w.kind !== 'repeater') throw new Error('unreachable');
    const item = widgetFor(w.items, defs);
    expect(item.kind).toBe('selector');
    if (item.kind !== 'selector') throw new Error('unreachable');
    expect(item.kinds).toEqual(['nodes', 'groups', 'cols']);
    expect(item.options.cols).toContain('TEMP');
    expect(item.options.cols).toContain('cbwd');
  });

  it('finds the split card variant selector the exercise started from', () => {
    const w = widgetFor(cards.split, defs);
    if (w.kind !== 'object') throw new Error('unreachable');
    const method = w.properties.find((p) => p.key === 'method');
    expect(method).toBeDefined();
    const inner = widgetFor(method!.value, defs);
    expect(inner.kind).toBe('variant');
    if (inner.kind !== 'variant') throw new Error('unreachable');
    expect(inner.options.sort()).toEqual(['percentile', 'tiles']);
  });
});
