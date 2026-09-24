import { describe, it, expect, afterEach, beforeEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { ThemeToggle } from './ThemeToggle';
import { setThemeMode, themeMode } from '../theme';

beforeEach(() => setThemeMode('light'));
afterEach(cleanup);

describe('ThemeToggle', () => {
  it('labels where a click goes, not where you are', () => {
    // The control is an affordance, not a status readout — which is also why there is no third
    // "system" state to display.
    const { getByRole } = render(() => <ThemeToggle />);
    expect(getByRole('button').getAttribute('aria-label')).toBe('switch to dark mode');
  });

  it('flips the mode, and relabels itself', async () => {
    const { getByRole } = render(() => <ThemeToggle />);
    fireEvent.click(getByRole('button'));
    await flush();
    expect(themeMode()).toBe('dark');
    expect(getByRole('button').getAttribute('aria-label')).toBe('switch to light mode');
  });
});
