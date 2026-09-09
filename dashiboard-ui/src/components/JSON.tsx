import { downloadJSON, loadJSON } from "../requests";
import { Button } from "./Button";

type UploadProps = {
  def: string;
  onChange: any;
  children: any;
};

export function UploadJSONButton(props: UploadProps) {
  let fileInput!: HTMLInputElement;
  const onChange = () => {
    loadJSON(fileInput, props.def).then((x: any) => props.onChange(x));
  };

  return (
    <>
      <Button onClick={() => fileInput.click()}>{props.children}</Button>
      <input onChange={onChange} type="file" ref={fileInput} class="hidden" />
    </>
  );
}

type DownloadProps = {
  data: any;
  name?: string;
  children: any;
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
