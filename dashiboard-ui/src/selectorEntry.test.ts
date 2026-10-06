import { describe, it, expect } from 'vitest';
import { emptyEntry, engaged, matches, stageOf, suggestions, step, type EntryState, type EntryInput, type EntryVocabulary } from './selectorEntry';

const V: EntryVocabulary = {
  kinds: ['nodes', 'groups', 'cols'],
  options: { nodes: ['zscore', 'impute'], groups: ['bills'], cols: ['bill_length', 'flipper_length', 'with space', 'a@b'] },
  chain: ['zscore', 'impute'],
  narrow: [],
};
/** Feed inputs in order; return the last state and every row emitted on the way. */
const walk = (inputs: EntryInput[], vocabulary = V, single = false, from: EntryState = emptyEntry) => {
  let state = from; const emitted = []; let left = false;
  for (const input of inputs) {
    const next = step(state, input, vocabulary, single);
    state = next.state; if (next.emit) emitted.push(next.emit); if (next.leave) left = true;
  }
  return { state, emitted, left };
};
const text = (value: string): EntryInput => ({ type: 'text', value });
const TAB: EntryInput = { type: 'tab' }; const ENTER: EntryInput = { type: 'enter' };
const BACK: EntryInput = { type: 'backspace' }; const ESC: EntryInput = { type: 'escape' };

describe('matches', () => {
  it('lists names that start with the text first, then names that contain it, each in the given order', () => {
    expect(matches('len', ['flipper_length', 'length', 'bill_length'])).toEqual(['length', 'flipper_length', 'bill_length']);
    expect(matches('', ['b', 'a'])).toEqual(['b', 'a']);
    expect(matches('BILL', ['bill_length'])).toEqual(['bill_length']);
    expect(matches('zzz', ['bill_length'])).toEqual([]);
  });
});

describe('the typed entry', () => {
  it('offers the kinds as soon as the box is focused, and on `:` alone', () => {
    const focused = walk([{ type: 'focus' }]).state;
    expect(focused.open).toBe(true);
    expect(suggestions(focused, V)).toEqual(['nodes', 'groups', 'cols']);
    const colon = walk([{ type: 'focus' }, text(':')]).state;
    expect(colon.kind).toBeNull();
    expect(suggestions(colon, V)).toEqual(['nodes', 'groups', 'cols']);
    expect(suggestions(walk([text('c')]).state, V)).toEqual(['cols']);
  });

  it('highlights nothing until something is typed or chosen; the first Down lands on the first match', () => {
    const focused = walk([{ type: 'focus' }]).state;
    expect(engaged(focused)).toBe(false);
    expect(engaged(walk([text('c')]).state)).toBe(true);
    const down = walk([{ type: 'focus' }, { type: 'down' }]).state;
    expect(engaged(down)).toBe(true);
    expect(suggestions(down, V)[down.highlight]).toBe('nodes');
    const up = walk([{ type: 'focus' }, { type: 'up' }]).state;
    expect(suggestions(up, V)[up.highlight]).toBe('cols');
  });

  it('TAB leaves the field until something is typed or chosen, even with the list showing', () => {
    expect(walk([{ type: 'focus' }, TAB]).left).toBe(true);
    expect(walk([{ type: 'focus' }, TAB]).state.kind).toBeNull();
    expect(walk([{ type: 'focus' }, { type: 'down' }, TAB]).state.kind).toBe('nodes');
    expect(walk([text('c'), TAB, TAB]).left).toBe(true);        // names showing, nothing typed
    expect(walk([text('c'), TAB, TAB]).state.name).toBeNull();
  });

  it('after a name, the list offers the nodes a chain may pass through', () => {
    const named = walk([text('c'), TAB, text('bill'), TAB]).state;
    expect(named.open).toBe(true);
    expect(stageOf(named)).toBe('chain');
    expect(suggestions(named, V)).toEqual(['zscore', 'impute']);
    expect(walk([text('c'), TAB, text('bill'), TAB, ENTER]).emitted[0].chain).toEqual([]);   // still direct
  });

  it('walks kind, name, chain, finish', () => {
    const { state, emitted } = walk([text('c'), TAB, text('bill'), TAB, text('@imp'), TAB, text('@zsc'), TAB, ENTER]);
    expect(emitted).toEqual([{ kind: 'cols', value: 'bill_length', chain: ['impute', 'zscore'] }]);
    // the kind stays for the next entry, with its names on offer; nothing typed, so TAB leaves
    expect(state).toEqual({ kind: 'cols', name: null, chain: [], text: '', open: true, highlight: 0, moved: false, selecting: false });
    expect(step(state, TAB, V).leave).toBe(true);
  });

  it('shows every name of the kind once the kind is accepted', () => {
    expect(suggestions(walk([text('g'), TAB]).state, V)).toEqual(['bills']);
    expect(stageOf(walk([text('g'), TAB]).state)).toBe('name');
  });

  it('accepts a kind typed out with its colon', () => {
    expect(walk([text('cols:')]).state.kind).toBe('cols');
  });

  it('ENTER accepts the highlighted match and finishes; a name with no chain is direct', () => {
    expect(walk([text('c'), TAB, text('flip'), ENTER]).emitted).toEqual([{ kind: 'cols', value: 'flipper_length', chain: [] }]);
    expect(walk([text('c'), TAB, text('bill'), TAB, text('@imp'), ENTER]).emitted)
      .toEqual([{ kind: 'cols', value: 'bill_length', chain: ['impute'] }]);
  });

  it('Up and Down choose another match before TAB', () => {
    const { emitted } = walk([text('c'), TAB, text('length'), { type: 'down' }, TAB, ENTER]);
    expect(emitted[0].value).toBe('flipper_length');
  });

  it('`@` typed after a name fragment accepts the top match and starts the chain', () => {
    const { state } = walk([text('c'), TAB, text('bill@')]);
    expect(state.name).toBe('bill_length');
    expect(stageOf(state)).toBe('chain');
    expect(suggestions(state, V)).toEqual(['zscore', 'impute']);
  });

  it('takes names with a space or an `@` in them whole, since nothing is parsed', () => {
    expect(walk([text('c'), TAB, text('with'), TAB, ENTER]).emitted[0].value).toBe('with space');
    expect(walk([text('c'), TAB, text('a@b'), TAB, ENTER]).emitted[0].value).toBe('a@b');
  });

  it('does nothing on ENTER with only a kind, or with a fragment that matches nothing', () => {
    expect(walk([text('c'), TAB, ENTER]).emitted).toEqual([]);
    expect(walk([text('c'), TAB, text('zzz'), ENTER]).emitted).toEqual([]);
    expect(walk([text('c'), TAB, text('zzz'), TAB]).state.name).toBeNull();
  });

  it('offers no chain when there are no nodes to pass through', () => {
    const none = { ...V, chain: [] };
    expect(suggestions(walk([text('c'), TAB, text('bill'), TAB, text('@')], none).state, none)).toEqual([]);
  });

  it('Backspace with nothing typed removes the last token whole, the kind last', () => {
    const full = walk([text('c'), TAB, text('bill'), TAB, text('@imp'), TAB]).state;
    const a = step(full, BACK, V).state;       expect(a.chain).toEqual([]);
    const b = step(a, BACK, V).state;          expect(b.name).toBeNull();
    const c = step(b, BACK, V).state;          expect(c.kind).toBeNull();
  });

  it('Esc closes the list, then clears the entry', () => {
    const typing = walk([text('c'), TAB, text('bill')]).state;
    const closed = step(typing, ESC, V).state;
    expect(closed.open).toBe(false);
    expect(closed.kind).toBe('cols');
    expect(step(closed, ESC, V).state).toEqual({ ...emptyEntry, open: false });
  });

  it('a pick from the list is TAB, ENTER, or "through" by mouse', () => {
    const named = walk([text('c'), TAB]).state;
    expect(step(named, { type: 'pick', value: 'bill_length', how: 'direct' }, V).emit)
      .toEqual({ kind: 'cols', value: 'bill_length', chain: [] });
    const through = step(named, { type: 'pick', value: 'bill_length', how: 'through' }, V).state;
    expect(through.name).toBe('bill_length');
    expect(stageOf(through)).toBe('chain');
    expect(suggestions(through, V)).toEqual(['zscore', 'impute']);
    expect(step(emptyEntry, { type: 'pick', value: 'groups', how: 'continue' }, V).state.kind).toBe('groups');
  });

  it('the list stays for the next entry after a pick or ENTER; only Esc and leaving close it', () => {
    const named = walk([text('c'), TAB]).state;
    expect(step(named, { type: 'pick', value: 'bill_length', how: 'direct' }, V).state.open).toBe(true);
    expect(step(named, { type: 'pick', value: 'bill_length', how: 'direct' }, V, true).state).toEqual(emptyEntry);
    expect(walk([text('c'), TAB, text('bill'), ENTER]).state.open).toBe(true);
    expect(walk([text('c'), TAB, text('bill'), ENTER, ESC]).state.open).toBe(false);
  });

  it('reads text after a name as a chain step, with or without its `@`', () => {
    expect(suggestions(walk([text('c'), TAB, text('bill'), TAB, text('imp')]).state, V)).toEqual(['impute']);
    expect(suggestions(walk([text('c'), TAB, text('bill'), TAB, text('@imp')]).state, V)).toEqual(['impute']);
  });

  it('in single mode ENTER clears the kind too', () => {
    expect(walk([text('c'), TAB, text('bill'), ENTER], V, true).state).toEqual(emptyEntry);
  });
});

describe('narrowing a step to a product', () => {
  const vocabulary = { kinds: ['cols'], options: { cols: ['Iws'] }, chain: ['fit'], narrow: ['prediction', 'logvar'] };
  const atChain = { ...emptyEntry, kind: 'cols', name: 'Iws', chain: ['fit'] };

  // `|` after a step asks which of its products; it does not start another step.
  it('offers the products once `|` is typed, and adds the choice to the step', () => {
    const typed = step(atChain, { type: 'text', value: '|lo' }, vocabulary).state;
    expect(suggestions(typed, vocabulary)).toEqual(['logvar']);
    const taken = step(typed, { type: 'tab' }, vocabulary).state;
    expect(taken.chain).toEqual(['fit|logvar']);
    expect(taken.text).toBe('');
  });

  it('keeps adding, in the order chosen', () => {
    const one = { ...atChain, chain: ['fit|logvar'] };
    const typed = step(one, { type: 'text', value: '|pre' }, { ...vocabulary, narrow: ['prediction'] }).state;
    expect(step(typed, { type: 'tab' }, { ...vocabulary, narrow: ['prediction'] }).state.chain).toEqual(['fit|logvar|prediction']);
  });

  it('has nothing to offer for a step with one product', () => {
    const typed = step(atChain, { type: 'text', value: '|' }, { ...vocabulary, narrow: [] }).state;
    expect(suggestions(typed, { ...vocabulary, narrow: [] })).toEqual([]);
  });

  // A lone `|` is a question already asked: TAB takes the first product instead of leaving.
  it('takes the first product on TAB after a lone `|`', () => {
    const typed = step(atChain, { type: 'text', value: '|' }, vocabulary).state;
    expect(step(typed, { type: 'tab' }, vocabulary).state.chain).toEqual(['fit|prediction']);
  });

  it('does not narrow before any step is taken', () => {
    const typed = step({ ...atChain, chain: [] }, { type: 'text', value: '|' }, vocabulary).state;
    expect(suggestions(typed, vocabulary)).toEqual([]);
  });
});

// `select…` is to `|` what `through…` is to `@`: a click and its mark reach the same state, and the
// list that follows has the form the list of nodes has — one row per choice, more until finished.
describe('choosing products, by mark or by click', () => {
  const v = (narrow: string[]): EntryVocabulary =>
    ({ kinds: ['nodes', 'cols'], options: { nodes: ['fit', 'scale'], cols: ['Iws'] }, chain: ['scale'], narrow });
  const same = (a: EntryState, b: EntryState) => {
    const keep = (s: EntryState) => ({ kind: s.kind, name: s.name, chain: s.chain, selecting: s.selecting });
    expect(keep(a)).toEqual(keep(b));
  };
  const atNodes = { ...emptyEntry, kind: 'nodes' };

  it('narrows a node selection with `|`, as a step is narrowed, and emits one token', () => {
    let s = walk([text('fi'), TAB], v(['one', 'two', 'three']), false, atNodes).state;
    s = walk([text('|one'), TAB], v(['one', 'two', 'three']), false, s).state;
    expect(s.name).toBe('fit|one');
    s = walk([text('|th'), TAB], v(['two', 'three']), false, s).state;
    expect(s.name).toBe('fit|one|three');
    expect(walk([ENTER], v(['two']), false, s).emitted).toEqual([{ kind: 'nodes', value: 'fit|one|three', chain: [] }]);
  });

  it('reaches by select… on a name the state `|` reaches', () => {
    const typed = walk([text('fit'), TAB, text('|')], v(['one', 'two']), false, atNodes).state;
    const clicked = step(atNodes, { type: 'pick', value: 'fit', how: 'select' }, v(['one', 'two'])).state;
    same(clicked, { ...typed, selecting: true });
    expect(suggestions(clicked, v(['one', 'two']))).toEqual(['one', 'two']);
    expect(suggestions(typed, v(['one', 'two']))).toEqual(['one', 'two']);
  });

  it('reaches by select… on a step the state `@step|` reaches', () => {
    const atName = { ...emptyEntry, kind: 'cols', name: 'Iws' };
    const typed = walk([text('@scale'), TAB, text('|')], v(['a', 'b']), false, atName).state;
    const clicked = step(atName, { type: 'pick', value: 'scale', how: 'select' }, v(['a', 'b'])).state;
    expect(clicked.chain).toEqual(typed.chain);
    expect(clicked.selecting).toBe(true);
    expect(suggestions(clicked, v(['a', 'b']))).toEqual(['a', 'b']);
  });

  it('lists the products left after one is kept by a click, until none is left', () => {
    const selecting = step(atNodes, { type: 'pick', value: 'fit', how: 'select' }, v(['one', 'two'])).state;
    const one = step(selecting, { type: 'pick', value: 'one', how: 'continue' }, v(['one', 'two'])).state;
    expect(one.name).toBe('fit|one');
    expect(one.selecting).toBe(true);
    expect(suggestions(one, v(['two']))).toEqual(['two']);
    const both = step(one, { type: 'pick', value: 'two', how: 'continue' }, v(['two'])).state;
    expect(both.name).toBe('fit|one|two');
    expect(both.selecting).toBe(false);                  // nothing left to choose: the nodes again
    expect(suggestions(both, v([]))).toEqual(['scale']);
  });

  it('goes on to the nodes from a product by through…, and by `@`', () => {
    const selecting = step(atNodes, { type: 'pick', value: 'fit', how: 'select' }, v(['one', 'two'])).state;
    const through = step(selecting, { type: 'pick', value: 'one', how: 'through' }, v(['one', 'two'])).state;
    expect(through.name).toBe('fit|one');
    expect(through.selecting).toBe(false);
    expect(suggestions(through, v(['two']))).toEqual(['scale']);
    const typed = walk([text('@sc')], v(['one', 'two']), false, selecting).state;
    expect(typed.selecting).toBe(false);
    expect(suggestions(typed, v(['one', 'two']))).toEqual(['scale']);
  });

  it('narrows what is already taken with the select beside add', () => {
    const atStep = { ...emptyEntry, kind: 'cols', name: 'Iws', chain: ['scale'] };
    const s = step(atStep, { type: 'select' }, v(['a', 'b'])).state;
    expect(s.selecting).toBe(true);
    expect(suggestions(s, v(['a', 'b']))).toEqual(['a', 'b']);
  });

  it('finishes on ENTER with nothing typed, never taking the first product', () => {
    const selecting = step(atNodes, { type: 'pick', value: 'fit', how: 'select' }, v(['one', 'two'])).state;
    expect(walk([ENTER], v(['one', 'two']), false, selecting).emitted).toEqual([{ kind: 'nodes', value: 'fit', chain: [] }]);
  });

  it('BACKSPACE with nothing typed first stops choosing products', () => {
    const selecting = step(atNodes, { type: 'pick', value: 'fit', how: 'select' }, v(['one', 'two'])).state;
    const back = walk([BACK], v(['one', 'two']), false, selecting).state;
    expect(back.selecting).toBe(false);
    expect(back.name).toBe('fit');
  });

  it('does not narrow a column or a group by name', () => {
    const atName = { ...emptyEntry, kind: 'cols', name: 'Iws' };
    expect(suggestions(step(atName, text('|'), v(['a'])).state, v(['a']))).toEqual([]);
  });
});
