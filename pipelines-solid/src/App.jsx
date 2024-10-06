import { createSignal } from "solid-js";
import { PathPicker } from "./components/path-picker";

export function App() {
    const [paths, setPaths] = createSignal([]);
    return <PathPicker permissionMessage="Enable folder"
        fileMessage="Load files" onInput={setPaths}>
    </PathPicker>;
}
