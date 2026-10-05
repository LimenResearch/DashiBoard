import { describe, it, expect, beforeEach } from 'vitest';
import { flush } from 'solid-js';
import { folderLabel, setFolders } from './folders';

describe('where a kind of file is', () => {
  beforeEach(async () => { setFolders(null); await flush(); });

  it('is the layout\'s folder until the server says otherwise', () => {
    expect(folderLabel('table')).toBe('data/');
    expect(folderLabel('cards')).toBe('pipeline/');
    expect(folderLabel('filters')).toBe('filter/');
  });

  // A workspace may keep a kind elsewhere, or everything at its root: the form says what is so.
  it('is what the server says: another folder, a path elsewhere, or the workspace itself', async () => {
    setFolders({ table: 'tables', cards: '', filters: '/mnt/filters' });
    await flush();           // a write is staged until the next tick
    expect(folderLabel('table')).toBe('tables/');
    expect(folderLabel('cards')).toBe('the workspace');
    expect(folderLabel('filters')).toBe('/mnt/filters/');
  });
});
