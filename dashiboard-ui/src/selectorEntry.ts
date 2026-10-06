import { STEP_SEPARATOR, type SelectorRow } from "./selector";

// The typed way into a selector: kind → name → optional chain → finish, the steps the panel of
// switches takes by mouse. Pure data, so the whole grammar is tested without a DOM, and what it
// emits is the row a click in the panel emits.

export type EntryVocabulary = {
  kinds: string[]; options: Record<string, string[]>; chain: string[];
  /** The products the last node taken — the last step, or the name of a `nodes` selection — may
   *  still be narrowed to. */
  narrow: string[];
};
export type EntryState = {
  kind: string | null; name: string | null; chain: string[];
  text: string; open: boolean; highlight: number;
  /** The highlight was moved by hand: the list is engaged even with nothing typed. */
  moved: boolean;
  /** The list offers the products of the last node taken rather than nodes to pass through:
   *  `select…` or `|` turns it on, `through…` or `@` off. */
  selecting: boolean;
};
export type EntryInput =
  | { type: "text"; value: string } | { type: "focus" } | { type: "tab" } | { type: "enter" }
  | { type: "backspace" } | { type: "escape" } | { type: "down" } | { type: "up" }
  | { type: "pick"; value: string; how: "continue" | "direct" | "through" | "select" }
  /** The `select…` beside `add`: choose products of what is already taken. */
  | { type: "select" };
export type EntryStep = { state: EntryState; emit?: SelectorRow; leave?: true };

/** The list shows whenever the box is in hand; Esc or leaving closes it. */
export const emptyEntry: EntryState = {
  kind: null, name: null, chain: [], text: "", open: true, highlight: 0, moved: false, selecting: false,
};

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

/** A node is there to narrow: the last step, or the name of a `nodes` selection. */
const narrowable = (state: EntryState) => state.chain.length > 0 || state.kind === "nodes";

/** At the chain stage, `|` or `select…` narrows the node just taken instead of adding a step;
 *  `@` goes back to the steps. */
export const narrowing = (state: EntryState) =>
  stageOf(state) === "chain" && narrowable(state) && !state.text.startsWith("@") &&
  (state.selecting || state.text.startsWith(STEP_SEPARATOR));

/** What is typed for the current stage: a chain step may be written with or without its `@`. */
const queryOf = (state: EntryState) =>
  (narrowing(state) && state.text.startsWith(STEP_SEPARATOR)) || (stageOf(state) === "chain" && state.text.startsWith("@"))
    ? state.text.slice(1) : state.text;

export function suggestions(state: EntryState, vocabulary: EntryVocabulary): string[] {
  switch (stageOf(state)) {
    case "kind": return matches(state.text, vocabulary.kinds);
    case "name": return matches(state.text, vocabulary.options[state.kind!] ?? []);
    case "chain": return matches(queryOf(state), narrowing(state) ? vocabulary.narrow : vocabulary.chain);
  }
}

/**
 * The state after `value` is accepted for the current stage; the next stage's list shows. A product
 * joins the node it narrows, and the products left stay on offer while there are any — `left` is
 * how many the list held, the one taken included.
 */
function accept(state: EntryState, value: string, left = 0): EntryState {
  const next = { ...state, text: "", open: true, highlight: 0, moved: false, selecting: false };
  switch (stageOf(state)) {
    case "kind": return { ...next, kind: value };
    case "name": return { ...next, name: value };
    case "chain": {
      if (!narrowing(state)) return { ...next, chain: [...state.chain, value] };
      const more = left > 1;
      return state.chain.length > 0
        ? { ...next, selecting: more, chain: [...state.chain.slice(0, -1), `${state.chain.at(-1)}${STEP_SEPARATOR}${value}`] }
        : { ...next, selecting: more, name: `${state.name}${STEP_SEPARATOR}${value}` };
    }
  }
}

/** Something was typed or chosen: a match is highlighted, and TAB and ENTER may take it. */
export const engaged = (state: EntryState) =>
  queryOf(state) !== "" || state.moved || (narrowing(state) && state.text.startsWith(STEP_SEPARATOR));

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
      return {
        state: {
          ...state, text: value, open: true, highlight: 0, moved: false,
          selecting: state.selecting && !value.startsWith("@"),
        },
      };
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
      return { state: value === undefined ? state : accept(state, value, vocabulary.narrow.length) };
    }
    case "enter": {
      // ENTER takes the highlighted match only for something typed or chosen: otherwise it
      // finishes what is already accepted, and never picks the first name off a list by itself.
      if (stageOf(state) === "kind" || !engaged(state)) return finish({ ...state, text: "" }, single);
      const value = highlighted(state, vocabulary);
      return value === undefined ? { state } : finish(accept(state, value, vocabulary.narrow.length), single);
    }
    case "backspace": {
      if (state.text !== "") return { state };
      if (state.selecting) return { state: { ...state, selecting: false, highlight: 0, moved: false } };
      if (state.chain.length > 0) return { state: { ...state, chain: state.chain.slice(0, -1), highlight: 0, moved: false } };
      if (state.name !== null) return { state: { ...state, name: null, highlight: 0, moved: false } };
      return { state: { ...emptyEntry } };
    }
    case "escape":
      return { state: state.open ? { ...state, open: false } : { ...emptyEntry, open: false } };
    case "pick": {
      const accepted = accept({ ...state, open: true }, input.value, vocabulary.narrow.length);
      if (input.how === "direct") return finish(accepted, single);
      // From a product, `through…` goes on to the nodes; on a name or a step, `select…` asks for
      // its products — what `@` and `|` do typed.
      if (input.how === "through") return { state: { ...accepted, selecting: false } };
      if (input.how === "select") return { state: { ...accepted, selecting: true } };
      return { state: accepted };
    }
    case "select":
      return { state: { ...state, text: "", open: true, highlight: 0, moved: false, selecting: narrowable(state) } };
  }
}
