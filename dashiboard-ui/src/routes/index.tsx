import { useSearchParams } from "@solidjs/router";
import { Title } from "@solidjs/meta";

import { Tabs } from "../components/Tabs";
import { Loader } from "../left-tabs/loading";
import { Filters } from "../left-tabs/filtering";
import { Cards } from "../left-tabs/processing";
import { Results } from "../left-tabs/results";
import { wireDocument } from "../wire";

const SECTIONS = ["Load", "Filter", "Process", "Document"] as const;
type Section = (typeof SECTIONS)[number];

/** `?tab=` value ↔ section name. Lower-case, one word, so the URL reads well. */
const slug = (s: Section) => s.toLowerCase().replace(/^the /, "");
const fromSlug = (v: string | undefined): Section =>
  SECTIONS.find((s) => slug(s) === v) ?? "Load";

export default function Home() {
  const [params, setParams] = useSearchParams<{ tab?: string }>();
  // The URL is the state. Reading it makes a reload, a shared link and the back button all land
  // on the section they name; writing it with `replace` keeps typing through tabs out of history.
  const section = () => fromSlug(params.tab);
  const setSection = (s: Section) => setParams({ tab: slug(s) }, { replace: true });


  return (
    <main class="grid grid-cols-5 gap-6 px-4 py-2">
      <Title>DashiBoard</Title>

      {/*
        Two panes, as `frontend/` had them: what you are building on the left, what it produced on
        the right. The left is a set of tabs because its stages are steps in one order; the right is
        always visible because a result is the answer to the left, and hiding it behind a tab meant
        the thing you ran was behind the thing you were editing.

        Sections stay mounted and hidden rather than unmounted: Load sets up choices.js, Process
        fetches the card IR, and remounting on each switch would refetch both.
      */}
      <div class="col-span-2 min-w-0">
        <Tabs group="sections" items={SECTIONS} active={section()} onSelect={setSection} size="md" />
        <section class="mt-4" data-section="Load" hidden={section() !== "Load"}><Loader /></section>
        <section data-section="Filter" hidden={section() !== "Filter"}><Filters /></section>
        <section data-section="Process" hidden={section() !== "Process"}><Cards /></section>
        <section data-section="Document" hidden={section() !== "Document"}>
          <pre data-testid="document" class="overflow-x-auto rounded-sm bg-muted p-3 text-control-xs">
            {JSON.stringify(wireDocument(), null, 2)}
          </pre>
        </section>
      </div>

      <div class="col-span-3 min-w-0" data-pane="results">
        <Results />
      </div>
    </main>
  );
}
