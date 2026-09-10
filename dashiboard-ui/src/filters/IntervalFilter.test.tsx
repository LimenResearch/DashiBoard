import { describe, it, expect, afterEach, beforeEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { IntervalFilter } from './IntervalFilter';
import { FILTERS_STORE, Interval } from '../stores';

const [filters, setFilters] = FILTERS_STORE;
const summary = { min: 0, max: 10 };

const fields = (c: HTMLElement) =>
  [...c.querySelectorAll('input[type=number]')] as HTMLInputElement[];

async function open(c: HTMLElement, getByText: (t: string) => HTMLElement) {
  fireEvent.click(getByText('TEMP'));
  await flush();
  return fields(c);
}

beforeEach(() => setFilters(() => ({ numerical: {}, categorical: {} })));
afterEach(cleanup);

describe('IntervalFilter', () => {
  it('records a bound that was typed', async () => {
    const { container, getByText } = render(() => (
      <IntervalFilter name="TEMP" summary={summary} />
    ));
    const [low] = await open(container, getByText);
    low.value = '3';
    fireEvent.change(low);
    await flush();
    expect(filters.numerical.TEMP?.min).toBe(3);
    expect(filters.numerical.TEMP?.max).toBe(10);
  });

  it('marks both bounds invalid when they cross, rather than storing an empty range', async () => {
    // Nothing downstream complains about min > max: it selects no rows, which looks like data
    // rather than like a mistake. This is what `Input`'s invalid state exists for.
    setFilters((draft) => {
      draft.numerical.TEMP = new Interval(8, 2);
    });
    const { container, getByText } = render(() => (
      <IntervalFilter name="TEMP" summary={summary} />
    ));
    const shown = await open(container, getByText);
    expect(shown).toHaveLength(2);
    for (const field of shown) {
      expect(field.getAttribute('aria-invalid')).toBe('true');
    }
  });

  it('ignores a cleared field instead of storing NaN', async () => {
    const { container, getByText } = render(() => (
      <IntervalFilter name="TEMP" summary={summary} />
    ));
    const [low] = await open(container, getByText);
    low.value = '3';
    fireEvent.change(low);
    await flush();
    low.value = '';
    fireEvent.change(low);
    await flush();
    expect(Number.isNaN(filters.numerical.TEMP?.min)).toBe(false);
    expect(filters.numerical.TEMP?.min).toBe(3); // the last good value stands
  });
});
