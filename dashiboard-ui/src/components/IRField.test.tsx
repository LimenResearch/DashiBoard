import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup } from '@solidjs/testing-library';
import { IRField } from './IRField';
import type { Defs, IRNode } from '../ir';
import payload from '../fixtures/card-ir.json';

const defs = payload.defs as Defs;
const cards = payload.cards as Record<string, IRNode>;

afterEach(cleanup);

describe('IRField', () => {
  it('renders one labelled control per property, in declaration order', () => {
    const node: IRNode = {
      type: 'object',
      title: 'Rescale',
      properties: [
        { key: 'suffix', required: true, value: { type: 'string', minLength: 1 } },
        { key: 'target_suffix', required: false, value: { type: 'string' } },
      ],
    };
    const { container } = render(() => (
      <IRField node={node} defs={defs} label="rescale" value={{}} onChange={() => {}} />
    ));
    // exact, not substring: 'target_suffix' contains 'suffix', so a substring check would
    // pass even with the order reversed.
    const labels = [...container.querySelectorAll('label')].map((l) => l.textContent ?? '');
    expect(labels).toEqual(['suffix*', 'target_suffix']);
    // The marker follows the name rather than leading it — an annotation on the field, not the
    // first character of its label. Asserted because it is the kind of thing a later tidy moves
    // back without noticing it was a decision.
    expect(labels[0].startsWith('*')).toBe(false);
    expect(labels[0].endsWith('*')).toBe(true);
  });

  it('passes numeric bounds through to the input', () => {
    const node: IRNode = { type: 'number', minimum: 0, maximum: 1 };
    const { container } = render(() => (
      <IRField node={node} defs={defs} label="percentile" value={0.5} onChange={() => {}} />
    ));
    const input = container.querySelector('input') as HTMLInputElement;
    expect(input.type).toBe('number');
    expect(input.min).toBe('0');
    expect(input.max).toBe('1');
  });

  it('reports a text edit as a string', () => {
    let seen: unknown = null;
    const { container } = render(() => (
      <IRField
        node={{ type: 'string' }} defs={defs} label="suffix"
        value="hat" onChange={(v) => { seen = v; }}
      />
    ));
    const input = container.querySelector('input') as HTMLInputElement;
    input.value = 'zscored';
    input.dispatchEvent(new Event('change', { bubbles: true }));
    expect(seen).toBe('zscored');
  });

  it('reports a numeric enum choice as a number, not a string', () => {
    // IntegerIR(enum = [1, 2]) on the tiles card: the document must carry 1, not "1".
    let seen: unknown = null;
    const { container } = render(() => (
      <IRField
        node={{ type: 'integer', enum: [1, 2] }} defs={defs} label="tiles"
        value={1} onChange={(v) => { seen = v; }}
      />
    ));
    const select = container.querySelector('select') as HTMLSelectElement;
    select.value = '2';
    select.dispatchEvent(new Event('change', { bubbles: true }));
    expect(seen).toBe(2);
    expect(typeof seen).toBe('number');
  });

  it('renders a variables reference as the selector picker, not a flat list', () => {
    const { container } = render(() => (
      <IRField
        node={{ $ref: '#/$defs/variables' }} defs={defs} label="inputs"
        value={[]} onChange={() => {}}
      />
    ));
    // A tab per selector kind, and the open one lists its vocabulary a value at a time.
    const kinds = [...container.querySelectorAll('[role=tab]')].map((e) =>
      e.getAttribute('data-tab'),
    );
    expect(kinds).toEqual(['cols', 'groups', 'nodes']); // display order, not the oneOf's
    const values = [...container.querySelectorAll('[data-value]')].map((e) =>
      e.getAttribute('data-value'),
    );
    expect(values).toContain('TEMP');
    expect(values).toContain('cbwd');
    // each value carries a switch, because it holds a *list* of qualifications rather than a flag
    expect(container.querySelectorAll('[role=switch]').length).toBe(values.length);
  });

  it('shows only the chosen variant subform', () => {
    const method = (cards.split as { properties: { key: string; value: IRNode }[] })
      .properties.find((p) => p.key === 'method')!.value;
    const { container } = render(() => (
      <IRField
        node={method} defs={defs} label="method"
        value={{ type: 'percentile', percentile: 0.9 }} onChange={() => {}}
      />
    ));
    const labels = [...container.querySelectorAll('label')].map((l) => l.textContent ?? '');
    expect(labels.some((l) => l.includes('percentile'))).toBe(true);
    expect(labels.some((l) => l.includes('tiles'))).toBe(false); // the other branch stays hidden
  });

  it('says so plainly when the IR does not describe a field', () => {
    const { container } = render(() => (
      <IRField node={{}} defs={defs} label="inputs" value={null} onChange={() => {}} />
    ));
    expect(container.textContent).toMatch(/not described/i);
    expect(container.querySelector('input')).toBeNull(); // no textarea pretending otherwise
  });
});
