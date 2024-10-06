import { createSignal } from "solid-js";
import { Button } from "./button";

export function FilePicker(props) {
    async function loadingHandler() {
        const options = {
            multiple: true,
        };
        const handles = await window.showOpenFilePicker(options);
        const paths = await Promise.all(handles.map(x => props.dirHandle.resolve(x)));
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
    return <div>
        <FolderPermission onInput={setDirHandle}>
            {props.permissionMessage}
        </FolderPermission>
        <FilePicker dirHandle={dirHandle()} onInput={props.onInput}>
            {props.fileMessage}
        </FilePicker>
    </div>;
}
