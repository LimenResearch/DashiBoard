import { createEffect, onCleanup } from 'solid-js';
import { instance } from '@viz-js/viz';

// Renders the Graphviz DOT that `evaluate-pipeline` returns as `graph`. Kept in its own
// component because loading viz is asynchronous and its failure should not take the page with it.

type GraphProps = { dot: string };

export function Graph(props: GraphProps) {
  let host!: HTMLDivElement;
  let disposed = false;
  onCleanup(() => {
    disposed = true;
  });

  createEffect(
    () => props.dot,
    (dot: string) => {
      if (!host) return;
      instance()
        .then((viz) => {
          if (disposed || !host) return;
          host.replaceChildren(viz.renderSVGElement(dot));
        })
        .catch((error: unknown) => {
          if (disposed || !host) return;
          host.textContent = `Could not render the graph: ${String(error)}`;
        });
    },
  );

  // `dashi-graph` is the hook App.css retints through: Graphviz writes its colours as SVG
  // presentation attributes, which CSS outranks, so a server-generated drawing can still follow
  // the viewer's theme.
  return <div ref={host} class="dashi-graph overflow-x-auto" />;
}
