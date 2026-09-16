import { Show } from "solid-js";
import { Button } from "./Button";
import { hasPreviousSession, recoverSession, resetSession, sessionSummary } from "../session";

// The gate itself, split out of `App.tsx` (controller's resolution to a layout risk in the task
// brief): `App`'s `Router` is built from `virtual:file-routes` with browser history, which is
// fragile to render under jsdom, so this reads and renders on its own and is tested directly.

export function SessionGate() {
  const summaryText = () => {
    const s = sessionSummary();
    return [
      `${s.columns} column${s.columns === 1 ? "" : "s"} loaded`,
      `${s.groups} group${s.groups === 1 ? "" : "s"}`,
      `${s.cards} card${s.cards === 1 ? "" : "s"}`,
    ].join(" · ");
  };

  return (
    <Show when={hasPreviousSession()}>
      <div data-session-gate class="fixed inset-0 z-50 grid place-items-center bg-background/80">
        <div class="max-w-md rounded-sm border border-border bg-background p-4 shadow">
          <p class="mb-3 text-control-xs">
            A previous session is here: {summaryText()}. Recover it, or start fresh?
          </p>
          <div class="flex gap-2">
            <Button onClick={recoverSession}>Recover</Button>
            <Button variant="danger" onClick={() => resetSession()}>Start fresh</Button>
          </div>
        </div>
      </div>
    </Show>
  );
}
