import download from "downloadjs";
import { Button } from "../components/button";
import { TableView } from "../components/table-view";
import { postRequest } from "../requests";

const headerClass = "text-xl font-semibold text-left py-2 text-blue-800";

// TODO use streams
function downloadData() {
    postRequest("download", {})
        .then(res => res.blob())
        .then(blob => download(blob));
}

export function Spreadsheet(props) {
    return <div>
        <p class={headerClass}>Source</p>
        <TableView metadata={props.source} processed={false}></TableView>
        <p class={headerClass}>Selection</p>
        <TableView metadata={props.selection} processed={true}></TableView>
        <div class="mt-4">
            <Button onClick={downloadData} positive>
                Download processed data
            </Button>
        </div>
    </div>
}