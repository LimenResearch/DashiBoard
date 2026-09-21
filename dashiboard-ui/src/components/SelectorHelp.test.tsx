import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { SelectorHelp } from './SelectorHelp';

afterEach(cleanup);

const button = (c: HTMLElement) => c.querySelector('[data-help]') as HTMLButtonElement;
const note = (c: HTMLElement) => c.querySelector('[role=note]');

describe('SelectorHelp', () => {
  it('is closed until asked, and reachable by TAB', () => {
    const { container } = render(() => <SelectorHelp />);
    expect(note(container)).toBeNull();
    expect(button(container).getAttribute('aria-expanded')).toBe('false');
    expect(button(container).tabIndex).not.toBe(-1);
  });

  it('lists the keys when opened', async () => {
    const { container } = render(() => <SelectorHelp />);
    fireEvent.click(button(container)); await flush();
    const text = note(container)!.textContent!;
    for (const word of ['Tab', '@', 'Enter', 'Alt']) expect(text).toContain(word);
    expect(button(container).getAttribute('aria-expanded')).toBe('true');
  });

  it('does not mention reordering for a field that holds one value', async () => {
    const { container } = render(() => <SelectorHelp single />);
    fireEvent.click(button(container)); await flush();
    expect(note(container)!.textContent).not.toContain('Alt');
  });

  it('closes on Escape, and on a second click', async () => {
    const { container } = render(() => <SelectorHelp />);
    fireEvent.click(button(container)); await flush();
    fireEvent.keyDown(button(container), { key: 'Escape' }); await flush();
    expect(note(container)).toBeNull();
    fireEvent.click(button(container)); await flush();
    fireEvent.click(button(container)); await flush();
    expect(note(container)).toBeNull();
  });
});
