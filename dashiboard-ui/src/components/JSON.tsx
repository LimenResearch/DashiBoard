import type { Element as JSXElement } from "solid-js";

import { downloadJSON } from "../requests";
import { Button } from "./Button";

// The anchor is deliberately hidden rather than absent: it has to exist in the document for a
// download to work at all. There is no upload counterpart any more: documents are read by the
// server from its data directory (`components/Documents.tsx`), not from a local file the browser
// picks off the whole disk.

type DownloadProps = {
  data: unknown;
  name?: string;
  children: JSXElement;
};

export function DownloadJSONButton(props: DownloadProps) {
  let anchor!: HTMLAnchorElement;
  return (
    <>
      <Button onClick={() => downloadJSON(props.data, anchor)}>
        {props.children}
      </Button>
      <a ref={anchor} download={props.name || true} class="hidden"></a>
    </>
  );
}
