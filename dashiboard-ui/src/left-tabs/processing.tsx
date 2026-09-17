import {
  createEffect, createMemo, createSignal, For, onCleanup, Show, Store, reconcile, untrack,
} from "solid-js";

import { Button } from "../components/Button";
import { DownloadJSONButton, UploadJSONButton } from "../components/JSON";
import { IRField } from "../components/IRField";
import { GroupsEditor } from "../components/GroupsEditor";
import { Disclosure, summaryAction } from "../components/Disclosure";
import { postRequest } from "../requests";
import { issueFindings } from "../findings";
import {
  CARDS_STORE,
  CARDS_JSON,
  CardsStore,
  Card,
  LOADER_STORE,
  addNode,
  removeNode,
  setCard,
  setNodeId,
  verdictOf,
  recordVerdict,
  issuesForNode,
  fieldPath,
  exportCards,
  importCards,
  emptyCards,
  emptyProbe,
  PROBE_STORE,
  type ProbeNode,
  type ProbeStore,
  type ProbeIssue,
} from "../stores";
import { defaultsFor, withoutOption, type Defs, type IRNode } from "../ir";
import { checkNode, type Incompleteness } from "../completeness";
import { askProbe } from "../probe";

/** The card half of the document, as `evaluate-pipeline` takes it. */
export function getCards(state: Store<CardsStore>) {
  return { nodes: state.nodes, groups: state.groups };
}

type Payload = { defs: Defs; cards: { [type: string]: IRNode } };

/** Everything a card may name: the source's columns, the other cards, the groups. */
type Vocabulary = { cols: string[]; nodes: string[]; groups: string[] };

/**
 * One IR fetch per vocabulary *change*, which reference equality cannot deliver.
 *
 * The three lists are rebuilt from the stores on every write, so a fresh object arrives whenever
 * anything in the document moves — a field edited, a chip picked. Comparing their contents is
 * what keeps the refetch tied to the vocabulary rather than to the keystroke.
 */
const sameVocabulary = (a: Vocabulary, b: Vocabulary) =>
  (["cols", "nodes", "groups"] as const).every(
    (part) => a[part].length === b[part].length && a[part].every((v, at) => v === b[part][at]),
  );

export function Cards() {
  const [state] = CARDS_STORE;
  const [metadata] = LOADER_STORE;
  const [probe, setProbe] = PROBE_STORE;

  const [payload, setPayload] = createSignal<Payload | null>(null);
  const [chosen, setChosen] = createSignal("");
  const [error, setError] = createSignal<string | null>(null);

  // `cards` is fetched once and kept; only `defs` follows the vocabulary. See the handler.
  const [cardIRs, setCardIRs] = createSignal<{ [type: string]: IRNode } | null>(null);

  // The IR is what the renderer builds from, and since A2 it is the only description of a card
  // that exists (§13). Which nodes and groups are referenceable depends on the document being
  // edited, not only on the source, so this re-runs when either changes.
  //
  // The vocabulary arrives as an argument rather than being read here: this runs from an effect
  // *callback*, where a read of a store or a signal is untracked — so reading the document here
  // would be a dependency the effect does not have, and the diagnostics say so.
  async function loadIR(vocabulary: Vocabulary) {
    // Captured before the request, not re-read from the signal after `setCardIRs` below: a
    // signal write stages into `_pendingValue` and an untracked read from this plain async
    // continuation is not guaranteed to observe it before the next flush (Solid 2's transition
    // model, unlike Solid 1's immediate same-tick reads). `untrack` says that is deliberate:
    // this is a cache lookup, not something the fetch should re-run for.
    const previousCards = untrack(cardIRs);
    const include = previousCards === null ? ["defs", "cards"] : ["defs"];
    const received = (await postRequest(
      "get-card-ir",
      { ...vocabulary, include },
      null,
    )) as Partial<Payload> | null;
    if (!received || !received.defs) {
      setError("Could not reach DashiBoard. Is the server running?");
      return;
    }
    setError(null);
    const cards = received.cards ?? previousCards;
    if (cards === null) return;                       // cannot happen on the first call
    setCardIRs(cards);
    setPayload({ defs: received.defs, cards });
    const types = Object.keys(cards).sort();
    if (!chosen() && types.length > 0) setChosen(types[0]);
  }

  // Refetch whenever the *vocabulary* changes — columns, node ids, group names — not only on
  // mount. `$defs/col` carries the source enum, so a picker rendered before a source is connected
  // has nothing to offer; and adding or renaming a card changes what `nodes:` and `through:` can
  // name. Driving this from the document rather than from explicit calls after each mutation also
  // sidesteps reading the store before Solid has settled the write.
  //
  // The memo is where the stores are read, so those reads are the effect's dependencies, and the
  // value it produces is what the request is built from — it cannot drift from what triggered it.
  const vocabulary = createMemo<Vocabulary>(
    () => ({
      cols: metadata.map((entry) => entry.name),
      // Only names that exist. `Pipelines.get_id` is the naming rule, and it has no index
      // fallback — a node with no `id` is called "" and is referenceable by nobody, so
      // offering its position as a name offered one the server would never resolve.
      nodes: state.nodes.map((node) => node.id).filter((id): id is string => !!id),
      groups: Object.keys(state.groups),
    }),
    { equals: sameVocabulary },
  );
  createEffect(vocabulary, (current) => void loadIR(current));

  const cardTypes = () => Object.keys(payload()?.cards ?? {}).sort();

  /**
   * The vocabulary this card may draw on: everything, minus its own name.
   *
   * A card naming itself — as an input, or as a step in a `through` chain — is a cycle, and the
   * server rejects the whole document for it. Offering it is offering a choice that cannot come
   * out well, so it is removed from the vocabulary rather than validated after the fact.
   */
  const defsForNode = (index: number): Defs => {
    const defs = payload()!.defs;
    const self = state.nodes[index]?.id;
    return self ? withoutOption(defs, "node", self) : defs;
  };

  // The continuous probe. Three things it does that a plain effect did not:
  //
  //   * reads the document from `CARDS_JSON`, which persistence already serialises — one deep
  //     read of the store instead of two;
  //   * waits 200 ms of quiet before asking, so a burst of edits is one request;
  //   * numbers each request and applies a reply only if it is still the newest, because
  //     replies are async and a slow answer to an old document used to overwrite a fast answer
  //     to the new one.
  let probeSeq = 0;
  let probeTimer: ReturnType<typeof setTimeout> | undefined;
  const PROBE_QUIET_MS = 200;

  createEffect(CARDS_JSON, (json) => {
    clearTimeout(probeTimer);
    probeTimer = setTimeout(() => {
      const document = JSON.parse(json) as CardsStore;
      // Nothing at all to resolve — no cards *and* no groups — is the one case answerable here.
      // "No cards" alone is not: groups first is the usual authoring order, and an empty group is
      // the server's finding to make, so short-circuiting on cards left a groups-only document
      // with no live finding until the first card existed.
      if (document.nodes.length === 0 && Object.keys(document.groups).length === 0) {
        probeSeq += 1;
        setProbe(reconcile(emptyProbe()));
        return;
      }
      const seq = ++probeSeq;
      void askProbe(document).then((answer) => {
        if (seq !== probeSeq) return;            // a newer request is out; this answer is stale
        if (answer === null) {
          // Could not be asked at all (item 1's missing proxy route, or the server being down) —
          // leave PROBE_STORE as it was. A stale answer is better than overwriting it with a false
          // clean one, which is what `usableProbe(null)` used to do here.
          console.warn("probe: could not reach DashiBoard");
          return;
        }
        setProbe(reconcile(answer));
      });
    }, PROBE_QUIET_MS);
  });

  // A pending probe must not outlive the tab: the timer would post after unmount, and a reply
  // already in flight would write the store. Moving the sequence past any live request discards it.
  onCleanup(() => {
    clearTimeout(probeTimer);
    probeSeq = Number.MAX_SAFE_INTEGER;
  });

  /**
   * What the server says about this card, as something a person can act on.
   *
   * Confirm has to ask it. The UI's own rules only cover what DashiBoard *accepts* — by design —
   * so on their own they let an empty card through: `checkNode` sees a name and is satisfied,
   * while construction fails on `method` and `inputs`. The probe already knows; Confirm was
   * simply not reading it.
   */
  /**
   * Ask Pipelines about this card, and only this card.
   *
   * `POST /validate-card` builds the card's own schema from the same vocabularies the IR was
   * built from and validates against it — the server's own check, not a copy of it. There was a
   * walk here that re-implemented `required` and `minItems` in TypeScript; measured against
   * `validate_pipeline_schema` it found exactly the same set, so it is gone.
   */
  async function askCard(document: CardsStore, index: number): Promise<ProbeIssue[]> {
    const answer = (await postRequest(
      "validate-card",
      {
        card: document.nodes[index].card,
        cols: metadata.map((entry) => entry.name),
        nodes: document.nodes.map((node) => node.id).filter((id): id is string => !!id),
        groups: Object.keys(document.groups),
        base: `/nodes/${index}/card`,
      },
      null,
    )) as { issues?: ProbeIssue[]; errors?: string[] } | null;
    if (answer === null) return [];
    return Array.isArray(answer.issues) ? answer.issues : [];
  }

  /**
   * What only the whole document can answer: a reference nothing produces, and — as a backstop —
   * any schema failure `validate-card` could not see because it needs the other cards.
   */
  const graphFindings = (answer: ProbeStore, index: number): Incompleteness[] => {
    // A warning never counts as unfinished — it still renders live through the probe path, in
    // the warning style, but does not stop Confirm from marking the card done.
    const schema = issueFindings(
      issuesForNode(answer.issues, index).filter(
        (issue) => issue.reason !== "unproduced" && issue.severity !== "warning",
      ),
    );
    const absent = answer.nodes[index]?.unproduced ?? [];
    return absent.length > 0
      ? [...schema, { message: `Nothing produces ${absent.join(", ")} — check the pass-through chain.` }]
      : schema;
  };

  /**
   * Confirm: ask, and record the answer as a verdict on exactly this content.
   *
   * One plain snapshot of the document is taken before any `await`, and every question — ours,
   * `validate-card`, the probe — and the verdict itself use that snapshot. Not the store: a
   * store proxy captured here would read the *current* card by the time a reply lands, so an
   * edit made while a request is in flight would be stamped green on content the server never
   * saw (measured against solid-js rc.6 in review, 2026-09-17). With the snapshot, the verdict
   * binds to what was checked and the edited card simply reads as unasked. Findings travel with
   * the verdict (`stores.ts`, verdicts), which also follows its card across a removal.
   */
  async function confirmNode(index: number) {
    const document = exportCards();
    const node = document.nodes[index];
    const key = `node:${index}`;
    const verdict = (findings: Incompleteness[]) =>
      recordVerdict(key, node, findings.length > 0 ? "rejected" : "confirmed", findings);

    // Ours alone: an unnamed node is a document the server accepts, so if this does not say it
    // nobody will. It is also the cheapest question, and answering it first keeps a card with no
    // name from spending two round trips to be told so.
    const named = checkNode(node);
    if (named.length > 0) return verdict(named);

    // A warning is not a finding (it renders live, amber, and never stops Confirm). The server's
    // card issues are all errors today; filtered anyway, so this path and `graphFindings` agree.
    const issues = (await askCard(document, index)).filter((issue) => issue.severity !== "warning");
    if (issues.length > 0) return verdict(issueFindings(issues));

    const answer = await askProbe(document);
    // `null` means the probe could not be asked at all (item 1: a missing dev-server proxy route,
    // or the server being down) — not that it came back clean. Reading it as "no issues" is what
    // let an empty group through Confirm with a green dot (final review, 2026-09-16); the same
    // failure reaches a card's Confirm through this same `askProbe` call.
    if (answer === null) {
      return verdict([{
        message: "Could not reach DashiBoard to check this card — is the server running?",
      }]);
    }
    return verdict(graphFindings(answer, index));
  }

  // Memos are a tracking scope; reading `probe.nodes` straight from JSX is not enough here.
  const probeNodes = createMemo(() => probe.nodes);
  const probeIssues = createMemo(() => probe.issues);
  // What the continuous probe says live about a card is only its *warnings* (a column about to be
  // overwritten). Its errors are not shown here: red is reserved for what Confirm or a Run found,
  // and until then the card is amber (decided 2026-09-17). The document-level banner that used
  // to sit above the cards went with it — the pointer next to Run pipeline names the items now.
  const warningsForNode = (index: number) =>
    issuesForNode(probeIssues(), index).filter((issue) => issue.severity === "warning");

  return (
    <div>
      <Show when={error()}>
        <p class="mb-4 rounded-sm border border-destructive/30 bg-destructive/10 p-3 text-destructive">{error()}</p>
      </Show>

      {/*
        Groups first, as their own section: a card's `groups:` selector can only offer names that
        already exist, so authoring in the other order means scrolling past the cards to define a
        group and back up to use it. "Add card" then sits directly above the cards it creates,
        rather than above the groups — a control belongs next to what it produces.
      */}
      <Show when={payload()}>
        <GroupsEditor defs={payload()!.defs} />
      </Show>

      <Show when={payload()} fallback={<p class="text-muted-foreground">Loading card descriptions…</p>}>
        <div class="flex items-center gap-2 p-3">
          <label for="card-type" class="text-control-xs font-semibold text-primary">
            Card type
          </label>
          <select
            id="card-type"
            class="h-control-xs rounded-sm border border-border pl-2 text-control-xs"
            value={chosen()}
            onChange={(event) => setChosen(event.currentTarget.value)}
          >
            <For each={cardTypes()}>{(type) => <option value={type}>{type}</option>}</For>
          </select>
          {/*
            The card starts with the defaults its IR declares, rather than with only a type. The
            form displayed them either way; the document did not carry them, so what was on screen
            and what a download produced disagreed.
          */}
          <Button
            onClick={() => {
              const ir = payload()?.cards[chosen()];
              const defaults = ir === undefined ? undefined : defaultsFor(ir, payload()!.defs);
              addNode({ type: chosen(), ...(defaults as object) } as Card);
            }}
          >
            Add card
          </Button>
        </div>
      </Show>

      <For each={state.nodes}>
        {(node, index) => {
          // The last verdict on exactly this content — null once the card is edited.
          const verdict = createMemo(() => verdictOf(`node:${index()}`, node));
          /** unconfirmed · confirmed · rejected — amber until asked; folded, the dot is all there is. */
          const nodeState = createMemo(() => verdict()?.verdict ?? "unconfirmed");
          const findings = createMemo(() => {
            const v = verdict();
            return v?.verdict === "rejected" ? v.findings : [];
          });

          return (
          <div class="my-2 rounded-sm border border-border p-2">
            <Disclosure
              bodyClass="mt-2 flex flex-col gap-1 border-t border-border pt-2"
              summary={
                <>
                  {/* Folded, this line is all that survives — so it says what the card is and
                      which name the rest of the document refers to it by. A long type name (e.g.
                      `dimensionality_reduction`) used to push Confirm/Remove past the pane's edge.
                      `text-overflow: ellipsis` only renders in a block/inline formatting context —
                      on a flex box `overflow:hidden` just hard-clips a child mid-character — so
                      `truncate` lives on the inner, non-flex `data-card-text` span around the text
                      run, not on this flex wrapper. The full text still reaches the reader through
                      `title`. */}
                  <span
                    data-card-title
                    title={`${String(node.card.type)} : ${node.id || "unnamed"}`}
                    class="flex min-w-0 items-center gap-1.5"
                  >
                    <span data-card-text class="min-w-0 truncate">
                      <span class="font-mono text-control-xs font-semibold text-primary">
                        {String(node.card.type)}
                      </span>
                      <span class="text-muted-foreground">:</span>
                      <span class="font-mono text-control-xs">
                        {node.id || <span class="text-destructive italic">unnamed</span>}
                      </span>
                    </span>
                    {/*
                      Amber until asked, then green or red on what the server answered. Folded,
                      this dot is the only thing on screen, so the answer has to live here as
                      well as in the findings below. A live warning never changes it.
                    */}
                    <span
                      data-state={nodeState()}
                      aria-label={nodeState()}
                      title={
                        nodeState() === "rejected"
                          ? "the server found something wrong — open to see what"
                          : nodeState() === "confirmed"
                            ? "confirmed"
                            : "not confirmed yet"
                      }
                      class={[
                        "ml-1 h-2 w-2 shrink-0 rounded-full",
                        {
                          "bg-success": nodeState() === "confirmed",
                          "bg-destructive": nodeState() === "rejected",
                          "bg-warning": nodeState() === "unconfirmed",
                        },
                      ]}
                    />
                  </span>
                  <span data-card-actions class="ml-auto flex shrink-0 items-center gap-2">
                    {/*
                      The distinction it carries is *completeness*, not validity, and the two come
                      apart in both directions: an empty group passes schema validation (measured —
                      `weather = []` constructs) and is still not something anyone meant to define,
                      while a blank `suffix` is filled in and the schema rejects it. So Confirm
                      cannot just be the validator — see `confirmNode` for what it is instead.
                    */}
                    <Button
                      title="mark this card deliberately finished"
                      onClick={summaryAction(() => {
                        void confirmNode(index());
                      })}
                    >
                      Confirm
                    </Button>
                    <Button
                      variant="danger"
                      onClick={summaryAction(() => removeNode(index()))}
                    >
                      Remove
                    </Button>
                  </span>
                </>
              }
            >
              <div class="flex items-center gap-2">
                <label
                  for={`node-id-${index()}`}
                  class="w-32 shrink-0 text-control-xs font-semibold text-primary"
                >
                  name
                </label>
                {/*
                  The node's name, not the card's. It is what another card's `nodes:` selector or
                  `through:` chain refers to, and `Pipelines.get_id` defaults a missing one to "",
                  so two unnamed cards collide and the whole document is rejected.
                */}
                <input
                  id={`node-id-${index()}`}
                  class="h-control-xs rounded-sm border border-border px-2 font-mono text-control-xs"
                  aria-label="node id"
                  value={node.id ?? ""}
                  onChange={(event) => setNodeId(index(), event.currentTarget.value)}
                />
              </div>
            {/*
              A7: the probe addresses each failure by JSON Pointer, so it is shown on the card it
              belongs to, naming the field and — for an enum — what would have been accepted.
              Attaching to the whole page was the behaviour this replaces.
            */}
            {/*
              What Confirm (or a Run) found on this exact content: red, one per control, and
              only while the verdict is a rejection — an edit drops them with the verdict.
              A UI finding (no name) and a server finding render through this one path.
            */}
            <For each={findings()}>
              {(finding: Incompleteness) => (
                <p
                  data-finding
                  class="mb-2 rounded-sm border border-destructive/30 bg-destructive/10 p-2 text-control-xs text-destructive"
                >
                  <Show when={finding.pointer && fieldPath(finding.pointer) !== ""}>
                    <span class="font-mono">{fieldPath(finding.pointer!)}</span>{" — "}
                  </Show>
                  {finding.message}
                </p>
              )}
            </For>
            {/* Live, amber, and not a verdict: the document is legal and would run. */}
            <For each={warningsForNode(index())}>
              {(issue: ProbeIssue) => (
                <p
                  data-issue-severity="warning"
                  class="mb-2 rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground"
                >
                  <Show when={fieldPath(issue.pointer) !== ""}>
                    <span class="font-mono">{fieldPath(issue.pointer)}</span>{" — "}
                  </Show>
                  {issue.message}
                </p>
              )}
            </For>
            <Show when={probeNodes()[index()]} keyed>
              {(reported: ProbeNode) => (
                <div class="mb-2 text-control-xs">
                  <p class="text-muted-foreground">
                    resolves to: {reported.inputs.join(", ") || "—"}
                    <Show when={reported.outputs.length > 0}>
                      {" "}→ {reported.outputs.join(", ")}
                    </Show>
                  </p>
                </div>
              )}
            </Show>
            <Show
              when={payload()?.cards[String(node.card.type)]}
              fallback={<p class="text-muted-foreground">No description for this card type.</p>}
            >
              <IRField
                node={payload()!.cards[String(node.card.type)]}
                defs={defsForNode(index())}
                label={String(node.card.type)}
                idPrefix={`node-${index()}`}
                value={node.card}
                onChange={(card) => setCard(index(), card as Card)}
              />
            </Show>
            </Disclosure>
          </div>
          );
        }}
      </For>

      <div class="flex gap-2">
        <DownloadJSONButton data={exportCards()} name="cards.json">
          Download cards
        </DownloadJSONButton>
        <UploadJSONButton
          def={emptyCards()}
          onChange={(value: CardsStore) => importCards(value)}
        >
          Upload cards
        </UploadJSONButton>
      </div>
    </div>
  );
}
