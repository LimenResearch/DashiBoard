import {
  createEffect, createMemo, createRoot, createSignal, createStore,
  type Accessor, type Setter, type Store, type StoreSetter,
} from "solid-js";

// sessionStorage-backed state.
//
// The stores are module-level globals (decisions §2: the store *is* the document), and a reload
// used to start them empty — twenty cards gone for pressing F5. `sessionStorage` rather than
// `localStorage` because the document belongs to this tab's session: two tabs editing two
// pipelines must not overwrite each other, and closing the tab is the natural end of the work.
//
// Everything is guarded: there is no `sessionStorage` during SSR, a private window may throw on
// access, and whatever is in there may be from an older shape. In every one of those cases the
// answer is "start from `initial`", never "fail to load the app".

type Codec<T> = { encode: (value: T) => unknown; decode: (raw: unknown) => T };

const identity = <T>(): Codec<T> => ({ encode: (v) => v, decode: (r) => r as T });

function read<T>(key: string, codec: Codec<T>): T | undefined {
  try {
    const raw = sessionStorage.getItem(key);
    return raw === null ? undefined : codec.decode(JSON.parse(raw));
  } catch {
    return undefined;
  }
}

function write(key: string, json: string) {
  try {
    sessionStorage.setItem(key, json);
  } catch {
    // Quota or a blocked store. The in-memory state is still right; only the backup failed.
  }
}

/**
 * A `createStore` that remembers itself.
 *
 * The write effect reads the whole store — `JSON.stringify` touches every leaf — so it tracks
 * every leaf and fires on any change. That one deep read is the cost of persistence, and it is
 * also the reason `json` is returned: anything else that needs the serialised document (the
 * probe) should read it from here rather than serialise again.
 */
export function persisted<T extends object>(
  key: string,
  initial: T,
  codec: Codec<T> = identity<T>(),
): [Store<T>, StoreSetter<T>, Accessor<string>] {
  const saved = read(key, codec);
  // `T extends object` does not rule out a function-shaped `T` at the type level, which is what
  // `createStore`'s `NoFn<T>` guards against — the cast is for the checker; callers of `persisted`
  // never pass a function as `initial`.
  const [store, setStore] = createStore<T>((saved ?? initial) as never);
  const json = createRoot(() => {
    const memo = createMemo(() => JSON.stringify(codec.encode(store)));
    createEffect(memo, (value) => write(key, value));
    return memo;
  });
  return [store, setStore, json];
}

export function persistedSignal<T>(key: string, initial: T): [Accessor<T>, Setter<T>] {
  const saved = read<T>(key, identity<T>());
  // Same cast as in `persisted`: `createSignal`'s overloads split on whether `T` could be a
  // function (a compute function vs. a plain value), which an unconstrained generic can't resolve.
  const [value, setValue] = createSignal<T>((saved === undefined ? initial : saved) as never);
  createRoot(() => createEffect(value, (v) => write(key, JSON.stringify(v))));
  return [value, setValue];
}
