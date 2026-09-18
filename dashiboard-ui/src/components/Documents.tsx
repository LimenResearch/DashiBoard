import { createEffect, createSignal, For, Show, untrack } from "solid-js";

import { Button } from "./Button";
import { Checkbox } from "./Checkbox";
import { DownloadJSONButton } from "./JSON";
import { FilePicker, type FileKind } from "./FilePicker";
import { Input } from "./Input";
import { postRequest } from "../requests";

// The document row of a tab: load one from the data directory, save this one into it, download
// it. One component for cards and for filters, because the three actions are the same and only
// the kind and the owner differ — it knows neither store.
//
// It replaces the browser's own file dialog. That dialog read a file on the author's machine,
// which the server never saw, and so showed the whole disk, while tables were confined to the
// server's data directory and picked from a list. One visibility now (owner, 2026-09-18): the
// server lists, reads and writes documents inside that directory, through the same picker.

type DocumentKind = Exclude<FileKind, "table">;

type DocumentsProps = {
  kind: DocumentKind;
  /** The document as it is saved and downloaded — already encoded, plain JSON. Read in an effect
   *  to notice edits, so it has to be a *tracked* read of the owner's store. */
  document: () => unknown;
  /** Put a loaded document in place. Resolves to the sentences nobody could place on an item
   *  (a loop; an unreachable server); empty when there is nothing to say. */
  onLoad: (document: unknown) => Promise<string[]> | string[];
};

type Reply = { valid?: boolean; document?: unknown; errors?: string[] } | null;
const UNREACHABLE = "Could not reach DashiBoard — is the server running?";
const sentences = (reply: Reply) =>
  reply === null
    ? [UNREACHABLE]
    : reply.errors?.length ? reply.errors : ["The server refused, without saying why."];

export function Documents(props: DocumentsProps) {
  const [picked, setPicked] = createSignal<string | null>(null);
  // The default name is a starting point, read once: a kind does not change under a mounted row.
  const [name, setName] = createSignal(`${untrack(() => props.kind)}.json`);
  const [overwrite, setOverwrite] = createSignal(false);
  const [busy, setBusy] = createSignal(false);
  let refresh: () => void = () => {};

  // What could not be said on an item — a load or save the server refused, or what the loader
  // could not place. It belongs to the document as it was when it was said, so an edit clears
  // it: the comparison is on the serialised document, the same string a save would write.
  const [report, setReport] = createSignal<string[] | null>(null);
  let reportedOn: string | null = null;
  const say = (lines: string[]) => {
    reportedOn = lines.length > 0 ? JSON.stringify(props.document()) : null;
    setReport(lines.length > 0 ? lines : null);
  };
  createEffect(
    () => JSON.stringify(props.document()),
    (json) => {
      if (reportedOn !== null && json !== reportedOn) {
        reportedOn = null;
        setReport(null);
      }
    },
  );

  async function load() {
    const path = picked();
    if (path === null) return;
    setBusy(true);
    try {
      const reply = (await postRequest("read-document", { path, kind: props.kind }, null)) as Reply;
      if (reply === null || reply.valid !== true) return say(sentences(reply));
      const loose = await props.onLoad(reply.document);
      // Said about the document as loaded, which is only in place once the owner's write has
      // settled — a tick later than `onLoad` returning. `untrack`: a one-off read from a
      // callback, which is deliberate and not something to subscribe to.
      queueMicrotask(() => untrack(() => say(loose)));
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    setBusy(true);
    try {
      const reply = (await postRequest(
        "write-document",
        { path: name(), kind: props.kind, document: props.document(), overwrite: overwrite() },
        null,
      )) as Reply;
      if (reply === null || reply.valid !== true) return say(sentences(reply));
      say([]);
      refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div data-documents={props.kind} class="flex flex-col gap-2 p-3">
      <FilePicker
        kind={props.kind}
        label={`A ${props.kind} file in the data directory`}
        onChange={(value) => setPicked(Array.isArray(value) ? (value[0] ?? null) : value || null)}
        refreshRef={(f) => { refresh = f; }}
      />
      <div class="flex flex-wrap items-center gap-2">
        <Button disabled={busy() || picked() === null} onClick={() => void load()}>
          Load {props.kind}
        </Button>
        <Input
          aria-label="file name"
          value={name()}
          onChange={(event) => setName(event.currentTarget.value.trim())}
        />
        <Checkbox label="replace an existing file" checked={overwrite()} onChange={setOverwrite} />
        <Button disabled={busy() || name() === ""} onClick={() => void save()}>
          Save {props.kind}
        </Button>
        <DownloadJSONButton data={props.document()} name={name() || `${props.kind}.json`}>
          Download {props.kind}
        </DownloadJSONButton>
      </div>
      {/* Same dress as a failed run's text under Run: the server's own sentence about the
          document. Gone on the next load or save, and on the next edit. */}
      <Show when={report()} keyed>
        {(lines: string[]) => (
          <div
            data-document-error
            class="rounded-sm border border-destructive/30 bg-destructive/10 p-3 text-control-xs text-destructive"
          >
            <For each={lines}>
              {(line: string) => <p class="font-mono break-words whitespace-pre-wrap">{line}</p>}
            </For>
          </div>
        )}
      </Show>
    </div>
  );
}
