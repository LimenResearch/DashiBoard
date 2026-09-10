import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { Tabs } from './Tabs';

afterEach(cleanup);

const tabs = (c: HTMLElement, group: string) =>
  [...c.querySelectorAll(`[data-tabs="${group}"] [role=tab]`)] as HTMLButtonElement[];

describe('Tabs', () => {
  it('marks exactly one tab selected, and reports the one clicked', () => {
    let picked: string | null = null;
    const { container } = render(() => (
      <Tabs group="demo" items={['a', 'b', 'c']} active="b" onSelect={(t) => { picked = t; }} />
    ));
    const found = tabs(container, 'demo');
    expect(found.map((t) => t.getAttribute('data-tab'))).toEqual(['a', 'b', 'c']);
    expect(found.map((t) => t.getAttribute('aria-selected'))).toEqual(['false', 'true', 'false']);
    fireEvent.click(found[2]);
    expect(picked).toBe('c');
  });

  it('names its group, so nested strips stay distinguishable', () => {
    // A picker's kind tabs live inside a page whose sections are also tabs. Without a group name
    // a query for one strip selects both.
    const { container } = render(() => (
      <>
        <Tabs group="outer" items={['x']} active="x" onSelect={() => {}} />
        <Tabs group="inner" items={['y']} active="y" onSelect={() => {}} />
      </>
    ));
    expect(tabs(container, 'outer')).toHaveLength(1);
    expect(tabs(container, 'inner')).toHaveLength(1);
  });

  it('shows a count, since a selection inside a closed tab is otherwise invisible', () => {
    const { container } = render(() => (
      <Tabs
        group="demo" items={['cols', 'groups']} active="cols" onSelect={() => {}}
        count={(t) => (t === 'groups' ? 2 : 0)}
      />
    ));
    const [cols, groups] = tabs(container, 'demo');
    expect(cols.textContent).toBe('cols'); // nothing chosen, so no count
    expect(groups.textContent).toContain('2');
  });
});
