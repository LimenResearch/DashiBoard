import { instance } from "@viz-js/viz";
import { createEffect } from "solid-js";

export function Graph(props) {
    let graphDiv;

    createEffect(() => {
        // This is needed here to trigger the effect
        const graph = props.graph;
        instance().then(viz => {
            if (graph) {
                const svg = viz.renderSVGElement(graph);
                graphDiv.replaceChildren(svg);
            }
        });
    })

    return <div ref={graphDiv}></div>;
}