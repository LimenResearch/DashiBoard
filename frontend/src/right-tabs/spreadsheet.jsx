import { A } from "../components/button";
import { DownloadJSON } from "../components/json";
import { TableView } from "../components/table-view";
import { getURL } from "../requests";

const headerClass = "text-xl font-semibold text-left py-2 text-blue-800";

export function Spreadsheet(props) {
  const reportList = () => {
    const { cards, report } = props;
    return cards.map((card, i) => ({ card, report: report[i] }));
  };
  return (
    <div>
      <p class={headerClass}>Source</p>
      <TableView metadata={props.sourceMetadata} processed={false}></TableView>
      <p class={headerClass}>Selection</p>
      <TableView
        metadata={props.selectionMetadata}
        processed={true}
      ></TableView>
      <div class="mt-4">
        <A href={getURL("get-processed-data")} download="processed-data.csv">
          Download processed data
        </A>
        <DownloadJSON data={reportList()} name="report.json">
          Download report
        </DownloadJSON>
      </div>
    </div>
  );
}
