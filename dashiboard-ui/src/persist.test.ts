import { describe, it, expect, beforeEach } from 'vitest';
import { flush } from 'solid-js';
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
});
