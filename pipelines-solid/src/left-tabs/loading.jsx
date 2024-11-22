import { createSignal, createResource } from "solid-js";
import { join } from 'path-browserify'

import { Button } from "../components/button";
import { FilePicker, DirectoryPicker } from "../components/file-picker";
import { postRequest } from "../requests";

async function computeFiles(data) {
    const [dirHandle, fileHandles] = data
    const resolver = fileHandle => dirHandle == null ? "" : dirHandle.resolve(fileHandle);
    const paths = await Promise.all(fileHandles.map(resolver));
    return paths.map(x => join(...x));
}

export function initLoader(){
    const [dirHandle, setDirHandle] = createSignal(null);
    const [fileHandles, setFileHandles] = createSignal([]);
    const [metadata, setMetadata] = createSignal([]);
    const [files] = createResource(() => [dirHandle(), fileHandles()], computeFiles);

    return {
        input: {
            dirHandle: [dirHandle, setDirHandle],
            fileHandles: [fileHandles, setFileHandles],
            metadata: [metadata, setMetadata],
            files
        },
        output: metadata
    }
}

export function Loader(props) {

    const input = props.input;
    const [dirHandle, setDirHandle] = input.dirHandle;
    const [fileHandles, setFileHandles] = input.fileHandles;
    const [metadata, setMetadata] = input.metadata;
    const files = input.files;

    const [loading, setLoading] = createSignal(false);

    function loadData() {
        setLoading(true);
        const body = {files: files()};
        postRequest("load", body)
            .then(x => x.json())
            .then(setMetadata)
            .catch(error => console.log(error))
            .finally(setLoading(false));
    }

    const fileOptions = {
        multiple: true
    };

    return <div>
        <div class="p-4">
            <DirectoryPicker onValue={setDirHandle}>
                {props.directoryMessage || "Enable folder"}
            </DirectoryPicker>
            <span>
                {dirHandle() == null ? "Select a directory" : dirHandle().name}
            </span>
        </div>
        <div class="p-4">
            <FilePicker disabled={dirHandle() == null} onValue={setFileHandles} options={fileOptions}>
                {props.fileMessage || "Choose files"}
            </FilePicker>
            <span>
                {files() && files().length > 0 ? files().join(", ") : "Pick a file"}
            </span>
        </div>
        <div class="p-4">
            <Button
                    positive
                    disabled={loading() || files.loading || files() == null || files().length == 0}
                    onClick={loadData}>
                {props.confirmationMessage || "Load"}
            </Button>
        </div>
    </div>;
}
