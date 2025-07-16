import { downloadJSON, loadJSON } from "../requests";
import { Button } from "./button";

export function UploadJSON(props) {
  let fileInput;
  const onChange = () => {
    loadJSON(fileInput, props.def).then((x) => props.onChange(x));
  };

  return (
    <>
      <Button onClick={() => fileInput.click()}>{props.children}</Button>
      <input onChange={onChange} type="file" ref={fileInput} class="hidden" />
    </>
  );
}

export function DownloadJSON(props) {
  let anchor;
  return (
    <>
      <Button onClick={() => downloadJSON(props.data, anchor)}>
        {props.children}
      </Button>
      <a ref={anchor} download={props.name || true} class="hidden"></a>
    </>
  );
}
