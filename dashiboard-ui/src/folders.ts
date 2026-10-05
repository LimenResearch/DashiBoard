// The workspace folder each kind of file is listed from and saved to, as the server names it.
// Kept apart from the picker so that a test mocking the picker does not have to carry it.

import type { FileKind } from "./components/FilePicker";

const FOLDER_OF: Record<FileKind, string> = { table: "data", cards: "pipeline", filters: "filter" };

export const folderOf = (kind: FileKind) => FOLDER_OF[kind];
