import { createSignal } from "solid-js";

import { Button } from "../components/button";
import { FilePicker } from "../components/file-picker";
import { postRequest } from "../requests";

export function initLoader(){
    const [metadata, setMetadata] = createSignal([]);

    return {
        input: {
            metadata: [metadata, setMetadata],
        },
        output: metadata
    }
}

export function Loader(props) {
    const [metadata, setMetadata] = props.input.metadata;
    const [files, setFiles] = createSignal([]);
    const [loading, setLoading] = createSignal(false);

    function loadData() {
        setLoading(true);
        const body = {files: files()};
        postRequest("load", body)
            .then(x => x.json())
            .then(setMetadata)
            .catch(error => window.alert(error))
            .finally(setLoading(false));
    }

    return <div>
        <div class="p-4">
            <FilePicker required multiple onChange={setFiles}></FilePicker>
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
