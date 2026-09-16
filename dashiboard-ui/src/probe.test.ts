import { describe, it, expect } from 'vitest';
import { usableProbe } from './probe';
import { emptyProbe } from './stores';

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
      .toEqual({ valid: true, cols: ['TEMP'], nodes: [node], errors: [], issues: [issue] });
  });

  it('falls back to an empty probe when there is no reply at all', () => {
    expect(usableProbe(null)).toEqual(emptyProbe());
    expect(usableProbe(undefined)).toEqual(emptyProbe());
  });
});
