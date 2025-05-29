import { A, Button } from "../components/button";
import { TableView } from "../components/table-view";
import { downloadJSON, getURL } from "../requests";

const headerClass = "text-xl font-semibold text-left py-2 text-blue-800";

function downloadReport(report, cards) {
    const list = cards.map((card, i) => ({card, report: report[i]}));
    const str = JSON.stringify(list);
    downloadJSON("report.json", str);
}

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
            <Button onClick={() => downloadReport(props.report, props.cards)} download positive>
                Download report
            </Button>
        </div>
    </div>;
}