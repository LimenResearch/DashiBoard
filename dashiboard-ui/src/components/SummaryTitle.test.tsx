import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
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

  it('lets the name be edited where it is read, without the click folding the line', () => {
    const renamed: string[] = [];
    const { container } = render(() => (
      <details>
        <summary>
          <SummaryTitle hook="group" kind="Group" name="weather" state="unconfirmed"
            edit={{ id: 'group-name-weather', label: 'group name', onRename: (field) => renamed.push(field.value) }} />
        </summary>
      </details>
    ));
    const field = container.querySelector('#group-name-weather') as HTMLInputElement;
    expect(field.value).toBe('weather');
    expect(field.getAttribute('aria-label')).toBe('group name');
    expect(field.className).toMatch(/min-w-0/);                  // shrinks with the pane
    expect(fireEvent.click(field)).toBe(false);                   // prevented: the line does not fold
    expect(fireEvent.keyUp(field, { key: ' ' })).toBe(false);     // nor on a space typed in the name
    fireEvent.change(field, { target: { value: 'sky' } });
    expect(renamed).toEqual(['sky']);
  });

  it('asks for a name in the box when there is none', () => {
    const { container } = render(() => (
      <SummaryTitle hook="card" kind="Split" name="" state="unconfirmed"
        edit={{ id: 'node-id-0', label: 'node id', onRename: () => {} }} />
    ));
    expect((container.querySelector('#node-id-0') as HTMLInputElement).placeholder).toBe('unnamed');
  });
});
