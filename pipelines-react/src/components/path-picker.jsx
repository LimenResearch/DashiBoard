import {Button} from "./button";

export function FilePicker({children, dirHandle, setState}) {
    async function loadingHandler() {
        const options = {
            multiple: true,
        };
        const handles = await window.showOpenFilePicker(options);
        const paths = await Promise.all(handles.map(x => dirHandle.resolve(x)));
        setState(paths);
    }

    return <Button positive onClick={loadingHandler}>{children}</Button>;
}

export function FolderPermission({children, setState}) {
    async function dirHandler() {
        const dirHandle = await window.showDirectoryPicker();
        setState(dirHandle);
    }

    return <Button positive onClick={dirHandler}>{children}</Button>;
}

export function PathPicker({permissionMessage, fileMessage, state, setState}) {
    const dirHandle = state[1];
    const cp = Array.from(state);
    const setPaths = x => {cp[0] = x; setState(cp);};
    const setDirHandle = x => {cp[1] = x; setState(cp);};
    return <div>
        <FolderPermission setState={setDirHandle}>
            {permissionMessage}
        </FolderPermission>
        <FilePicker dirHandle={dirHandle} setState={setPaths}>
            {fileMessage}
        </FilePicker>
    </div>;
}