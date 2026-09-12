import { describe, it, expect } from 'vitest';
import raw from './card-ir.json';

// Invariants on the fixture *as a recording of the route*, not on the IR it happens to describe.
//
// Every other suite renders this file and so inherits whatever it says. A regeneration that drifts
// from `DashiBoard.get_card_ir` therefore moves the whole test suite off the payload the UI
// actually receives, silently — which is exactly what happened: a regeneration written as an inline
// Julia command dropped two things the route does, and the failures it produced pointed at
// `defaultsFor` and at the card-type list rather than at the fixture.
//
// `card-ir.regenerate.jl`, next to this file, is the only supported way to rewrite it.

const payload = raw as Record<string, unknown>;

describe('card-ir.json', () => {
  it('has no nulls, because the route omits them', () => {
    // `json_response(…; omit_null = true)`. In the IR `nothing` means "the type declares no
    // default", so a serialised `null` turns an *absence* into a present value: `defaultsFor` read
    // `default: null` as a default and gave a new card `{type: null}`.
    const nulls: string[] = [];
    const walk = (node: unknown, path: string) => {
      if (node === null) { nulls.push(path); return; }
      if (Array.isArray(node)) { node.forEach((v, i) => walk(v, `${path}/${i}`)); return; }
      if (typeof node === 'object') {
        for (const [k, v] of Object.entries(node as object)) walk(v, `${path}/${k}`);
      }
    };
    walk(payload, '');
    expect(nulls).toEqual([]);
  });

  it('describes every card type the test server registers', () => {
    // Ten, not nine: `trivial` is a `WildCard` the *host* registers (see
    // `DashiBoard/test/dashiboard.jl`), so a fixture generated from a bare Pipelines session is
    // missing the one card type that shows how a registered wild card renders.
    const cards = payload.cards as Record<string, unknown>;
    expect(Object.keys(cards)).toContain('trivial');
    expect(Object.keys(cards)).toHaveLength(10);
  });

  it('carries the vocabularies the UI tests name', () => {
    // The three `$defs` the selector renders from. Pinned because a regeneration with a different
    // `VariableConfig` would leave the selector suites asserting on columns that are no longer
    // offered, and they would fail one at a time rather than here.
    const defs = payload.defs as Record<string, { enum?: string[] }>;
    expect(defs.col.enum).toContain('TEMP');
    expect(defs.group.enum).toEqual(['weather']);
    expect(defs.node.enum).toEqual(['rescale', 'split']);
  });
});
