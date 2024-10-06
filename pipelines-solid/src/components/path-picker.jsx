import { createSignal } from "solid-js";
import { Button } from "./button";

export function FilePicker(props) {
    async function loadingHandler() {
        const options = {
            multiple: true,
        };
        const handles = await window.showOpenFilePicker(options);
        const paths = await Promise.all(handles.map(
            handle => props.dirHandle.resolve(handle)
        ));
        props.onInput(paths);
    }

    return <Button positive onClick={loadingHandler}>{props.children}</Button>;
}

export function FolderPermission(props) {
    async function dirHandler() {
        const dirHandle = await window.showDirectoryPicker();
        props.onInput(dirHandle);
    }

    return <Button positive onClick={dirHandler}>{props.children}</Button>;
}

export function PathPicker(props) {
    const [dirHandle, setDirHandle] = createSignal(null);
    const [paths, setPaths] = createSignal([]);

    return <div>
        <div class="m-4">
            <FolderPermission onInput={setDirHandle}>
                {props.permissionMessage}
            </FolderPermission>
            <span>
                {dirHandle() === null ? "Select a directory" : dirHandle().name}
            </span>
        </div>
        <div class="m-4">
            <FilePicker dirHandle={dirHandle()} onInput={setPaths}>
                {props.fileMessage}
            </FilePicker>
            <span>
                {paths().length > 0 ? paths().map(x => x.join("/")).join(", ") : "Pick a file"}
            </span>
        </div>
        <div class="m-4">
            <Button positive onClick={() => props.onInput(paths())}>
                {props.confirmationMessage}
            </Button>
        </div>
    </div>;
}
