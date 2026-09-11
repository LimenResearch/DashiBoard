import { describe, it, expect, beforeEach } from 'vitest';
import { flush } from 'solid-js';
import {
  applyTheme,
  initialMode,
  modeFromSearch,
  setThemeMode,
  themeMode,
  toggleTheme,
} from './theme';

beforeEach(() => setThemeMode('light'));

describe('modeFromSearch', () => {
  it('reads an explicit request', () => {
    expect(modeFromSearch('?theme=dark')).toBe('dark');
    expect(modeFromSearch('?theme=light')).toBe('light');
  });

  it('says nothing when the URL says nothing, rather than guessing', () => {
    expect(modeFromSearch('')).toBeNull();
    expect(modeFromSearch('?other=1')).toBeNull();
    expect(modeFromSearch('?theme=midnight')).toBeNull(); // not a mode we have
  });
});

describe('initialMode', () => {
  it('lets the URL win, since that is how a frame learns the mode before first paint', () => {
    expect(initialMode('?theme=dark', false)).toBe('dark');
    expect(initialMode('?theme=light', true)).toBe('light');
  });

  it('falls back to the OS, with no third state to represent', () => {
    expect(initialMode('', true)).toBe('dark');
    expect(initialMode('', false)).toBe('light');
  });
});

describe('applyTheme', () => {
  it('adds and removes the class the palette is keyed on', () => {
    const root = document.createElement('html');
    applyTheme('dark', root);
    expect(root.classList.contains('dark')).toBe(true);
    applyTheme('light', root);
    expect(root.classList.contains('dark')).toBe(false);
  });

  it('is idempotent, so applying twice does not toggle', () => {
    const root = document.createElement('html');
    applyTheme('dark', root);
    applyTheme('dark', root);
    expect(root.classList.contains('dark')).toBe(true);
  });
});

describe('toggleTheme', () => {
  it('flips between exactly two states', async () => {
    // Solid 2 defers signal updates, so each flip needs settling before it can be read back.
    expect(themeMode()).toBe('light');
    toggleTheme();
    await flush();
    expect(themeMode()).toBe('dark');
    toggleTheme();
    await flush();
    expect(themeMode()).toBe('light');
  });
});
