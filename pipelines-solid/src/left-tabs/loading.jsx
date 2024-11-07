import { createSignal, createResource } from "solid-js";
import { join } from 'path-browserify'

import { Button } from "../components/button";
import { FilePicker, DirectoryPicker } from "../components/file-picker";

async function computeFiles(data) {
    const [dirHandle, fileHandles] = data
    const resolver = fileHandle => dirHandle == null ? "" : dirHandle.resolve(fileHandle);
    const paths = await Promise.all(fileHandles.map(resolver));
    return paths.map(x => join(...x));
}

export function initPathPicker(){
    const [dirHandle, setDirHandle] = createSignal(null);
    const [fileHandles, setFileHandles] = createSignal([]);
    const [files] = createResource(() => [dirHandle(), fileHandles()], computeFiles);

    return {
        input: {dirHandle, setDirHandle, fileHandles, setFileHandles, files},
        output: files
    }
}

export function PathPicker(props) {

    const {dirHandle, setDirHandle, setFileHandles, files} = props.input;
    const [loading, setLoading] = createSignal(false);
    const onClick = async () => {
        setLoading(true);
        // TODO: add catch block here
        try {
            await props.onLoad();
        } finally {
            setLoading(false);
        }
    };

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
                {files() && files().length > 0 ? files().join(", ") : "Pick a file"}
            </span>
        </div>
        <div class="p-4">
            <Button
                    positive
                    disabled={loading() || files.loading || files() == null || files().length == 0}
                    onClick={onClick}>
                {props.confirmationMessage}
            </Button>
        </div>
    </div>;
}
