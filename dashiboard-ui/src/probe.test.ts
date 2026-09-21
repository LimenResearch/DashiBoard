import { describe, it, expect, vi } from 'vitest';
import { usableProbe, askProbe } from './probe';
import { emptyProbe, emptyCards } from './stores';

// `askProbe` sits directly on `postRequest`, so its own tests mock that boundary rather than the
// network — the same seam `GroupsEditor.test.tsx` and `processing.test.tsx` mock.
const postRequest = vi.fn();
vi.mock('./requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
}));

// The envelope a failing probe actually sends. `failure_report` is `(; valid, kind, errors,
// issues)` and the probe's schema path adds `cols` — there is no `nodes` key on any failure
// route, so a coercion that demanded one threw every real failure away (final review, 2026-09-16).
const SERVER_FAILURE = {
  valid: false,
  kind: 'pipeline',
  cols: ['TEMP'],
  errors: ['group `g` has no columns'],
  issues: [{
    pointer: '/groups/g', reason: 'empty', severity: 'error' as const, found: null,
    allowed: null, missing: [], related: [], message: 'group `g` has no columns',
  }],
};

describe('usableProbe', () => {
  it('keeps the server\'s failure envelope, which carries no nodes', () => {
    const probe = usableProbe(SERVER_FAILURE);
    expect(probe.valid).toBe(false);
    expect(probe.issues).toEqual(SERVER_FAILURE.issues);
    expect(probe.errors).toEqual(['group `g` has no columns']);
    expect(probe.cols).toEqual(['TEMP']);
    expect(probe.nodes).toEqual([]);
  });

  it('keeps a success envelope whole', () => {
    const node = { id: 'r', inputs: ['TEMP'], outputs: ['TEMP_z'], unproduced: [] };
    const issue = {
      pointer: '/nodes/0/card', reason: 'overwrites', severity: 'warning' as const, found: null,
      allowed: null, missing: [], related: [], message: '`TEMP_z` already exists',
    };
    expect(usableProbe({ valid: true, cols: ['TEMP'], nodes: [node], errors: [], issues: [issue] }))
      .toEqual({ valid: true, cols: ['TEMP'], nodes: [node], errors: [], issues: [issue], referable: null });
  });

  it('keeps what each item may refer to, and reads anything else as not said', () => {
    const referable = { nodes: [{ nodes: [], groups: ['g'] }], groups: { g: { nodes: [], groups: [] } } };
    expect(usableProbe({ valid: true, referable }).referable).toEqual(referable);
    expect(usableProbe({ valid: true }).referable).toBeNull();
    expect(usableProbe({ valid: true, referable: 3 }).referable).toBeNull();
    expect(usableProbe({ valid: true, referable: { nodes: 'x', groups: {} } }).referable).toBeNull();
  });

  it('falls back to an empty probe when there is no reply at all', () => {
    expect(usableProbe(null)).toEqual(emptyProbe());
    expect(usableProbe(undefined)).toEqual(emptyProbe());
  });
});

describe('askProbe', () => {
  // `postRequest` resolves to its `def` (`null`, passed at the call site) on any failure —
  // including a 404 HTML body it cannot parse as JSON (item 1). `askProbe` used to paper over that
  // with `usableProbe(null)`, which reads as `{valid: true, issues: []}` — a clean bill of health —
  // so a probe that never reached the server looked identical to one that found nothing wrong.
  it('reports null — not a clean bill of health — when postRequest could not ask', async () => {
    postRequest.mockResolvedValueOnce(null);
    expect(await askProbe(emptyCards())).toBeNull();
  });

  it('normalises a real reply the same way usableProbe does', async () => {
    const reply = { valid: true, cols: ['TEMP'], nodes: [], errors: [], issues: [] };
    postRequest.mockResolvedValueOnce(reply);
    expect(await askProbe(emptyCards())).toEqual(usableProbe(reply));
  });
});
