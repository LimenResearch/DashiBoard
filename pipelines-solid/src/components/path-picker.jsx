import { createSignal, createResource } from "solid-js";
import { Button } from "./button";
import { FilePicker, DirectoryPicker } from "./file-picker";

export function PathPicker(props) {
    const [dirHandle, setDirHandle] = createSignal(null);
    const [fileHandles, setFileHandles] = createSignal([]);

    function computePaths(data) {
        const [dir, files] = data
        const resolver = x => dir == null ? [] : dir.resolve(x);
        return Promise.all(files.map(resolver));
    }

    const [paths] = createResource(() => [dirHandle(), fileHandles()], computePaths);

    const fileOptions = {
        multiple: true
    };

    return <div>
        <div class="p-4">
            <DirectoryPicker onValue={setDirHandle}>
                {props.directoryMessage}
            </DirectoryPicker>
            <span>
                {dirHandle() == null ? "Select a directory" : dirHandle().name}
            </span>
        </div>
        <div class="p-4">
            <FilePicker disabled={dirHandle() == null} onValue={setFileHandles} options={fileOptions}>
                {props.fileMessage}
            </FilePicker>
            <span>
                {paths() && paths().length > 0 ? paths().map(x => x.join("/")).join(", ") : "Pick a file"}
            </span>
        </div>
        <div class="p-4">
            <Button
                    positive
                    disabled={paths.loading || paths() == null || paths().length == 0}
                    onClick={() => props.onValue(paths())}>
                {props.confirmationMessage}
            </Button>
        </div>
    </div>;
}
