import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { MapField } from './MapField';

afterEach(cleanup);

const mount = (over: Partial<Parameters<typeof MapField>[0]> = {}) => {
  const written: (Record<string, string> | undefined)[] = [];
  const view = render(() => (
    <MapField
      label="input_transforms" id="n-input_transforms" listName="inputs"
      columns={['TEMP', 'PRES']} stale={[]} values={['log', 'sqrt']} held={{}}
      fixed={() => false} onChange={(next) => { written.push(next); }}
      {...over}
    />
  ));
  return { ...view, written };
};
const select = (c: HTMLElement, column: string) =>
  c.querySelector(`[data-row="${column}"] select`) as HTMLSelectElement | null;
const pick = async (c: HTMLElement, column: string, value: string) => {
  const control = select(c, column)!;
  control.value = value; fireEvent.change(control); await flush();
};

describe('MapField', () => {
  it('draws a row per column, identity until something else is chosen', () => {
    const { container } = mount({ held: { PRES: 'sqrt' } });
    expect([...container.querySelectorAll('[data-row]')].map((r) => r.getAttribute('data-row'))).toEqual(['TEMP', 'PRES']);
    expect([...select(container, 'TEMP')!.options].map((o) => o.value)).toEqual(['identity', 'log', 'sqrt']);
    expect(select(container, 'TEMP')!.value).toBe('identity');
    expect(select(container, 'PRES')!.value).toBe('sqrt');
  });

  it('writes the choice, and only what is not identity', async () => {
    const { container, written } = mount({ held: { PRES: 'sqrt' } });
    await pick(container, 'TEMP', 'log');
    expect(written.at(-1)).toEqual({ PRES: 'sqrt', TEMP: 'log' });
  });

  it('removes the entry, and the whole map with the last one, on identity', async () => {
    const { container, written } = mount({ held: { PRES: 'sqrt' } });
    await pick(container, 'PRES', 'identity');
    expect(written.at(-1)).toBeUndefined();
  });

  it('offers no transform for a column that cannot take one', () => {
    const { container } = mount({ fixed: (column) => column === 'TEMP' });
    expect(select(container, 'TEMP')).toBeNull();
    expect(container.querySelector('[data-row="TEMP"]')!.textContent).toMatch(/categorical/);
    expect(select(container, 'PRES')).not.toBeNull();
  });

  // What the server will refuse is shown, so it can be seen and cleared.
  it('sets a stale entry apart, fixed and removable', async () => {
    const { container, written } = mount({ held: { PRES: 'log', GONE: 'sqrt' }, stale: ['GONE'] });
    const row = container.querySelector('[data-row="GONE"]') as HTMLElement;
    expect(row.hasAttribute('data-stale')).toBe(true);
    expect(row.textContent).toMatch(/not among the inputs/);
    expect(select(container, 'GONE')!.disabled).toBe(true);
    expect(select(container, 'GONE')!.value).toBe('sqrt');
    fireEvent.click(row.querySelector('button')!); await flush();
    expect(written.at(-1)).toEqual({ PRES: 'log' });
  });

  it('draws nothing with no transform to choose, or no column to choose it for', () => {
    expect(mount({ values: [] }).container.textContent).toBe('');
    cleanup();
    expect(mount({ columns: [] }).container.textContent).toBe('');
  });
});
