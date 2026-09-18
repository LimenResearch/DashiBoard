import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { Button } from './Button';

afterEach(cleanup);

const btn = (c: HTMLElement) => c.querySelector('button')!;

describe('Button', () => {
  it('renders its label and reports a click', () => {
    let clicked = 0;
    const { container } = render(() => <Button onClick={() => { clicked += 1; }}>Run</Button>);
    expect(btn(container).textContent).toBe('Run');
    fireEvent.click(btn(container));
    expect(clicked).toBe(1);
  });

  it('does not fire while disabled', () => {
    let clicked = 0;
    const { container } = render(() => (
      <Button disabled onClick={() => { clicked += 1; }}>Run</Button>
    ));
    fireEvent.click(btn(container));
    expect(clicked).toBe(0);
    expect(btn(container).disabled).toBe(true);
  });

  it('sizes by height, the way the host does', () => {
    // Sized by height rather than by padding around a label, and the height is a token — so a
    // host that runs roomier resizes this rather than being matched by us in advance.
    const { container: sm } = render(() => <Button>a</Button>);
    expect(btn(sm).className).toContain('h-control-xs');
    const { container: md } = render(() => <Button size="md">a</Button>);
    expect(btn(md).className).toContain('h-control-sm');
  });

  it('distinguishes its variants', () => {
    const { container: plain } = render(() => <Button>a</Button>);
    const { container: danger } = render(() => <Button variant="danger">a</Button>);
    expect(btn(plain).className).not.toBe(btn(danger).className);
    expect(btn(danger).className).toContain('destructive');
  });

  it('carries no layout of its own', () => {
    // A component that positions itself cannot be reused: the margin it brings is right in the one
    // place it was written for and wrong everywhere else. Spacing belongs to the parent.
    const { container } = render(() => <Button>a</Button>);
    expect(btn(container).className).not.toMatch(/\b-?m[trblxy]?-/);
  });
});
