import {useState} from "react"
import {PathPicker} from "./components/path-picker";

export function App() {
    const [state, setState] = useState([[], null]);
    console.log(state);
    return <PathPicker permissionMessage="Enable folder"
        fileMessage="Load files" state={state} setState={setState}>
    </PathPicker>;
}
