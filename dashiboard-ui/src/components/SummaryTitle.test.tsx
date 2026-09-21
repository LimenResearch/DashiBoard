import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup } from '@solidjs/testing-library';
import { SummaryTitle, readableType } from './SummaryTitle';

afterEach(cleanup);

describe('readableType', () => {
  it('turns a type name into words, for when the server has given no title', () => {
    expect(readableType('dimensionality_reduction')).toBe('Dimensionality Reduction');
    expect(readableType('rescale')).toBe('Rescale');
    expect(readableType('')).toBe('');
  });
});

describe('SummaryTitle', () => {
  it('says what kind of thing it is, then its name, then where it stands', () => {
    const { container } = render(() => <SummaryTitle hook="card" kind="Rescale" name="r" state="confirmed" />);
    const title = container.querySelector('[data-card-title]')!;
    expect(title.textContent).toBe('Rescale:r');
    expect(title.getAttribute('title')).toBe('Rescale : r');
    expect(title.querySelector('[data-state]')!.getAttribute('data-state')).toBe('confirmed');
  });

  it('truncates the text, not the flex container, so the ellipsis can render', () => {
    const { container } = render(() => <SummaryTitle hook="group" kind="Group" name="weather" state="unconfirmed" />);
    const title = container.querySelector('[data-group-title]')!;
    expect(title.className).toMatch(/min-w-0/);
    expect(title.className).not.toMatch(/truncate/);
    const text = container.querySelector('[data-group-text]')!;
    expect(text.className).toMatch(/truncate/);
    expect(text.className).not.toMatch(/flex/);
  });

  it('says so when there is no name', () => {
    const { container } = render(() => <SummaryTitle hook="card" kind="Split" name="" state="unconfirmed" />);
    expect(container.querySelector('[data-card-title]')!.textContent).toBe('Split:unnamed');
    expect(container.querySelector('[data-card-title]')!.getAttribute('title')).toBe('Split : unnamed');
  });
});
