import {
  createEffect, createMemo, createSignal, For, onCleanup, Show, Store, reconcile, untrack,
  snapshot,
} from "solid-js";

import { Button } from "../components/Button";
import { Documents } from "../components/Documents";
import { IRField } from "../components/IRField";
import { GroupsEditor } from "../components/GroupsEditor";
import { Presets } from "../components/Presets";
import { HelpButton } from "../components/SelectorHelp";
import { Disclosure } from "../components/Disclosure";
import { SummaryTitle, readableType } from "../components/SummaryTitle";
import { postRequest } from "../requests";
import { issueFindings } from "../findings";
import { throughOptions } from "../through";
import { presetFields, presetsFor } from "../presets";
import {
  CARDS_STORE,
  CARDS_JSON,
  CardsStore,
  Card,
  LOADER_STORE,
  addGroup,
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
  emptyProbe,
  askedOf,
  stillAsked,
  documentFindings,
  rejectFromIssues,
  rejectDocument,
  forgetVerdict,
  PROBE_STORE,
  PRESETS_STORE,
  droppedReferences,
  describedNodes,
  rememberDescribed,
  pruneReferences,
  setDroppedReferences,
  type ProbeNode,
  type ProbeStore,
  type ProbeIssue,
} from "../stores";
import { defaultsFor, onlyOptions, withoutOption, type Defs, type IRNode } from "../ir";
import { checkNames, checkNode, type Incompleteness } from "../completeness";
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
  const [presets] = PRESETS_STORE;

  const [payload, setPayload] = createSignal<Payload | null>(null);
  const [menuOpen, setMenuOpen] = createSignal(false);
  // Below the button when the page has room there, else above: the row can sit anywhere from the
  // top of a short page to the bottom of the view.
  const [menuAbove, setMenuAbove] = createSignal(false);
  let menuButton: HTMLButtonElement | undefined;
  let menu: HTMLUListElement | undefined;
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
  // Which card-IR request is the latest. Every vocabulary change asks again, and the answers
  // can land out of order: an older one arriving last used to put back a vocabulary the document
  // no longer has, so pickers offered a node name that did not exist any more (measured
  // 2026-09-21; it takes a slow server). Same guard as the continuous probe's `probeSeq`.
  // The server's title for a card type ("GLM", "Interpolation"); derived from the type name
  // until the IR has arrived, or for a type it does not know.
  const cardTitle = (type: string) => {
    const title = (payload()?.cards[type] as { title?: unknown } | undefined)?.title;
    return typeof title === "string" && title !== "" ? title : readableType(type);
  };

  let irSeq = 0;
  async function loadIR(vocabulary: Vocabulary) {
    const seq = ++irSeq;
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
    if (seq !== irSeq) return;                         // a newer question is out; this answer is stale
    if (!received || !received.defs) {
      setError("Could not reach DashiBoard. Is the server running?");
      return;
    }
    setError(null);
    const cards = received.cards ?? previousCards;
    if (cards === null) return;                       // cannot happen on the first call
    setCardIRs(cards);
    setPayload({ defs: received.defs, cards });
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
   * The vocabulary this card may draw on: what the server says it can refer to without a loop.
   *
   * A card naming itself or anything that depends on it — as an input, or as a step in a
   * `through` chain — is a cycle, and the server rejects the whole document for it. Offering it
   * is offering a choice that cannot come out well, so it is removed from the vocabulary rather
   * than validated after the fact. Until the server has answered for these cards, only the
   * card's own name is removed.
   */
  const defsForNode = (index: number): Defs => {
    const defs = payload()!.defs;
    // An answer about another number of cards is about an older document: its indices are not ours.
    const may = probe.referable?.nodes.length === state.nodes.length ? probe.referable.nodes[index] : undefined;
    if (may !== undefined) return onlyOptions(onlyOptions(defs, "node", may.nodes), "group", may.groups);
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
        rememberDescribed(answer, document.nodes.map((node) => node.id ?? ""));
      });
    }, PROBE_QUIET_MS);
  });

  // A pending probe must not outlive the tab: the timer would post after unmount, and a reply
  // already in flight would write the store. Moving the sequence past any live request discards it.
  onCleanup(() => {
    clearTimeout(probeTimer);
    probeSeq = Number.MAX_SAFE_INTEGER;
    irSeq = Number.MAX_SAFE_INTEGER;
  });

  /**
   * Loading a cards document is an act of asking.
   *
   * The document is put in place exactly as it came — a broken one included, because fixing it
   * here is what the form is for (owner, 2026-09-18) — and then asked about once, on the
   * author's behalf, from that same copy. What the server points at is rejected on its item,
   * the way a failed run's issues are; a taken name is ours to place (`checkNames`), since the
   * server reports it with no pointer; whatever is left has no item and goes on the document's
   * own verdict, said next to Run until the next edit. What is handed back to `Documents` is
   * only what is about the server (it could not be reached). Nothing is confirmed: an
   * item the probe has nothing against stays amber, because nobody looked at it.
   *
   * Its own `askProbe`, not the continuous probe's reply: that one writes the store and nothing
   * else, and by the time it answers the document may already be a later one.
   */
  /**
   * A new card of `type`, with the defaults its IR declares rather than only a type: the form
   * displayed them either way, and a document without them disagreed with the screen.
   */
  const add = (type: string) => {
    const ir = payload()?.cards[type];
    const defaults = ir === undefined ? undefined : defaultsFor(ir, payload()!.defs);
    // The author's starting values for the fields cards share, for the fields this type has.
    // Only at creation: a preset set later never rewrites a card already on screen.
    const preset = payload() === null
      ? {}
      : presetsFor(presetFields(payload()!.cards, payload()!.defs), ir, snapshot(presets));
    reach(`node-id-${addNode({ type, ...(defaults as object), ...preset } as Card)}`);
  };

  /** Take the hand to a new item's name box once it is drawn; the item stays folded. */
  const reach = (id: string) => requestAnimationFrame(() => document.getElementById(id)?.focus());

  async function loadCards(value: unknown): Promise<string[]> {
    // One plain copy is what is stored, what is asked about and what the verdicts bind to —
    // not `exportCards()` read back right after `importCards`, which on Solid 2 may still be
    // the previous document in this tick.
    const document = structuredClone(value) as CardsStore;
    // Pruned before it is stored and asked about, so the two never disagree.
    setDroppedReferences(pruneReferences(metadata.length > 0 ? metadata.map((column) => column.name) : null, document));
    importCards(document);
    const taken = checkNames(document.nodes);
    for (const { index, finding } of taken) {
      recordVerdict(`node:${index}`, document.nodes[index], "rejected", [finding]);
    }
    const answer = await askProbe(document);
    if (answer === null) {
      return ["Could not reach DashiBoard to check this document — is the server running?"];
    }
    rejectFromIssues(answer.issues, document);
    // With a taken name placed above, the server's one build error for this document is that
    // same duplicate id (construction stops there — measured), already on the later card; what
    // else there is surfaces once the names are fixed.
    if (taken.length > 0) return [];
    // What is left belongs to the pipeline, not to the file: it goes on the document's verdict
    // and is said next to Run. The row below keeps to what is about the file and the server.
    const loose = documentFindings(answer);
    if (loose.length > 0) rejectDocument(document, loose);
    return [];
  }

  /**
   * Ask Pipelines about this card, and only this card.
   *
   * Confirm has to ask: the UI's own rules only cover what DashiBoard *accepts* — by design —
   * so on their own they let an empty card through (`checkNode` sees a name and is satisfied,
   * while construction fails on `method` and `inputs`).
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
   * What only the whole document can answer *about this card*: a reference nothing produces, and
   * a schema failure `validate-card` could not see because it needs the other cards. Whether
   * the document builds at all is not this card's to carry — `confirmNode` asks that first.
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
    return [
      ...schema,
      ...(absent.length > 0
        ? [{ message: `Nothing produces ${absent.join(", ")} — check the pass-through chain.` }]
        : []),
    ];
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
    // An answer is only recorded while the card at this position is still the one that was
    // asked: cards are keyed by position, so a removal slides another card — possibly an
    // identical one, which the content check cannot tell apart — under the same key
    // (`stores.ts`, `askedOf`). Checked after every `await` below, through `verdict`.
    const asked = askedOf(key);
    const verdict = (findings: Incompleteness[]) => {
      if (!stillAsked(key, asked)) return;
      recordVerdict(key, node, findings.length > 0 ? "rejected" : "confirmed", findings);
    };

    // Ours alone: an unnamed node is a document the server accepts, so if this does not say it
    // nobody will. It is also the cheapest question, and answering it first keeps a card with no
    // name from spending two round trips to be told so.
    const named = checkNode(node);
    if (named.length > 0) return verdict(named);
    // Ours too: a name an earlier card already has. Only a loaded document can hold one
    // (`setNodeId` refuses it), the load marks this card for it, and the server's own word for
    // it points at no card — so without this, Confirm would wipe the one useful mark.
    const taken = checkNames(document.nodes).filter((entry) => entry.index === index);
    if (taken.length > 0) return verdict(taken.map((entry) => entry.finding));

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
    // A document that does not build — a loop, a chain nothing can resolve — is nobody's card:
    // written on whichever card was asked, one loop read as a fault of every card (seen in a
    // browser, 2026-09-18). It goes on the document, which says it once next to Run, and this
    // card is not vouched for: whether something produces its inputs is a question of the very
    // graph that does not build. So it is left unasked — amber — rather than green or red.
    const loose = documentFindings(answer);
    if (loose.length > 0) {
      if (!stillAsked(key, asked)) return;
      forgetVerdict(key);
      rejectDocument(document, loose);
      return;
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

      {/* A reference to a column the table lacks, or to a node or group the document lacks, was
          removed when the table or the document was loaded. Said once, here. */}
      <Show when={droppedReferences().length > 0}>
        <div
          data-dropped-references
          class="mb-3 flex items-start gap-2 rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground"
        >
          <span class="min-w-0 flex-1">
            References removed — not in the table or the document:{" "}
            <span class="font-mono">
              {droppedReferences().map((d) => `${d.what} from ${d.where}`).join(", ")}
            </span>
          </span>
          <button
            type="button"
            aria-label="dismiss"
            onClick={() => setDroppedReferences([])}
            class="grid h-4 w-4 shrink-0 place-items-center rounded-sm text-muted-foreground hover:bg-secondary hover:text-foreground"
          >
            ×
          </button>
        </div>
      </Show>

      {/* Groups first: a card's `groups:` selector can only offer names that already exist. */}
      <Show when={payload()}>
        <GroupsEditor defs={payload()!.defs} />
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
          // Why the last name typed into this card was refused — per card, since the `<For>`
          // callback is a per-row owner. `GroupsEditor`'s `rename` is the same move for groups.
          const [nameError, setNameError] = createSignal<string | null>(null);
          function rename(field: HTMLInputElement) {
            const to = field.value;
            if (setNodeId(index(), to)) {
              setNameError(null);
              return;
            }
            // The document refused, so the screen must not keep showing the name that was typed.
            field.value = node.id ?? "";
            setNameError(
              to === ""
                ? "There is already a card without a name."
                : `There is already a card called "${to}".`,
            );
          }

          return (
          <div class="my-2 rounded-sm border border-border p-2" data-last-item={index() === state.nodes.length - 1 ? "" : undefined}>
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
                  <SummaryTitle
                    hook="card"
                    kind={cardTitle(String(node.card.type))}
                    name={node.id ?? ""}
                    state={nodeState()}
                    // The node's name, not the card's: what another card's `nodes:` selector or
                    // `through:` chain refers to. A taken name is refused in `rename`.
                    edit={{ id: `node-id-${index()}`, label: "node id", onRename: rename }}
                  />
                </>
              }
            >
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
            {/* A refused name, with the other banners rather than under the field: seen in a
                browser with the field between two red banners, it read as two kinds of thing
                (owner, 2026-09-17). One stack, then the fields. */}
            <Show when={nameError()}>
              <p
                data-name-error
                class="mb-2 rounded-sm border border-destructive/30 bg-destructive/10 p-2 text-control-xs text-destructive"
              >
                {nameError()}
              </p>
            </Show>
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
                // A chain may only pass through nodes that read what it carries; the probe
                // says what each node reads.
                chainFor={(row, all) => throughOptions(row, all, describedNodes(), state.groups)}
                value={node.card}
                onChange={(card) => setCard(index(), card as Card)}
              />
            </Show>
            </Disclosure>
            {/* At the foot, after the last field, and outside what folds. */}
            <span data-card-actions class="mt-1 flex shrink-0 items-center justify-end gap-2">
              {/*
                The distinction it carries is *completeness*, not validity, and the two come
                apart in both directions: an empty group passes schema validation (measured —
                `weather = []` constructs) and is still not something anyone meant to define,
                while a blank `suffix` is filled in and the schema rejects it. So Confirm
                cannot just be the validator — see `confirmNode` for what it is instead.
              */}
              <Button
                title="mark this card deliberately finished"
                onClick={() => void confirmNode(index())}
              >
                Confirm
              </Button>
              <Button
                variant="danger"
                onClick={() => removeNode(index())}
              >
                Remove
              </Button>
            </span>
          </div>
          );
        }}
      </For>

      {/* After the last item and before the files, where a hand that has just finished one item
          is; pinned to the bottom of the view so it is there without scrolling. */}
      <Show when={payload()} fallback={<p class="text-muted-foreground">Loading card descriptions…</p>}>
        <div data-add class="sticky bottom-0 z-10 flex flex-wrap items-center gap-2 border-t border-border bg-background p-3">
          <Button onClick={() => reach(`group-name-${addGroup()}`)}>Add group</Button>
          {/* The card types, on demand: a menu above the button, since the row is at the foot. */}
          <div class="relative">
            <Button
              menu={{ open: menuOpen(), ref: (el) => { menuButton = el; } }}
              onClick={() => {
                const below = window.innerHeight - (menuButton?.getBoundingClientRect().bottom ?? 0);
                setMenuAbove(below < 320);
                setMenuOpen(!menuOpen());
              }}
            >
              Add card
            </Button>
            <Show when={menuOpen()}>
              <ul
                role="menu"
                tabindex={-1}
                aria-label="card type"
                ref={(el) => { menu = el; requestAnimationFrame(() => el.querySelector("button")?.focus()); }}
                onFocusOut={(event) => {
                  if (!menu?.contains(event.relatedTarget as Node | null)) setMenuOpen(false);
                }}
                onKeyDown={(event) => {
                  const items = [...(menu?.querySelectorAll("button") ?? [])];
                  const at = items.indexOf(document.activeElement as HTMLButtonElement);
                  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                    event.preventDefault();
                    const step = event.key === "ArrowDown" ? 1 : -1;
                    items[(at + step + items.length) % items.length]?.focus();
                  } else if (event.key === "Escape") {
                    event.preventDefault();
                    setMenuOpen(false);
                    menuButton?.focus();
                  }
                }}
                class={[
                  "absolute left-0 z-20 max-h-72 min-w-48 overflow-y-auto rounded-sm border border-border bg-card p-1 shadow-sm",
                  menuAbove() ? "bottom-full mb-1" : "top-full mt-1",
                ]}
              >
                <For each={cardTypes()}>
                  {(type) => (
                    <li role="none">
                      {/* The title the folded cards use; the document holds the type name. */}
                      <button
                        type="button"
                        role="menuitem"
                        data-card-type={type}
                        onClick={() => {
                          setMenuOpen(false);
                          add(type);
                        }}
                        class="w-full rounded-sm px-2 py-1 text-left text-control-xs hover:bg-muted focus:bg-muted focus:outline-none"
                      >
                        {cardTitle(type)}
                      </button>
                    </li>
                  )}
                </For>
              </ul>
            </Show>
          </div>
          <Presets cards={payload()!.cards} defs={payload()!.defs} />
          {/* Apart from the three that make something: what the keys are, for the whole tab. */}
          <div class="ml-auto">
            <HelpButton />
          </div>
        </div>
      </Show>

      {/* `CARDS_JSON`, not `exportCards`: `Documents` clears what it said when the document
          changes, and it learns that by reading `document()` in an effect. `exportCards` reads a
          `snapshot`, which tracks nothing; `CARDS_JSON` is the memo persistence already builds
          over the whole store, so parsing it back is a tracked read of the same document. */}
      <Documents
        kind="cards"
        noun="pipeline"
        document={() => JSON.parse(CARDS_JSON()) as CardsStore}
        onLoad={loadCards}
      />
    </div>
  );
}
