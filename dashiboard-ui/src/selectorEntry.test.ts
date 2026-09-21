import { describe, it, expect } from 'vitest';
import { emptyEntry, matches, stageOf, suggestions, step, type EntryState, type EntryInput, type EntryVocabulary } from './selectorEntry';

const V: EntryVocabulary = {
  kinds: ['nodes', 'groups', 'cols'],
  options: { nodes: ['zscore', 'impute'], groups: ['bills'], cols: ['bill_length', 'flipper_length', 'with space', 'a@b'] },
  chain: ['zscore', 'impute'],
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
  it('opens nothing by itself, and TAB on an idle box leaves the field', () => {
    expect(emptyEntry.open).toBe(false);
    expect(walk([TAB]).left).toBe(true);
  });

  it('offers the kinds on the first keystroke, and on Down', () => {
    expect(suggestions(walk([text('c')]).state, V)).toEqual(['cols']);
    expect(suggestions(walk([{ type: 'down' }]).state, V)).toEqual(['nodes', 'groups', 'cols']);
  });

  it('walks kind, name, chain, finish', () => {
    const { state, emitted } = walk([text('c'), TAB, text('bill'), TAB, text('@imp'), TAB, text('@zsc'), TAB, ENTER]);
    expect(emitted).toEqual([{ kind: 'cols', value: 'bill_length', chain: ['impute', 'zscore'] }]);
    // the kind stays for the next entry; the list is closed, so the next TAB leaves
    expect(state).toEqual({ kind: 'cols', name: null, chain: [], text: '', open: false, highlight: 0 });
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
    expect(step(closed, ESC, V).state).toEqual(emptyEntry);
  });

  it('a pick from the list is TAB, ENTER, or "through" by mouse', () => {
    const named = walk([text('c'), TAB]).state;
    expect(step(named, { type: 'pick', value: 'bill_length', how: 'direct' }, V).emit)
      .toEqual({ kind: 'cols', value: 'bill_length', chain: [] });
    const through = step(named, { type: 'pick', value: 'bill_length', how: 'through' }, V).state;
    expect(through.name).toBe('bill_length');
    expect(through.text).toBe('@');
    expect(suggestions(through, V)).toEqual(['zscore', 'impute']);
    expect(step(emptyEntry, { type: 'pick', value: 'groups', how: 'continue' }, V).state.kind).toBe('groups');
  });

  it('in single mode ENTER clears the kind too', () => {
    expect(walk([text('c'), TAB, text('bill'), ENTER], V, true).state).toEqual(emptyEntry);
  });
});
