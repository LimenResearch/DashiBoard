import { createSignal } from "solid-js";
import { Title } from "@solidjs/meta";

import { Tabs } from "../components/Tabs";
import { Loader } from "../left-tabs/loading";
import { Filters } from "../left-tabs/filtering";
import { Cards } from "../left-tabs/processing";
import { Results } from "../left-tabs/results";
import { wireDocument } from "../wire";

const SECTIONS = ["Load", "Filter", "Process", "Run", "The document"] as const;

export default function Home() {
  const [section, setSection] = createSignal<(typeof SECTIONS)[number]>("Load");

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
