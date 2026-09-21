import type { SelectorRow } from "./selector";

// The typed way into a selector: kind → name → optional chain → finish, the steps the panel of
// switches takes by mouse. Pure data, so the whole grammar is tested without a DOM, and what it
// emits is the row a click in the panel emits.

export type EntryVocabulary = { kinds: string[]; options: Record<string, string[]>; chain: string[] };
export type EntryState = {
  kind: string | null; name: string | null; chain: string[];
  text: string; open: boolean; highlight: number;
};
export type EntryInput =
  | { type: "text"; value: string } | { type: "tab" } | { type: "enter" } | { type: "backspace" }
  | { type: "escape" } | { type: "down" } | { type: "up" }
  | { type: "pick"; value: string; how: "continue" | "direct" | "through" };
export type EntryStep = { state: EntryState; emit?: SelectorRow; leave?: true };

export const emptyEntry: EntryState = { kind: null, name: null, chain: [], text: "", open: false, highlight: 0 };

/** Names starting with the text, then names containing it; each in the order given. */
export function matches(query: string, options: readonly string[]): string[] {
  const q = query.toLowerCase();
  if (q === "") return [...options];
  const starts = options.filter((o) => o.toLowerCase().startsWith(q));
  const contains = options.filter((o) => !o.toLowerCase().startsWith(q) && o.toLowerCase().includes(q));
  return [...starts, ...contains];
}

/** Which part of an entry the text is for. After a name, only a chain step (`@…`) can follow. */
export function stageOf(state: EntryState): "kind" | "name" | "chain" | "done" {
  if (state.kind === null) return "kind";
  if (state.name === null) return "name";
  return state.text.startsWith("@") ? "chain" : "done";
}

export function suggestions(state: EntryState, vocabulary: EntryVocabulary): string[] {
  switch (stageOf(state)) {
    case "kind": return matches(state.text, vocabulary.kinds);
    case "name": return matches(state.text, vocabulary.options[state.kind!] ?? []);
    case "chain": return matches(state.text.slice(1), vocabulary.chain);
    default: return [];
  }
}

/** The state after `value` is accepted for the current stage. */
function accept(state: EntryState, value: string): EntryState {
  switch (stageOf(state)) {
    case "kind": return { ...state, kind: value, text: "", open: true, highlight: 0 };
    case "name": return { ...state, name: value, text: "", open: false, highlight: 0 };
    case "chain": return { ...state, chain: [...state.chain, value], text: "", open: false, highlight: 0 };
    default: return state;
  }
}

const highlighted = (state: EntryState, vocabulary: EntryVocabulary): string | undefined =>
  state.open ? suggestions(state, vocabulary)[state.highlight] : undefined;

function finish(state: EntryState, single: boolean): EntryStep {
  if (state.kind === null || state.name === null) return { state };
  const emit: SelectorRow = { kind: state.kind, value: state.name, chain: state.chain };
  return { emit, state: single ? emptyEntry : { ...emptyEntry, kind: state.kind } };
}

export function step(state: EntryState, input: EntryInput, vocabulary: EntryVocabulary, single = false): EntryStep {
  switch (input.type) {
    case "text": {
      const value = input.value;
      // `cols:` typed out, and `bill@` typed through, both accept what came before the mark.
      if (stageOf(state) === "kind" && value.endsWith(":")) {
        const top = matches(value.slice(0, -1), vocabulary.kinds)[0];
        return { state: top === undefined ? { ...state, text: value, open: true, highlight: 0 } : accept({ ...state, text: value.slice(0, -1) }, top) };
      }
      if (stageOf(state) === "name" && value.endsWith("@") && !(vocabulary.options[state.kind!] ?? []).some((o) => o.toLowerCase().startsWith(value.toLowerCase()))) {
        const top = matches(value.slice(0, -1), vocabulary.options[state.kind!] ?? [])[0];
        if (top !== undefined) return { state: { ...accept({ ...state, text: value.slice(0, -1) }, top), text: "@", open: true } };
      }
      return { state: { ...state, text: value, open: true, highlight: 0 } };
    }
    case "down":
    case "up": {
      if (!state.open) return { state: { ...state, open: true, highlight: 0 } };
      const count = suggestions(state, vocabulary).length;
      if (count === 0) return { state };
      const delta = input.type === "down" ? 1 : -1;
      return { state: { ...state, highlight: (state.highlight + delta + count) % count } };
    }
    case "tab": {
      if (!state.open) return { state, leave: true };
      const value = highlighted(state, vocabulary);
      return { state: value === undefined ? state : accept(state, value) };
    }
    case "enter": {
      // ENTER takes the highlighted match only for something typed: with nothing typed it
      // finishes what is already accepted, and never picks the first name off an open list.
      const stage = stageOf(state);
      const query = stage === "chain" ? state.text.slice(1) : state.text;
      if (stage === "kind" || query === "") return finish({ ...state, text: "" }, single);
      const value = highlighted(state, vocabulary);
      return value === undefined ? { state } : finish(accept(state, value), single);
    }
    case "backspace": {
      if (state.text !== "") return { state };
      if (state.chain.length > 0) return { state: { ...state, chain: state.chain.slice(0, -1), open: false } };
      if (state.name !== null) return { state: { ...state, name: null, open: false } };
      return { state: { ...emptyEntry } };
    }
    case "escape":
      return { state: state.open ? { ...state, open: false } : emptyEntry };
    case "pick": {
      const accepted = accept({ ...state, open: true }, input.value);
      if (input.how === "direct") return finish(accepted, single);
      if (input.how === "through") return { state: { ...accepted, text: "@", open: true, highlight: 0 } };
      return { state: accepted };
    }
  }
}
