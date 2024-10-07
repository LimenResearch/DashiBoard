import { Button } from "./button";

export function FilePicker(props) {
    async function onClick() {
        const value = await window.showOpenFilePicker(props.options || {});
        props.onValue && props.onValue(value);
    }

    return <Button positive onClick={onClick}>{props.children}</Button>;
}

export function DirectoryPicker(props) {
    async function onClick() {
        const value = await window.showDirectoryPicker(props.options || {});
        props.onValue && props.onValue(value);
    }

    return <Button positive onClick={onClick}>{props.children}</Button>;
}
