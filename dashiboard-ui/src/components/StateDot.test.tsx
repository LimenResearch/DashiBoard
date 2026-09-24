import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup } from '@solidjs/testing-library';
import { createSignal, flush } from 'solid-js';
import { StateDot } from './StateDot';

afterEach(cleanup);
const dot = (c: HTMLElement) => c.querySelector('[data-state]') as HTMLElement;

describe('StateDot', () => {
  it('is amber until asked, green when confirmed, red when rejected', () => {
    for (const [state, colour] of [['unconfirmed', 'bg-warning'], ['confirmed', 'bg-success'], ['rejected', 'bg-destructive']] as const) {
      const { container } = render(() => <StateDot state={state} />);
      expect(dot(container).getAttribute('data-state')).toBe(state);
      expect(dot(container).getAttribute('aria-label')).toBe(state);
      expect(dot(container).className).toContain(colour);
      cleanup();
    }
  });

  it('says what each state means for a card unless told otherwise', () => {
    const { container } = render(() => <StateDot state="rejected" />);
    expect(dot(container).title).toBe('the server found something wrong — open to see what');
    cleanup();
    const run = render(() => <StateDot state="rejected" titles={{ rejected: 'the last run failed' }} />);
    expect(dot(run.container).title).toBe('the last run failed');
  });

  it('follows its state', async () => {
    const [state, setState] = createSignal<'unconfirmed' | 'confirmed'>('unconfirmed');
    const { container } = render(() => <StateDot state={state()} />);
    setState('confirmed');
    await flush();
    expect(dot(container).getAttribute('data-state')).toBe('confirmed');
    expect(dot(container).className).toContain('bg-success');
  });
});
