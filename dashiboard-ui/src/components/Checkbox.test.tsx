import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { Checkbox } from './Checkbox';

afterEach(cleanup);

const box = (c: HTMLElement) => c.querySelector('input[type=checkbox]')! as HTMLInputElement;

describe('Checkbox', () => {
  it('labels itself, and clicking the label toggles it', () => {
    // The input and its text are one control. Wrapping in <label> is what makes the text a hit
    // target, which at this density is most of the control's usable area.
    let seen: boolean | null = null;
    const { getByText } = render(() => (
      <Checkbox label="TEMP" checked={false} onChange={(c) => { seen = c; }} />
    ));
    fireEvent.click(getByText('TEMP'));
    expect(seen).toBe(true);
  });

  it('reports the new state, not the event', () => {
    let seen: boolean | null = null;
    const { container } = render(() => (
      <Checkbox label="a" checked onChange={(c) => { seen = c; }} />
    ));
    fireEvent.click(box(container));
    expect(seen).toBe(false);
  });

  it('carries a value, since callers read it back off the DOM', () => {
    const { container } = render(() => (
      <Checkbox label="pretty" value="raw" checked={false} onChange={() => {}} />
    ));
    expect(box(container).value).toBe('raw');
  });

  it('falls back to the label as its value', () => {
    const { container } = render(() => (
      <Checkbox label="TEMP" checked={false} onChange={() => {}} />
    ));
    expect(box(container).value).toBe('TEMP');
  });

  it('tints with the brand rather than the browser default', () => {
    // No forms plugin is installed — `form-checkbox` compiled to nothing wherever it was used.
    // `accent-*` themes the native control with no plugin and no custom-drawn box.
    const { container } = render(() => (
      <Checkbox label="a" checked={false} onChange={() => {}} />
    ));
    expect(box(container).className).toContain('accent-primary');
  });
});
