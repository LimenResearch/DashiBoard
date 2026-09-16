import { describe, it, expect, beforeEach } from 'vitest';
import { flush, createRoot } from 'solid-js';
import { persisted, persistedSignal } from './persist';

beforeEach(() => sessionStorage.clear());

describe('persisted', () => {
  it('starts from what was saved, and saves what changes', async () => {
    const [a, setA] = persisted('t.store', { n: 0, list: [] as string[] });
    setA((d) => { d.n = 3; d.list.push('x'); });
    await flush();
    expect(JSON.parse(sessionStorage.getItem('t.store')!)).toEqual({ n: 3, list: ['x'] });

    // "reload": a second store under the same key sees the saved value, not `initial`
    const [b] = persisted('t.store', { n: 0, list: [] as string[] });
    expect(b.n).toBe(3);
    expect(b.list).toEqual(['x']);
  });

  it('falls back to initial when storage holds nothing, or garbage', () => {
    sessionStorage.setItem('t.bad', '{not json');
    const [s] = persisted('t.bad', { ok: true });
    expect(s.ok).toBe(true);
  });

  it('uses the codec both ways, for values JSON cannot carry', async () => {
    const codec = {
      encode: (v: { s: Set<string> }) => ({ s: [...v.s] }),
      decode: (raw: unknown) => ({ s: new Set((raw as { s: string[] }).s) }),
    };
    const [a, setA] = persisted('t.set', { s: new Set<string>() }, codec);
    setA((d) => { d.s = new Set(['p', 'q']); });
    await flush();
    const [b] = persisted('t.set', { s: new Set<string>() }, codec);
    expect(b.s).toBeInstanceOf(Set);
    expect([...b.s]).toEqual(['p', 'q']);
  });
});

describe('persistedSignal', () => {
  it('round-trips a plain value', async () => {
    const [a, setA] = persistedSignal('t.sig', 'x');
    setA('y');
    await flush();
    const [b] = persistedSignal('t.sig', 'x');
    expect(b()).toBe('y');
  });

  it('stops writing once its owner is disposed', async () => {
    // A signal created during a component's render (Home's `lastTab`) must not keep a write
    // effect alive after the component unmounts — that would be one leaked root per mount.
    let dispose!: () => void;
    let setV!: (v: string) => void;
    createRoot((d) => {
      dispose = d;
      [, setV] = persistedSignal('t.owned', 'a');
    });
    await flush();
    dispose();
    setV('b');
    await flush();
    expect(sessionStorage.getItem('t.owned')).toBe(JSON.stringify('a'));
  });
});
