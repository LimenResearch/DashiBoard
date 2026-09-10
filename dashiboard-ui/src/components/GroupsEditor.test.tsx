import { describe, it, expect, afterEach, beforeEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { GroupsEditor } from './GroupsEditor';
import { importCards, exportCards, emptyCards, addGroup, setGroup } from '../stores';
import type { Defs } from '../ir';
import payload from '../fixtures/card-ir.json';

const defs = payload.defs as Defs;
const mount = () => render(() => <GroupsEditor defs={defs} />);
const nameFields = (c: HTMLElement) =>
  [...c.querySelectorAll('input[aria-label="group name"]')] as HTMLInputElement[];

afterEach(cleanup);
beforeEach(() => importCards(emptyCards()));

describe('GroupsEditor', () => {
  it('says the document defines none, rather than showing an empty area', async () => {
    const { container } = mount();
    expect(container.textContent).toContain('No groups defined');
  });

  it('adds a group, which is what makes the groups tab in every picker non-empty', async () => {
    const { getByText, container } = mount();
    fireEvent.click(getByText('Add group'));
    await flush();
    expect(nameFields(container).map((f) => f.value)).toEqual(['group']);
    expect(exportCards().groups).toEqual({ group: [] });
  });

  it('edits a group with the same picker a card field uses', async () => {
    addGroup('weather');
    const { container } = mount();
    await flush();
    const box = [...container.querySelectorAll('input[type=checkbox]')].find(
      (b) => (b as HTMLInputElement).value === 'TEMP',
    )!;
    fireEvent.click(box);
    await flush();
    expect(exportCards().groups.weather).toEqual([{ cols: ['TEMP'] }]);
  });

  it('renames a group, carrying its selectors with it', async () => {
    addGroup('g');
    setGroup('g', [{ cols: 'TEMP' }]);
    const { container } = mount();
    await flush();
    const field = nameFields(container)[0];
    field.value = 'weather';
    fireEvent.change(field);
    await flush();
    expect(exportCards().groups).toEqual({ weather: [{ cols: 'TEMP' }] });
  });

  it('refuses a rename onto an existing group, and puts the old name back', async () => {
    // Silently merging would discard one group's selectors, and the field would keep showing the
    // name the user typed — so the document and the screen would disagree.
    addGroup('a');
    setGroup('a', [{ cols: 'TEMP' }]);
    addGroup('b');
    const { container } = mount();
    await flush();
    const field = nameFields(container)[1];
    field.value = 'a';
    fireEvent.change(field);
    await flush();
    expect(Object.keys(exportCards().groups)).toEqual(['a', 'b']);
    expect(exportCards().groups.a).toEqual([{ cols: 'TEMP' }]);
    expect(nameFields(container)[1].value).toBe('b'); // reverted on screen too
    expect(container.textContent).toMatch(/already/i);
  });

  it('removes a group', async () => {
    addGroup('a');
    const { getByText } = mount();
    await flush();
    fireEvent.click(getByText('Remove'));
    await flush();
    expect(exportCards().groups).toEqual({});
  });
});
