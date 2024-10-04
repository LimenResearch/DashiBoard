import {useState} from "react"
import {PathPicker} from "./components/path-picker";

export function App() {
    const [paths, setPaths] = useState([]);
    console.log(paths);
    return <PathPicker permissionMessage="Enable folder"
        fileMessage="Load files" setState={setPaths}>
    </PathPicker>;
}
