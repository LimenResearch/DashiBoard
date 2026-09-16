import { createSignal } from "solid-js";
import { CARDS_STORE, LOADER_STORE } from "./stores";

// The stores restore themselves from `sessionStorage` at module load (persist.ts). That is what
// brought a whole document back after a server restart on 2026-09-16 — right after an accident,
// too much when a fresh start was wanted, and in both cases silent. This makes the choice
// explicit: a gate once per tab when something was restored, and Start over at any time.
//
// `sessionStorage` is per tab and survives reloads, so "a previous session" can only mean this
// tab reloaded; a new tab has no storage and no gate.

const GATE = "dashi.gate";

function read(): boolean {
  try { return sessionStorage.getItem(GATE) === "answered"; } catch { return true; }
}

// Solid 2 signals defer visibility of a write until the next microtask flush — `setX(v); x()`
// still answers with the *previous* value (CHEATSHEET: "Reads update only after flush"). A
// caller of `recoverSession()` needs `hasPreviousSession()` to already say "no gate" the instant
// it returns, most concretely `SessionGate.test.tsx`'s "Recover" click and `session.test.ts`'s
// direct call, neither of which waits a tick before asking. `sessionStorage` has no such delay —
// it is a synchronous browser API — so it stays the one source of truth for the answered flag;
// `bump` exists only to give the JSX `<Show>` something to depend on, exactly as `TableView`'s
// `revision` is read to register a dependency and then not used for its value.
const [bump, setBump] = createSignal(0);

/** How much came back — for the gate to say what it is offering. */
export function sessionSummary() {
  const [loader] = LOADER_STORE;
  const [cards] = CARDS_STORE;
  return { columns: loader.length, groups: Object.keys(cards.groups).length, cards: cards.nodes.length };
}

/** Something was restored, and this tab has not said what to do with it. */
export function hasPreviousSession(): boolean {
  bump(); // dependency only, so a `recoverSession()` call is reflected in JSX — see `bump` above
  if (read()) return false;
  const s = sessionSummary();
  return s.columns + s.groups + s.cards > 0;
}

export function recoverSession() {
  try { sessionStorage.setItem(GATE, "answered"); } catch { /* no storage: nothing to remember */ }
  setBump((n) => n + 1);
}

/**
 * Forget everything and start again through the one path the stores already have: empty
 * storage, then a reload. Not a store-by-store reset — that would be a second code path for the
 * same state, and the reload also drops every in-memory signal that was derived from it.
 */
export function resetSession(reload: () => void = () => location.reload()) {
  try {
    for (const key of Object.keys(sessionStorage)) {
      if (key.startsWith("dashi.")) sessionStorage.removeItem(key);
    }
  } catch { /* no storage: nothing to clear */ }
  reload();
}
