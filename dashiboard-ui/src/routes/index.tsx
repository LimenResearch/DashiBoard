import { useSearchParams } from "@solidjs/router";
import { Title } from "@solidjs/meta";

import { Tabs } from "../components/Tabs";
import { Loader } from "../left-tabs/loading";
import { Filters } from "../left-tabs/filtering";
import { Cards } from "../left-tabs/processing";
import { Results } from "../left-tabs/results";
import { wireDocument } from "../wire";

const SECTIONS = ["Load", "Filter", "Process", "Run", "The document"] as const;
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
    <main class="mx-auto max-w-5xl px-4 py-2">
      <Title>DashiBoard</Title>

      {/*
        The five stages are tabs, not a single scroll. They are steps in one order — load, filter,
        process, run — and only one is being worked on at a time; stacked, the one in hand is
        wherever you last scrolled to.

        Every section stays mounted and is hidden rather than unmounted: Load sets up choices.js,
        Process fetches the card IR and Run holds a grid that pages the output, so remounting on
        each switch would refetch all three and drop each picker's open tab. The stores survive
        either way — the local state is what would not.
      */}
      <Tabs
        group="sections"
        items={SECTIONS}
        active={section()}
        onSelect={setSection}
        size="md"
      />

      <section class="mt-4" data-section="Load" hidden={section() !== "Load"}>
        <Loader />
      </section>

      <section data-section="Filter" hidden={section() !== "Filter"}>
        <Filters />
      </section>

      <section data-section="Process" hidden={section() !== "Process"}>
        <Cards />
      </section>

      <section data-section="Run" hidden={section() !== "Run"}>
        <Results />
      </section>

      {/* The same assembly the Run button posts, by construction — see `wireDocument`. */}
      <section data-section="The document" hidden={section() !== "The document"}>
        <pre
          data-testid="document"
          class="overflow-x-auto rounded-sm bg-muted p-3 text-control-xs"
        >{JSON.stringify(wireDocument(), null, 2)}</pre>
      </section>
    </main>
  );
}
