import type { Element as JSXElement } from "solid-js";

import { downloadJSON, loadJSON } from "../requests";
import { Button } from "./Button";

// The file input and the anchor are deliberately hidden rather than absent: both need to exist in
// the document for `.click()` and for a download to work at all.

type UploadProps<T> = {
  /** Returned when the file cannot be read or parsed, so a bad file is a no-op, not a crash. */
  def: T;
  onChange: (value: T) => void;
  children: JSXElement;
};

export function UploadJSONButton<T>(props: UploadProps<T>) {
  let fileInput!: HTMLInputElement;
  const onChange = () => {
    void loadJSON(fileInput, props.def).then((value: T) => props.onChange(value));
  };

  return (
    <>
      <Button onClick={() => fileInput.click()}>{props.children}</Button>
      <input onChange={onChange} type="file" ref={fileInput} class="hidden" />
    </>
  );
}

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
