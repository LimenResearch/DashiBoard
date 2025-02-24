import { A } from "../components/button";
import { TableView } from "../components/table-view";
import { getURL } from "../requests";

const headerClass = "text-xl font-semibold text-left py-2 text-blue-800";

export function Spreadsheet(props) {
    return <div>
        <p class={headerClass}>Source</p>
        <TableView metadata={props.sourceMetadata} processed={false}></TableView>
        <p class={headerClass}>Selection</p>
        <TableView metadata={props.selectionMetadata} processed={true}></TableView>
        <div class="mt-4">
            <A href={getURL("processed-data")} download positive>
                Download processed data
            </A>
        </div>
    </div>;
}