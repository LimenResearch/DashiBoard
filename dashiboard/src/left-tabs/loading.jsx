import { createSignal } from "solid-js";

import { Button } from "../components/button";
import { FilePicker } from "../components/file-picker";
import { postRequest } from "../requests";

const source = "data";
const extensions = [".csv", ".tsv", ".txt", ".json", ".parquet"];

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
            .catch(error => console.log(error))
            .finally(setLoading(false));
    }

    return <div>
        <div class="p-4">
            <FilePicker
                    multiple
                    onChange={setFiles}
                    source={source}
                    extensions={extensions}>
            </FilePicker>
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
