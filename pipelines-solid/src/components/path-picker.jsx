import { createEffect, createSignal } from "solid-js";
import { Button } from "./button";
import { FilePicker, DirectoryPicker } from "./file-picker";

export function PathPicker(props) {
    const [dirHandle, setDirHandle] = createSignal(null);
    const [fileHandles, setFileHandles] = createSignal([]);
    const [paths, setPaths] = createSignal([]);

    const fileOptions = {
        multiple: true
    };

    function updatePaths() {
        Promise.all(fileHandles().map(x => dirHandle().resolve(x))).then(setPaths);
    }

    function onFileClick(value) {
        setFileHandles(value);
        updatePaths();
    }

    function onDirectoryClick(value) {
        setDirHandle(value);
        updatePaths();
    }

    return <div>
        <div class="m-4">
            <DirectoryPicker onValue={onDirectoryClick}>
                {props.directoryMessage}
            </DirectoryPicker>
            <span>
                {dirHandle() === null ? "Select a directory" : dirHandle().name}
            </span>
        </div>
        <div class="m-4">
            <FilePicker onValue={onFileClick} options={fileOptions}>
                {props.fileMessage}
            </FilePicker>
            <span>
                {paths().length > 0 ? paths().map(x => x.join("/")).join(", ") : "Pick a file"}
            </span>
        </div>
        <div class="m-4">
            <Button positive onClick={() => props.onValue(paths())}>
                {props.confirmationMessage}
            </Button>
        </div>
    </div>;
}
