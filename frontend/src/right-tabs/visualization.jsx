import { For } from "solid-js";

export function Visualization(props) {
    return <For
        each={props.visualization.filter(x => x != null)}
        fallback={<div>No visualization available</div>}>

        {item => <div innerHTML={item}></div>}
    </For>;
}