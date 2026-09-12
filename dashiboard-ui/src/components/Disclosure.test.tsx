import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { Disclosure, summaryAction } from './Disclosure';

afterEach(cleanup);

const details = (c: HTMLElement) => c.querySelector('details') as HTMLDetailsElement;

describe('Disclosure', () => {
  it('starts folded, so a list of them reads as a list of names', () => {
    const { container } = render(() => (
      <Disclosure summary={<span>cluster</span>}>body</Disclosure>
    ));
    expect(details(container).open).toBe(false);
  });

  it('opens when its summary is clicked', () => {
    const { container } = render(() => (
      <Disclosure summary={<span>cluster</span>}>body</Disclosure>
    ));
    fireEvent.click(container.querySelector('summary')!);
    expect(details(container).open).toBe(true);
  });

  it('runs an action on the folded line', () => {
    // The *other* half of this — that the click does not also toggle the disclosure — cannot be
    // verified here. jsdom toggles `<details>` on a click landing directly on `<summary>` but not
    // on one bubbling up from a descendant button, so removing `preventDefault` from
    // `summaryAction` leaves every assertion green. Measured, not assumed: the mutation was run.
    //
    // The guard stays because browsers do toggle on the bubbled click. This test covers the half
    // it can and says so, rather than asserting `open === false` and reading as though it proved
    // something.
    let ran = 0;
    const { getByText } = render(() => (
      <Disclosure
        summary={
          <>
            <span>cluster</span>
            <button type="button" onClick={summaryAction(() => { ran += 1; })}>
              Remove
            </button>
          </>
        }
      >
        body
      </Disclosure>
    ));
    fireEvent.click(getByText('Remove'));
    expect(ran).toBe(1);
  });

  it('honours an explicit open, for the rare caller that wants one expanded', () => {
    const { container } = render(() => (
      <Disclosure open summary={<span>cluster</span>}>body</Disclosure>
    ));
    expect(details(container).open).toBe(true);
  });
});
