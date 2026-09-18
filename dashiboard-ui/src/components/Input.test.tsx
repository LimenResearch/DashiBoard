import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { Input } from './Input';

afterEach(cleanup);

const field = (c: HTMLElement) => c.querySelector('input')!;

describe('Input', () => {
  it('matches the host control height rather than stock shadcn', () => {
    const { container } = render(() => <Input />);
    expect(field(container).className).toContain('h-control-xs');
  });

  it('reports changes', () => {
    let seen = '';
    const { container } = render(() => (
      <Input onChange={(e) => { seen = (e.currentTarget as HTMLInputElement).value; }} />
    ));
    const el = field(container);
    el.value = 'typed';
    fireEvent.change(el);
    expect(seen).toBe('typed');
  });

  it('shows an invalid state, which is what A7 gives it something to say', () => {
    // The probe addresses a failure by JSON Pointer, so a field can be told it is the offender.
    // Without a state to render, that information has nowhere to land but a banner.
    const { container } = render(() => <Input invalid />);
    expect(field(container).getAttribute('aria-invalid')).toBe('true');
    expect(field(container).className).toContain('destructive');
  });

  it('is not invalid by default, and says so to assistive tech', () => {
    const { container } = render(() => <Input />);
    expect(field(container).getAttribute('aria-invalid')).toBe('false');
    expect(field(container).className).not.toContain('destructive');
  });

  it('can be disabled', () => {
    const { container } = render(() => <Input disabled />);
    expect(field(container).disabled).toBe(true);
  });

  it('takes extra classes from the caller without losing its own', () => {
    const { container } = render(() => <Input class="w-full" />);
    expect(field(container).className).toContain('w-full');
    expect(field(container).className).toContain('h-control-xs');
  });
});
