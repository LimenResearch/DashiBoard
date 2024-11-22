import { TableView } from "../components/table-view";

const headerClass = "text-xl font-semibold text-left py-2 text-blue-800";

export function Spreadsheet(props) {
    return <div>
        <p class={headerClass}>Source</p>
        <TableView metadata={props.source} processed={false}></TableView>
        <p class={headerClass}>Selection</p>
        <TableView metadata={props.selection} processed={true}></TableView>
    </div>
}