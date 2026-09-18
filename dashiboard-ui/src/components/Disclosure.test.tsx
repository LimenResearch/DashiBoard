import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
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

  it('turns only the chevron whose own disclosure is open', () => {
    // The reported bug: nested chevrons turned when the *outer* section opened and then sat stuck,
    // because `group-open` compiles to `:is(.group:is([open]) *)` — every descendant of every open
    // group, not the nearest one.
    //
    // jsdom applies no stylesheet, so the rotation itself is unobservable here; the selector is
    // not. It is read out of the shipped CSS rather than retyped, so this fails if the rule is
    // edited back to a descendant match, and evaluated against real nested markup, so it fails for
    // the reason the bug had rather than on a string comparison.
    // Comments are stripped before matching: the rule carries a prose block explaining itself, and
    // a selector is just "everything brace-free before the `{`", so the comment came along and
    // `querySelectorAll` threw a syntax error.
    const css = readFileSync(join(process.cwd(), 'src/App.css'), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '');
    const selector = css.match(/([^{}]+)\{\s*rotate:\s*90deg;/)?.[1].trim();
    expect(selector).toBeTruthy();

    const { container } = render(() => (
      <Disclosure open summary={<span>outer</span>}>
        <Disclosure summary={<span>inner</span>}>body</Disclosure>
      </Disclosure>
    ));
    const all = [...container.querySelectorAll('.disclosure-chevron')];
    expect(all).toHaveLength(2); // one per disclosure, so the next assertion can discriminate

    const outer = container.querySelector('details') as HTMLDetailsElement;
    const inner = container.querySelector('details details') as HTMLDetailsElement;
    expect(outer.open).toBe(true);
    expect(inner.open).toBe(false);

    const turned = () => [...container.querySelectorAll(selector!)];
    expect(turned()).toEqual([all[0]]); // the outer's, and only the outer's

    inner.open = true;
    expect(turned()).toEqual(all); // both, once both are open

    outer.open = false;
    expect(turned()).toEqual([all[1]]); // the inner's alone — it tracks itself, not its ancestor
  });

  it('honours an explicit open, for the rare caller that wants one expanded', () => {
    const { container } = render(() => (
      <Disclosure open summary={<span>cluster</span>}>body</Disclosure>
    ));
    expect(details(container).open).toBe(true);
  });
});
