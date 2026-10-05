import { createSignal } from "solid-js";

// Where each kind of file is listed from and saved to. The layout names a folder per kind, but
// a workspace may keep a kind elsewhere or everything at its root, so the server says where —
// with every listing — and the form repeats it rather than assume.

import type { FileKind } from "./components/FilePicker";

type Folders = Partial<Record<FileKind, string>>;

/** The layout's own folders, which is what a kind is in until the server has said. */
const CONVENTIONAL: Record<FileKind, string> = { table: "data", cards: "pipeline", filters: "filter" };

const [folders, setKnown] = createSignal<Folders | null>(null);

/** What the server said, from a listing; `null` forgets it. */
export const setFolders = (said: Folders | null) => setKnown(said);

/** The folder as the server names it: relative to the workspace, a whole path, or `""` for the workspace itself. */
export const folderOf = (kind: FileKind) => folders()?.[kind] ?? CONVENTIONAL[kind];

/** The folder as the form says it: `data/`, `/mnt/tables/`, or "the workspace". */
export const folderLabel = (kind: FileKind) => {
  const folder = folderOf(kind);
  return folder === "" ? "the workspace" : `${folder}/`;
};
