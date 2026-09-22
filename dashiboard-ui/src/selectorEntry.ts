import type { SelectorRow } from "./selector";

// The typed way into a selector: kind → name → optional chain → finish, the steps the panel of
// switches takes by mouse. Pure data, so the whole grammar is tested without a DOM, and what it
// emits is the row a click in the panel emits.

export type EntryVocabulary = { kinds: string[]; options: Record<string, string[]>; chain: string[] };
export type EntryState = {
  kind: string | null; name: string | null; chain: string[];
  text: string; open: boolean; highlight: number;
  /** The highlight was moved by hand: the list is engaged even with nothing typed. */
  moved: boolean;
};
export type EntryInput =
  | { type: "text"; value: string } | { type: "focus" } | { type: "tab" } | { type: "enter" }
  | { type: "backspace" } | { type: "escape" } | { type: "down" } | { type: "up" }
  | { type: "pick"; value: string; how: "continue" | "direct" | "through" };
export type EntryStep = { state: EntryState; emit?: SelectorRow; leave?: true };

/** The list shows whenever the box is in hand; Esc or leaving closes it. */
export const emptyEntry: EntryState = { kind: null, name: null, chain: [], text: "", open: true, highlight: 0, moved: false };

/** Names starting with the text, then names containing it; each in the order given. */
export function matches(query: string, options: readonly string[]): string[] {
  const q = query.toLowerCase();
  if (q === "") return [...options];
  const starts = options.filter((o) => o.toLowerCase().startsWith(q));
  const contains = options.filter((o) => !o.toLowerCase().startsWith(q) && o.toLowerCase().includes(q));
  return [...starts, ...contains];
}

/** Which part of an entry the text is for. After a name only chain steps can follow. */
export function stageOf(state: EntryState): "kind" | "name" | "chain" {
  if (state.kind === null) return "kind";
  if (state.name === null) return "name";
  return "chain";
}

/** What is typed for the current stage: a chain step may be written with or without its `@`. */
const queryOf = (state: EntryState) =>
  stageOf(state) === "chain" && state.text.startsWith("@") ? state.text.slice(1) : state.text;

export function suggestions(state: EntryState, vocabulary: EntryVocabulary): string[] {
  switch (stageOf(state)) {
    case "kind": return matches(state.text, vocabulary.kinds);
    case "name": return matches(state.text, vocabulary.options[state.kind!] ?? []);
    case "chain": return matches(queryOf(state), vocabulary.chain);
  }
}

/** The state after `value` is accepted for the current stage; the next stage's list shows. */
function accept(state: EntryState, value: string): EntryState {
  const next = { ...state, text: "", open: true, highlight: 0, moved: false };
  switch (stageOf(state)) {
    case "kind": return { ...next, kind: value };
    case "name": return { ...next, name: value };
    case "chain": return { ...next, chain: [...state.chain, value] };
  }
}

/** Something was typed or chosen: a match is highlighted, and TAB and ENTER may take it. */
export const engaged = (state: EntryState) => queryOf(state) !== "" || state.moved;

const highlighted = (state: EntryState, vocabulary: EntryVocabulary): string | undefined =>
  state.open ? suggestions(state, vocabulary)[state.highlight] : undefined;

function finish(state: EntryState, single: boolean): EntryStep {
  if (state.kind === null || state.name === null) return { state };
  const emit: SelectorRow = { kind: state.kind, value: state.name, chain: state.chain };
  return { emit, state: single ? emptyEntry : { ...emptyEntry, kind: state.kind } };
}

export function step(state: EntryState, input: EntryInput, vocabulary: EntryVocabulary, single = false): EntryStep {
  switch (input.type) {
    case "focus":
      return { state: { ...state, open: true } };
    case "text": {
      // A `:` alone asks for the kinds, it names none.
      const value = stageOf(state) === "kind" && input.value === ":" ? "" : input.value;
      // `cols:` typed out, and `bill@` typed through, both accept what came before the mark;
      // the mark alone only asks for the list.
      if (stageOf(state) === "kind" && value.endsWith(":") && value.length > 1) {
        const top = matches(value.slice(0, -1), vocabulary.kinds)[0];
        if (top !== undefined) return { state: accept({ ...state, text: value.slice(0, -1) }, top) };
      }
      if (stageOf(state) === "name" && value.endsWith("@") && value.length > 1 &&
          !(vocabulary.options[state.kind!] ?? []).some((o) => o.toLowerCase().startsWith(value.toLowerCase()))) {
        const top = matches(value.slice(0, -1), vocabulary.options[state.kind!] ?? [])[0];
        if (top !== undefined) return { state: accept({ ...state, text: value.slice(0, -1) }, top) };
      }
      return { state: { ...state, text: value, open: true, highlight: 0, moved: false } };
    }
    case "down":
    case "up": {
      const count = suggestions(state, vocabulary).length;
      if (count === 0) return { state: { ...state, open: true } };
      const delta = input.type === "down" ? 1 : -1;
      // From an untouched list the first press lands on the first match (Up: on the last).
      const from = state.open && engaged(state) ? state.highlight : delta > 0 ? -1 : count;
      return { state: { ...state, open: true, highlight: (from + delta + count) % count, moved: true } };
    }
    case "tab": {
      // TAB completes only what was typed or chosen; otherwise it leaves the field, as TAB does.
      if (!state.open || !engaged(state)) return { state, leave: true };
      const value = highlighted(state, vocabulary);
      return { state: value === undefined ? state : accept(state, value) };
    }
    case "enter": {
      // ENTER takes the highlighted match only for something typed or chosen: otherwise it
      // finishes what is already accepted, and never picks the first name off a list by itself.
      if (stageOf(state) === "kind" || !engaged(state)) return finish({ ...state, text: "" }, single);
      const value = highlighted(state, vocabulary);
      return value === undefined ? { state } : finish(accept(state, value), single);
    }
    case "backspace": {
      if (state.text !== "") return { state };
      if (state.chain.length > 0) return { state: { ...state, chain: state.chain.slice(0, -1), highlight: 0, moved: false } };
      if (state.name !== null) return { state: { ...state, name: null, highlight: 0, moved: false } };
      return { state: { ...emptyEntry } };
    }
    case "escape":
      return { state: state.open ? { ...state, open: false } : { ...emptyEntry, open: false } };
    case "pick": {
      const accepted = accept({ ...state, open: true }, input.value);
      if (input.how === "direct") return finish(accepted, single);
      if (input.how === "through") return { state: accepted };
      return { state: accepted };
    }
  }
}
