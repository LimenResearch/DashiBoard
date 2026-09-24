import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, waitFor } from '@solidjs/testing-library';
import { Graph } from './Graph';

afterEach(cleanup);

const DOT = `digraph G{
  bgcolor = "transparent";
  subgraph cards {
    node [shape = "box" style = "filled"];
    "1" [label = "rescale" fillcolor = "white"];
    "2" [label = "split" fillcolor = "transparent"];
  }
  edge [arrowhead = "normal"];
  "1" -> {"2"};
}`;

describe('Graph', () => {
  it('renders the DOT it is given', async () => {
    const { container } = render(() => <Graph dot={DOT} />);
    await waitFor(() => expect(container.querySelector('svg')).not.toBeNull());
    expect(container.textContent).toContain('rescale');
    expect(container.textContent).toContain('split');
  });

  it('carries the hook its theming is attached to', () => {
    const { container } = render(() => <Graph dot={DOT} />);
    expect(container.querySelector('.dashi-graph')).not.toBeNull();
  });

  it('emits the attributes the theme selectors match on', async () => {
    // The retint works by attribute selector, so these are a contract with Graphviz rather than
    // an implementation detail. If its output shape changes, the graph silently goes back to
    // black-on-black in dark mode — which is exactly the failure that has no symptom in light.
    const { container } = render(() => <Graph dot={DOT} />);
    await waitFor(() => expect(container.querySelector('svg')).not.toBeNull());
    const svg = container.querySelector('svg')!;
    expect(svg.querySelector('polygon[fill="white"]')).not.toBeNull(); // a node to be recomputed
    expect(svg.querySelector('polygon[fill="none"]')).not.toBeNull();  // one that is current
    expect(svg.querySelector('path[stroke="black"]')).not.toBeNull();  // an edge
    expect(svg.querySelector('polygon[fill="black"]')).not.toBeNull(); // its arrowhead
    // `<text>` carries no fill of its own — which is why it needs the rule at all.
    expect(svg.querySelector('text')!.hasAttribute('fill')).toBe(false);
  });
});
