import { describe, it, expect, afterEach, beforeEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush, reconcile, snapshot } from 'solid-js';
import { Presets } from './Presets';
import { PRESETS_STORE } from '../stores';
import type { Defs, IRNode } from '../ir';
import payload from '../fixtures/card-ir.json';

const defs = payload.defs as Defs;
const cards = payload.cards as unknown as { [type: string]: IRNode };
const mount = () => render(() => <Presets cards={cards} defs={defs} />);
/** The marker sits on the label; the control is the button around it. */
const button = (c: HTMLElement) => c.querySelector('[data-presets]')!.closest('button') as HTMLButtonElement;
const panel = (c: HTMLElement) => c.querySelector('[role=dialog]');

afterEach(cleanup);
beforeEach(() => { PRESETS_STORE[1](reconcile({})); });

describe('Presets', () => {
  it('is closed until asked, and says how many fields carry one', async () => {
    const { container } = mount();
    expect(panel(container)).toBeNull();
    expect(button(container).textContent).toBe('Presets');
    PRESETS_STORE[1]((d) => { d.partition = { cols: 'TEMP' }; }); await flush();
    expect(button(container).textContent).toBe('Presets 1');
  });

  it('draws one picker per shared field, in the order presetFields gives', async () => {
    const { container } = mount();
    fireEvent.click(button(container)); await flush();
    expect([...container.querySelectorAll('[data-selector-name]')].map((e) => e.textContent))
      .toEqual(['partition', 'group_by', 'order_by', 'weights']);
  });

  it('writes what a picker holds, and forgets a field once it is emptied', async () => {
    const { container } = mount();
    fireEvent.click(button(container)); await flush();
    const box = container.querySelectorAll('[data-entry]')[0] as HTMLInputElement;
    fireEvent.input(box, { target: { value: 'c' } }); await flush();
    fireEvent.keyDown(box, { key: 'Tab' }); await flush();
    fireEvent.input(box, { target: { value: 'TEMP' } }); await flush();
    fireEvent.keyDown(box, { key: 'Enter' }); await flush();
    expect(snapshot(PRESETS_STORE[0])).toEqual({ partition: { cols: 'TEMP' } });
    fireEvent.click(container.querySelector('[data-chip-remove]')!); await flush();
    expect(snapshot(PRESETS_STORE[0])).toEqual({});
  });

  it('keeps the tab round inside itself, so no field is the one that closes it', async () => {
    const { container } = mount();
    fireEvent.click(button(container)); await flush();
    const stops = [...container.querySelectorAll<HTMLElement>('[role=dialog] button, [role=dialog] input')]
      .filter((el) => el.tabIndex !== -1 && el.closest('[hidden]') === null);
    stops.at(-1)!.focus();
    expect(fireEvent.keyDown(stops.at(-1)!, { key: 'Tab' })).toBe(false);   // prevented
    await flush();
    expect(document.activeElement).toBe(stops[0]);
    expect(panel(container)).not.toBeNull();
    expect(fireEvent.keyDown(stops[0], { key: 'Tab', shiftKey: true })).toBe(false);
    await flush();
    expect(document.activeElement).toBe(stops.at(-1));
  });

  it('closes on Escape, on a click outside and on a second click of the button', async () => {
    const { container } = mount();
    fireEvent.click(button(container)); await flush();
    fireEvent.keyDown(panel(container)!, { key: 'Escape' }); await flush();
    expect(panel(container)).toBeNull();
    expect(document.activeElement).toBe(button(container));
    fireEvent.click(button(container)); await flush();
    fireEvent.focusOut(panel(container)!, { relatedTarget: document.body }); await flush();
    expect(panel(container)).toBeNull();
    fireEvent.click(button(container)); await flush();
    fireEvent.click(button(container)); await flush();
    expect(panel(container)).toBeNull();
  });
});
