import { describe, it, expect, afterEach, beforeEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { HelpTip, HelpButton, setHelpOpen } from './SelectorHelp';

afterEach(cleanup);
beforeEach(() => setHelpOpen(false));

const note = (c: HTMLElement) => c.querySelector('[role=note]');
/** jsdom has no layout: this is how far down the viewport the ⓘ sits. */
const sitAt = (c: HTMLElement, selector: string, top: number) => {
  const anchor = c.querySelector(selector)!;
  anchor.getBoundingClientRect = () => ({ top, bottom: top + 20, height: 20, left: 0, right: 20, width: 20 } as DOMRect);
};
/** jsdom's window is 768 tall, so `top` decides which side has the room. */
const height = (c: HTMLElement) => (note(c) as HTMLElement).style.maxHeight;

describe('HelpTip, the pointer’s path', () => {
  it('is not a tab stop and carries no action: hover is all it does', () => {
    const { container } = render(() => <HelpTip />);
    const tip = container.querySelector('[data-help-tip]') as HTMLElement;
    expect(tip.tagName).not.toBe('BUTTON');
    expect(tip.getAttribute('tabindex')).toBe('-1');
    expect(note(container)).toBeNull();
  });

  it('shows the keys while the pointer rests on it, above it so the suggestions stay visible', async () => {
    const { container } = render(() => <HelpTip />);
    const tip = container.querySelector('[data-help-tip]')!;
    sitAt(container, '[data-help-tip]', 600);
    fireEvent.mouseEnter(tip); await flush();
    expect(note(container)!.textContent).toContain('Tab');
    expect(note(container)!.className).toContain('bottom-full');   // opens upward, from its left edge
    expect(note(container)!.className).toContain('left-0');
    fireEvent.mouseLeave(tip); await flush();
    expect(note(container)).toBeNull();
  });

  it('drops below the mark when there is no room above it', async () => {
    // Near the top of the page the panel was cut off at the window's edge and unreadable.
    const { container } = render(() => <HelpTip />);
    sitAt(container, '[data-help-tip]', 30);
    fireEvent.mouseEnter(container.querySelector('[data-help-tip]')!); await flush();
    expect(note(container)!.className).toContain('top-full');
    expect(note(container)!.className).not.toContain('bottom-full');
  });

  it('does not mention reordering for a field that holds one value', async () => {
    const { container } = render(() => <HelpTip single />);
    fireEvent.mouseEnter(container.querySelector('[data-help-tip]')!); await flush();
    expect(note(container)!.textContent).not.toContain('Alt');
  });
});

describe('HelpButton, the keyboard’s path', () => {
  it('is one reachable button that toggles the same keys, and says F1 opens them', async () => {
    const { container } = render(() => <HelpButton />);
    const button = container.querySelector('[data-help]') as HTMLButtonElement;
    expect(button.tabIndex).not.toBe(-1);
    expect(button.getAttribute('aria-label')).toMatch(/how to type/i);
    expect(button.textContent).toBe('ⓘ');
    sitAt(container, '[data-help]', 600);
    fireEvent.click(button); await flush();
    expect(note(container)!.textContent).toContain('F1');
    // The button is at the right end of its row, so the panel hangs from that edge.
    expect(note(container)!.className).toContain('right-0');
    expect(note(container)!.className).toContain('bottom-full');
    fireEvent.click(button); await flush();
    expect(note(container)).toBeNull();
  });

  it('opens from anywhere through the shared signal, dropping below when the top is tight', async () => {
    const { container } = render(() => <HelpButton />);
    sitAt(container, '[data-help]', 30);
    setHelpOpen(true); await flush();
    expect(note(container)!.className).toContain('top-full');
    expect(height(container)).toBe('710px');                      // 768 - (30 + 20) - 8
    fireEvent.keyDown(container.querySelector('[data-help]')!, { key: 'Escape' }); await flush();
    expect(note(container)).toBeNull();
  });

  it('never grows past the view, and is not a tab stop of its own', async () => {
    const { container } = render(() => <HelpButton />);
    sitAt(container, '[data-help]', 600);
    setHelpOpen(true); await flush();
    expect(note(container)!.className).toMatch(/overflow-y-auto/);
    expect(note(container)!.getAttribute('tabindex')).toBe('-1');
    // Never taller than the side it opened on: 768 tall here, the mark at 600, so 592 above it.
    expect(height(container)).toBe('592px');
  });

  it('gives each key its own line, so the long ones are not folded into a column', async () => {
    const { container } = render(() => <HelpButton />);
    setHelpOpen(true); await flush();
    for (const term of container.querySelectorAll('dt')) {
      expect(term.className).toContain('whitespace-nowrap');
      expect(term.nextElementSibling!.tagName).toBe('DD');
    }
    expect(note(container)!.querySelector('.grid-cols-\\[auto_1fr\\]')).toBeNull();
  });
});
