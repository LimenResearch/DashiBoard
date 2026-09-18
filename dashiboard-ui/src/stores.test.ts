import { describe, it, expect, beforeEach } from 'vitest';
import { flush, reconcile } from 'solid-js';
import {
  emptyCards, importCards, exportCards, setCard, setCardField, addNode, removeNode, setNodeId,
  issuesForNode, fieldPath, type ProbeIssue,
  addGroup, removeGroup, renameGroup, setGroup,
  isConfirmed, confirmDefinition, forgetConfirmation,
  CARDS_STORE, type CardsStore,
  Interval,
} from './stores';
import { getCards } from './left-tabs/processing';

beforeEach(() => sessionStorage.clear());

// The authored card half of a Config, in the post-9bd6c28 group vocabulary: plural selectors are
// arrays, singular ones are objects, and a selector value may be a string or a list.
const STORED: CardsStore = {
  nodes: [
    {
      id: 'rescale',
      card: {
        type: 'rescale',
        method: { type: 'zscore' },
        group_by: [{ cols: 'cbwd' }],
        partition: { nodes: 'partition' },
        inputs: [{ groups: 'weather' }, { cols: 'No' }],
      },
    },
  ],
  groups: { weather: [{ cols: ['PRES', 'TEMP'] }] },
};

describe('the document is the model', () => {
  beforeEach(() => importCards(emptyCards()));

  it('starts empty', () => {
    expect(exportCards()).toEqual({ nodes: [], groups: {} });
  });

  it('round-trips a stored document verbatim', () => {
    importCards(structuredClone(STORED));
    expect(exportCards()).toEqual(STORED);
  });

  it('preserves top-level keys it does not understand', () => {
    // section 2: what gets saved is the stored JSON, never a reconstruction. A future `version`
    // key must survive a UI that has never heard of it.
    const withExtra = { ...structuredClone(STORED), version: 'dashi/1' };
    importCards(withExtra);
    expect(exportCards()).toEqual(withExtra);
  });

  it('edits a card field in place and leaves the rest untouched', () => {
    importCards(structuredClone(STORED));
    setCardField(0, 'suffix', 'zscored');
    const after = exportCards();
    expect(after.nodes[0].card.suffix).toBe('zscored');
    expect(after.nodes[0].card.method).toEqual({ type: 'zscore' });
    expect(after.groups).toEqual(STORED.groups);
  });

  it('replaces a whole card, which is what an IRField edit produces', () => {
    importCards(structuredClone(STORED));
    setCard(0, { type: 'rescale', method: { type: 'log' }, suffix: 'logged' });
    expect(exportCards().nodes[0].card).toEqual({
      type: 'rescale', method: { type: 'log' }, suffix: 'logged',
    });
    expect(exportCards().nodes[0].id).toBe('rescale'); // the node wrapper survives
  });

  it('does not coerce singular and plural selectors into one shape', () => {
    importCards(structuredClone(STORED));
    const card = exportCards().nodes[0].card;
    expect(Array.isArray(card.group_by)).toBe(true); // plural -> array
    expect(Array.isArray(card.partition)).toBe(false); // singular -> object
  });

  it('adds and removes nodes', () => {
    addNode({ type: 'split' });
    expect(exportCards().nodes[0].card.type).toBe('split');
    addNode({ type: 'rescale' }, 'named');
    expect(exportCards().nodes[1].id).toBe('named');
    removeNode(0);
    expect(exportCards().nodes).toHaveLength(1);
    expect(exportCards().nodes[0].card.type).toBe('rescale');
  });

  it('names every node, since an unnamed one is unreferenceable and two collide', () => {
    // `Pipelines.get_id` defaults a missing `id` to "", so two unnamed nodes are duplicates and
    // `dependency_graph` rejects the document outright. A name is not decoration here.
    addNode({ type: 'split' });
    addNode({ type: 'split' });
    addNode({ type: 'rescale' });
    const ids = exportCards().nodes.map((node) => node.id);
    expect(ids).toEqual(['split', 'split_2', 'rescale']);
  });

  it('does not reuse a name a surviving node still holds', () => {
    addNode({ type: 'split' });   // split
    addNode({ type: 'split' });   // split_2
    removeNode(0);                // split_2 survives
    addNode({ type: 'split' });
    const ids = exportCards().nodes.map((node) => node.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('renames a node', () => {
    addNode({ type: 'split' });
    setNodeId(0, 'partition');
    expect(exportCards().nodes[0].id).toBe('partition');
    expect(exportCards().nodes[0].card.type).toBe('split'); // the card is untouched
  });

  it('exports a snapshot, not the reactive proxy', () => {
    importCards(structuredClone(STORED));
    const before = exportCards();
    setCardField(0, 'suffix', 'changed');
    expect(before.nodes[0].card.suffix).toBeUndefined();
  });
});

describe('getCards', () => {
  beforeEach(() => importCards(emptyCards()));

  it('returns the card half of the wire document, and nothing else', () => {
    importCards(structuredClone(STORED));
    const [state] = CARDS_STORE;
    const cards = getCards(state);
    // exactly the two keys evaluate-pipeline reads from this half
    expect(Object.keys(cards).sort()).toEqual(['groups', 'nodes']);
    expect(cards.nodes).toEqual(STORED.nodes);
    expect(cards.groups).toEqual(STORED.groups);
  });
});

describe('probe issues (A7)', () => {
  it('attaches an issue to the card its pointer addresses', () => {
    const issues: ProbeIssue[] = [
      { pointer: '/nodes/0/card/method/type', reason: 'enum', found: 'nonesuch',
        allowed: ['zscore'], missing: [], related: [], message: 'x' },
      { pointer: '/nodes/12/card', reason: 'unproduced', found: null, allowed: null,
        missing: ['TEMP_a'], related: [], message: 'y' },
    ];
    expect(issuesForNode(issues, 0)).toHaveLength(1);
    expect(issuesForNode(issues, 12)).toHaveLength(1);
    // `/nodes/1/...` must not match node 12 — a prefix test on the raw string would
    expect(issuesForNode(issues, 1)).toHaveLength(0);
  });

  it('reads the field path relative to the card, one-based for a reader', () => {
    // The pointer counts array positions from zero, as JSON Pointer must. A person reading
    // "the 3rd input" should not be shown "2".
    expect(fieldPath('/nodes/0/card/inputs/2/cols')).toBe('inputs → 3 → cols');
    expect(fieldPath('/nodes/0/card/method/dissimilarity/p')).toBe('method → dissimilarity → p');
    expect(fieldPath('/nodes/0/card')).toBe(''); // the card itself, not a field within it
  });

  it('unescapes a pointer token, since a group name may contain a slash', () => {
    expect(fieldPath('/nodes/0/card/a~1b/c')).toBe('a/b → c');
  });
});

describe('groups', () => {
  beforeEach(() => importCards(emptyCards()));

  it('creates an empty group, which the server accepts until it is filled', () => {
    // Measured: `weather = []` constructs fine. So a group can be named before it holds
    // anything, and naming it first is the only order that works — a group is referred to by
    // name, so the name is the part that has to exist.
    const name = addGroup();
    expect(name).toBe('group');
    expect(exportCards().groups).toEqual({ group: [] });
    expect(addGroup()).toBe('group_2');
  });

  it('replaces a group\'s selectors', () => {
    const name = addGroup();
    setGroup(name, [{ cols: ['PRES', 'TEMP'] }]);
    expect(exportCards().groups[name]).toEqual([{ cols: ['PRES', 'TEMP'] }]);
  });

  it('renames a group in place, keeping its position among the others', () => {
    // Position matters only because a reader scans the list; delete-then-add would send the
    // renamed group to the end, which reads as it having been recreated.
    addGroup('a');
    addGroup('b');
    addGroup('c');
    setGroup('b', [{ cols: 'TEMP' }]);
    expect(renameGroup('b', 'weather')).toBe(true);
    expect(Object.keys(exportCards().groups)).toEqual(['a', 'weather', 'c']);
    expect(exportCards().groups.weather).toEqual([{ cols: 'TEMP' }]);
  });

  it('refuses a rename that would collide, rather than silently merging two groups', () => {
    addGroup('a');
    addGroup('b');
    setGroup('a', [{ cols: 'TEMP' }]);
    expect(renameGroup('b', 'a')).toBe(false);
    expect(exportCards().groups.a).toEqual([{ cols: 'TEMP' }]); // untouched
    expect(Object.keys(exportCards().groups)).toEqual(['a', 'b']);
  });

  it('removes a group', () => {
    addGroup('a');
    addGroup('b');
    removeGroup('a');
    expect(Object.keys(exportCards().groups)).toEqual(['b']);
  });
});

describe('confirmation', () => {
  // Solid 2 defers signal updates, so a write and the read that checks it cannot share a tick.
  it('remembers a definition as confirmed', async () => {
    const card = { type: 'rescale', suffix: 'rescaled' };
    expect(isConfirmed('node:a', card)).toBe(false);
    confirmDefinition('node:a', card);
    await flush();
    expect(isConfirmed('node:a', card)).toBe(true);
  });

  it('un-confirms itself when the definition changes', async () => {
    // Stored as a signature of the content rather than a flag. A card confirmed and then edited
    // is no longer something anyone declared finished, and a flag would go quietly stale.
    const card = { type: 'rescale', suffix: 'rescaled' };
    confirmDefinition('node:b', card);
    await flush();
    expect(isConfirmed('node:b', card)).toBe(true);
    expect(isConfirmed('node:b', { ...card, suffix: 'zscored' })).toBe(false);
  });

  it('keeps confirmations apart by key', async () => {
    const card = { type: 'rescale' };
    confirmDefinition('node:c', card);
    await flush();
    expect(isConfirmed('node:d', card)).toBe(false);
  });

  it('forgets one on request, for a definition that no longer exists', async () => {
    const card = { type: 'rescale' };
    confirmDefinition('node:e', card);
    await flush();
    forgetConfirmation('node:e');
    await flush();
    expect(isConfirmed('node:e', card)).toBe(false);
  });

  it('confirms two keys set back to back in the same tick, not only the last', async () => {
    // Solid 2 stages a signal write: a plain read right after a write in the same tick still
    // returns the pre-write value. Two `confirmDefinition` calls back to back used to each build
    // their map off the same stale read, so the second call's edit was the only one to survive a
    // flush — the fix is a functional updater, which chains off the previous updater's return
    // value instead of off a read.
    const card = { type: 'rescale' };
    confirmDefinition('node:h', card);
    confirmDefinition('node:i', card);
    await flush();
    expect(isConfirmed('node:h', card)).toBe(true);
    expect(isConfirmed('node:i', card)).toBe(true);
  });

  it('forgets two keys set in the same synchronous loop, not only the last', async () => {
    const card = { type: 'rescale' };
    confirmDefinition('node:j', card);
    confirmDefinition('node:k', card);
    await flush();
    expect(isConfirmed('node:j', card)).toBe(true);
    expect(isConfirmed('node:k', card)).toBe(true);

    for (const key of ['node:j', 'node:k']) forgetConfirmation(key);
    await flush();
    expect(isConfirmed('node:j', card)).toBe(false);
    expect(isConfirmed('node:k', card)).toBe(false);
  });
});

describe('the stores survive a reload', () => {
  it('cards: the document is restored verbatim', async () => {
    // A fresh module instance stands in for a reload: the stores are module-level, so re-importing
    // the module is exactly what a page load does.
    const first = await import('./stores');
    first.importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: { g: [] } });
    await flush();
    expect(JSON.parse(sessionStorage.getItem('dashi.cards')!).nodes[0].id).toBe('r');
  });

  it('filters: Interval and Set come back as themselves', async () => {
    const { FILTERS_STORE, filtersCodec } = await import('./stores');
    const [, set] = FILTERS_STORE;
    set((d) => { d.numerical.TEMP = new Interval(1, 2); d.categorical.cbwd = new Set(['NW']); });
    await flush();
    const raw = JSON.parse(sessionStorage.getItem('dashi.filters')!);
    const back = filtersCodec.decode(raw);
    expect(back.numerical.TEMP).toBeInstanceOf(Interval);
    expect(back.numerical.TEMP!.max).toBe(2);
    expect(back.categorical.cbwd).toBeInstanceOf(Set);
    expect(back.categorical.cbwd!.has('NW')).toBe(true);
  });

  it('verdicts are kept, with their findings', async () => {
    const { recordVerdict, verdictOf } = await import('./stores');
    recordVerdict('node:0', { type: 'rescale' }, 'rejected', [{ message: 'needs a value', pointer: '/nodes/0/card/inputs' }]);
    await flush();
    const raw = JSON.parse(sessionStorage.getItem('dashi.verdicts')!)['node:0'];
    expect(raw.verdict).toBe('rejected');
    expect(raw.findings[0].message).toBe('needs a value');
    expect(verdictOf('node:0', { type: 'rescale' })?.verdict).toBe('rejected');
  });
});

describe('references follow the thing they name', () => {
  // Check 6 by hand: deleting the group `empty` left `groups:empty` on the card, with no way to
  // remove it — the picker only offers switches for values in the vocabulary.
  const doc = () => ({
    nodes: [
      { id: 'r', card: { type: 'rescale', inputs: [{ groups: 'g' }, { cols: 'TEMP' }], group_by: [{ groups: 'g' }] } },
      { id: 's', card: { type: 'rescale', inputs: [{ nodes: 'r' }, { cols: 'PRES', through: ['r'] }] } },
    ],
    groups: { g: [{ cols: ['TEMP'] }], h: [{ groups: 'g' }, { cols: 'PRES' }] },
  });
  it('removeGroup drops every item naming the group', async () => {
    const s = await import('./stores');
    s.importCards(doc()); s.removeGroup('g'); await flush();
    const out = s.exportCards();
    expect(out.nodes[0].card.inputs).toEqual([{ cols: 'TEMP' }]);
    expect(out.nodes[0].card.group_by).toEqual([]);
    expect(out.groups.h).toEqual([{ cols: 'PRES' }]);
  });
  it('renameGroup rewrites them', async () => {
    const s = await import('./stores');
    s.importCards(doc()); s.renameGroup('g', 'wind'); await flush();
    const out = s.exportCards();
    expect(out.nodes[0].card.inputs).toEqual([{ groups: 'wind' }, { cols: 'TEMP' }]);
    expect(out.groups.h[0]).toEqual({ groups: 'wind' });
  });
  it('removeNode drops nodes: items and through entries', async () => {
    const s = await import('./stores');
    s.importCards(doc()); s.removeNode(0); await flush();
    const out = s.exportCards();
    expect(out.nodes[0].card.inputs).toEqual([{ cols: 'PRES' }]);   // `through: ['r']` gone with r
  });
  // Not every selector is a list. `$defs/variable` fields — `partition`, `weights`,
  // `gaussian_encoding.input`, `interp.input`, `glm.formula.target` — hold one selector object,
  // and a walk that only looked at arrays left them naming a group that no longer exists.
  const lone = () => ({
    nodes: [{ id: 'p', card: { type: 'split', partition: { groups: 'g' }, method: { type: 'tiles' } } }],
    groups: { g: [{ cols: 'TEMP' }] },
  });
  it('removeGroup drops a lone selector object that named it', async () => {
    const s = await import('./stores');
    s.importCards(lone()); s.removeGroup('g'); await flush();
    const card = s.exportCards().nodes[0].card;
    expect('partition' in card).toBe(false);
    expect(card.method).toEqual({ type: 'tiles' });   // a plain object beside it is untouched
  });
  it('renameGroup rewrites a lone selector object', async () => {
    const s = await import('./stores');
    s.importCards(lone()); s.renameGroup('g', 'wind'); await flush();
    expect(s.exportCards().nodes[0].card.partition).toEqual({ groups: 'wind' });
  });
  it('setNodeId rewrites nodes: items and through entries', async () => {
    const s = await import('./stores');
    s.importCards(doc()); s.setNodeId(0, 'rescaled'); await flush();
    const out = s.exportCards();
    expect(out.nodes[1].card.inputs).toEqual([{ nodes: 'rescaled' }, { cols: 'PRES', through: ['rescaled'] }]);
  });
  // Two cards with one name is a document the server cannot build, and it says so with no
  // pointer (measured 2026-09-17: `Encountered nodes with equal \`id\``, `issues: []`) — so no
  // card could show it. Refused at the source, as `renameGroup` refuses a second group's name.
  it('setNodeId refuses a name another card already has, and leaves the document alone', async () => {
    const s = await import('./stores');
    s.importCards(doc());
    expect(s.setNodeId(1, 'r')).toBe(false);
    await flush();
    const out = s.exportCards();
    expect(out.nodes.map((node) => node.id)).toEqual(['r', 's']);
    // Nothing that named `s` was rewritten to name `r`.
    expect(out.nodes[1].card.inputs).toEqual([{ nodes: 'r' }, { cols: 'PRES', through: ['r'] }]);
  });
  it('setNodeId says yes when the name is free, and when it is the card\'s own', async () => {
    const s = await import('./stores');
    s.importCards(doc());
    expect(s.setNodeId(0, 'rescaled')).toBe(true);
    expect(s.setNodeId(1, 's')).toBe(true);
    await flush();
    expect(s.exportCards().nodes.map((node) => node.id)).toEqual(['rescaled', 's']);
  });
  it('setNodeId counts a card with no id as named "", which only one card can be', async () => {
    // `Pipelines.get_id` defaults a missing id to "", so two unnamed cards collide exactly as two
    // cards called `a` do (measured on the same day, same error).
    const s = await import('./stores');
    s.importCards({ nodes: [{ card: { type: 'rescale' } }, { id: 's', card: { type: 'rescale' } }], groups: {} });
    expect(s.setNodeId(1, '')).toBe(false);
    await flush();
    expect(s.exportCards().nodes[1].id).toBe('s');
  });
});

describe('pruneFilters', () => {
  it('drops filters on columns the loaded table lacks, keeps the rest, and says which', async () => {
    const s = await import('./stores');
    const [, setFilters] = s.FILTERS_STORE;
    setFilters(() => ({
      numerical: { TEMP: new s.Interval(0, 1), PRES: new s.Interval(0, 1) },
      categorical: { cbwd: new Set(['NW']) },
    }));
    await flush();
    const dropped = s.pruneFilters([{ name: 'TEMP' }, { name: 'No' }]);
    await flush();
    expect(dropped).toEqual(['PRES', 'cbwd']);
    expect(Object.keys(s.FILTERS_STORE[0].numerical)).toEqual(['TEMP']);
    expect(Object.keys(s.FILTERS_STORE[0].categorical)).toEqual([]);
    expect(s.droppedFilters()).toEqual(['PRES', 'cbwd']);
  });

  it('drops nothing when every column is present, and nothing when no table is loaded', async () => {
    const s = await import('./stores');
    const [, setFilters] = s.FILTERS_STORE;
    setFilters(() => ({ numerical: { TEMP: new s.Interval(0, 1) }, categorical: {} }));
    await flush();
    expect(s.pruneFilters([{ name: 'TEMP' }])).toEqual([]);
    // No summaries means no table: a document's filters cannot be judged, so they stay.
    expect(s.pruneFilters([])).toEqual([]);
    await flush();
    expect(Object.keys(s.FILTERS_STORE[0].numerical)).toEqual(['TEMP']);
  });
});

describe('verdicts', () => {
  it('bind to the exact content, and expire when it changes', async () => {
    const s = await import('./stores');
    s.recordVerdict('node:0', { type: 'rescale', suffix: 'z' }, 'rejected', [{ message: 'needs a value', pointer: '/nodes/0/card/inputs' }]);
    await flush();
    expect(s.verdictOf('node:0', { type: 'rescale', suffix: 'z' })).toEqual({
      signature: JSON.stringify({ type: 'rescale', suffix: 'z' }),
      verdict: 'rejected',
      findings: [{ message: 'needs a value', pointer: '/nodes/0/card/inputs' }],
    });
    expect(s.verdictOf('node:0', { type: 'rescale', suffix: 'zz' })).toBeNull(); // edited: no verdict
    expect(s.isConfirmed('node:0', { type: 'rescale', suffix: 'z' })).toBe(false);
    s.recordVerdict('node:0', { type: 'rescale', suffix: 'z' }, 'confirmed');
    await flush();
    expect(s.isConfirmed('node:0', { type: 'rescale', suffix: 'z' })).toBe(true);
    expect(s.verdictOf('node:0', { type: 'rescale', suffix: 'z' })?.findings).toEqual([]);
  });

  it('keep every write of one tick, and forget on request', async () => {
    const s = await import('./stores');
    s.recordVerdict('group:a', [], 'confirmed');
    s.recordVerdict('group:b', [], 'rejected', [{ message: 'x' }]);
    await flush();
    expect(s.verdictOf('group:a', [])?.verdict).toBe('confirmed');
    expect(s.verdictOf('group:b', [])?.verdict).toBe('rejected');
    s.forgetVerdict('group:a');
    await flush();
    expect(s.verdictOf('group:a', [])).toBeNull();
    expect(s.verdictOf('group:b', [])?.verdict).toBe('rejected');
    s.forgetAllVerdicts();
    await flush();
    expect(s.verdictOf('group:b', [])).toBeNull();
  });

  it('a failed run rejects exactly the items its issues point at', async () => {
    const s = await import('./stores');
    s.importCards({
      nodes: [
        { id: 'a', card: { type: 'cluster' } },
        { id: 'b', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [{ cols: 'TEMP' }], suffix: 'z' } },
      ],
      groups: { g: [], h: [{ cols: 'TEMP' }] },
    });
    await flush();
    const issue = (over: Partial<ProbeIssue>): ProbeIssue => ({
      pointer: '', reason: 'required', severity: 'error', found: null, allowed: null, missing: [], related: [], message: 'x', ...over,
    });
    s.rejectFromIssues([
      issue({ pointer: '/nodes/0/card', missing: ['method', 'inputs'], related: ['/nodes/0/card/method', '/nodes/0/card/inputs'] }),
      issue({ pointer: '/groups/g', reason: 'empty', message: 'group `g` has no columns' }),
      issue({ pointer: '/nodes/1/card', reason: 'overwrites', severity: 'warning', message: '`TEMP_z` already exists' }),
    ]);
    await flush();
    const cards = s.exportCards();
    // A card's verdict binds to the whole node: its id is part of what was checked.
    expect(s.verdictOf('node:0', cards.nodes[0])?.verdict).toBe('rejected');
    expect(s.verdictOf('node:0', cards.nodes[0])?.findings.map((f) => f.pointer))
      .toEqual(['/nodes/0/card/method', '/nodes/0/card/inputs']);
    expect(s.verdictOf('group:g', cards.groups.g)?.verdict).toBe('rejected');
    expect(s.verdictOf('group:g', cards.groups.g)?.findings[0].message).toMatch(/has no columns/);
    expect(s.verdictOf('node:1', cards.nodes[1])).toBeNull(); // a warning is not a rejection
    expect(s.verdictOf('group:h', cards.groups.h)).toBeNull();
    expect(s.PROBE_STORE[0].valid).toBe(true); // verdicts only: the probe store is not written here
  });

  it('a failed run binds to the document that was sent, not to the store as it is later', async () => {
    const s = await import('./stores');
    s.forgetAllVerdicts();
    s.importCards({ nodes: [{ id: 'a', card: { type: 'cluster' } }], groups: {} });
    await flush();
    const sent = s.exportCards();
    s.setCardField(0, 'output', 'edited');
    await flush(); // the store now differs from what was sent
    s.rejectFromIssues([{
      pointer: '/nodes/0/card', reason: 'required', severity: 'error', found: null, allowed: null,
      missing: ['method'], related: ['/nodes/0/card/method'], message: 'x',
    }], sent);
    await flush();
    expect(s.verdictOf('node:0', sent.nodes[0])?.verdict).toBe('rejected');
    expect(s.verdictOf('node:0', s.exportCards().nodes[0])).toBeNull();
  });

  it('rejectFromIssues records the rejection and leaves the probe store alone', async () => {
    // The probe store has one writer, the continuous probe, sequenced by `probeSeq`
    // (`processing.tsx`). A second, unsequenced writer let an older probe reply erase a failed
    // run's issues — measured 2026-09-17 — and the line next to Run lost the run's names.
    const s = await import('./stores');
    s.forgetAllVerdicts();
    s.importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: {} });
    s.PROBE_STORE[1](reconcile(s.emptyProbe()));
    s.rejectFromIssues([{
      pointer: '/nodes/0/card/inputs', reason: 'required', severity: 'error', found: null,
      allowed: null, missing: ['inputs'], related: ['/nodes/0/card/inputs'], message: 'x',
    }]);
    await flush();
    expect(s.verdictOf('node:0', s.exportCards().nodes[0])?.verdict).toBe('rejected');
    expect(s.PROBE_STORE[0].valid).toBe(true);
    expect(s.PROBE_STORE[0].issues).toEqual([]);
  });

  describe('the document verdict', () => {
    // A relational fault — a loop — is nobody's card: seen in a browser on 2026-09-18 written on
    // every card that was asked. It gets a verdict of its own, bound to the whole cards
    // document, so it is said once (next to Run) and any edit expires it.
    const doc = () => ({
      nodes: [{ id: 'a', card: { type: 'rescale' } }, { id: 'b', card: { type: 'rescale' } }],
      groups: {},
    });
    it('is recorded on the document that was asked about, and read back while it is unchanged', async () => {
      const s = await import('./stores');
      s.forgetAllVerdicts();
      s.importCards(doc());
      await flush();
      expect(s.documentVerdict()).toBeNull();
      s.rejectDocument(s.exportCards(), [{ message: 'a loop: a, b' }]);
      await flush();
      expect(s.documentVerdict()?.verdict).toBe('rejected');
      expect(s.documentVerdict()?.findings).toEqual([{ message: 'a loop: a, b' }]);
    });
    it('expires on any edit of the document', async () => {
      const s = await import('./stores');
      s.forgetAllVerdicts();
      s.importCards(doc());
      await flush();
      s.rejectDocument(s.exportCards(), [{ message: 'x' }]);
      s.setCardField(1, 'suffix', 'edited');
      await flush();
      expect(s.documentVerdict()).toBeNull();
    });
    it('binds whatever key order the document arrived in', async () => {
      // A loaded file may say `groups` before `nodes`; the store holds `nodes` first.
      const s = await import('./stores');
      s.forgetAllVerdicts();
      s.importCards(doc());
      await flush();
      const { nodes, groups } = s.exportCards();
      s.rejectDocument({ groups, nodes }, [{ message: 'x' }]);
      await flush();
      expect(s.documentVerdict()?.verdict).toBe('rejected');
    });
  });

  describe('documentFindings', () => {
    const pointed = {
      pointer: '/nodes/0/card/method', reason: 'type', severity: 'error' as const, found: 'zscore',
      allowed: null, missing: [], related: [], message: 'Schema Validation Error',
    };
    it('is the errors when the document does not build and no issue names an item', async () => {
      // The server's literal reply for two cards named `a` (measured 2026-09-17).
      const s = await import('./stores');
      expect(s.documentFindings({
        valid: false, issues: [], errors: ['ArgumentError: Encountered nodes with equal `id`'],
      })).toEqual([{ message: 'ArgumentError: Encountered nodes with equal `id`' }]);
    });
    it('is empty when every error is pointed at an item', async () => {
      // A schema failure's `errors` is the issues' own messages run together; those are read on
      // the items, and confirming an unrelated card must still go green.
      const s = await import('./stores');
      expect(s.documentFindings({
        valid: false, issues: [pointed], errors: ['1 schema validation error:\nSchema Validation Error'],
      })).toEqual([]);
    });
    it('is empty when the document builds', async () => {
      const s = await import('./stores');
      expect(s.documentFindings({ valid: true, issues: [], errors: [] })).toEqual([]);
    });
    it('carries the message of an issue that points at no item, beside pointed ones', async () => {
      const s = await import('./stores');
      expect(s.documentFindings({
        valid: false,
        issues: [pointed, { ...pointed, pointer: '', message: 'nothing to run' }],
        errors: ['x'],
      })).toEqual([{ message: 'nothing to run' }]);
    });
    it('does not say a sentence twice when the errors repeat a loose issue\'s message', async () => {
      // The server's loop reply: one issue that points at no item, and `errors` holding that
      // same message (`errors` is always the issues' messages, for a client that reads only it).
      const s = await import('./stores');
      const loop = { ...pointed, pointer: '', reason: 'loop', message: 'The input graph contains at least one loop: a, b' };
      expect(s.documentFindings({ valid: false, issues: [loop], errors: [loop.message] }))
        .toEqual([{ message: loop.message }]);
    });
    it('ignores warnings', async () => {
      const s = await import('./stores');
      expect(s.documentFindings({
        valid: true, issues: [{ ...pointed, pointer: '', severity: 'warning' }], errors: [],
      })).toEqual([]);
    });
  });

  it('a removed group takes its verdict with it; a renamed one keeps it under the new name', async () => {
    const s = await import('./stores');
    s.forgetAllVerdicts();
    s.importCards({ nodes: [], groups: { g: [], h: [{ cols: 'TEMP' }] } });
    await flush();
    s.recordVerdict('group:g', [], 'rejected', [{ message: 'group `g` has no columns' }]);
    s.recordVerdict('group:h', [{ cols: 'TEMP' }], 'confirmed');
    await flush();
    s.removeGroup('g');
    s.addGroup('g'); // same name, same (empty) content as the one that was rejected
    await flush();
    expect(s.verdictOf('group:g', [])).toBeNull(); // amber until asked, not red by inheritance
    expect(s.renameGroup('h', 'weather')).toBe(true);
    await flush();
    expect(s.verdictOf('group:weather', [{ cols: 'TEMP' }])?.verdict).toBe('confirmed');
    expect(s.verdictOf('group:h', [{ cols: 'TEMP' }])).toBeNull();
  });

  it('follow their card when an earlier one is removed', async () => {
    const s = await import('./stores');
    s.forgetAllVerdicts();
    s.importCards({
      nodes: [{ id: 'a', card: { type: 'rescale' } }, { id: 'b', card: { type: 'cluster' } }],
      groups: { g: [] },
    });
    await flush();
    const [a, b] = s.exportCards().nodes;
    s.recordVerdict('node:0', a, 'confirmed');
    s.recordVerdict('node:1', b, 'rejected', [{ message: 'needs a value', pointer: '/nodes/1/card/method' }]);
    s.recordVerdict('group:g', [], 'rejected', [{ message: 'x' }]);
    await flush();
    s.removeNode(0);
    await flush();
    expect(s.verdictOf('node:0', b)?.verdict).toBe('rejected');   // b is at 0 now, still red
    expect(s.verdictOf('node:0', b)?.findings[0].message).toBe('needs a value');
    // and the finding's pointer moved with it, so a control lookup lands on the right card
    expect(s.verdictOf('node:0', b)?.findings[0].pointer).toBe('/nodes/0/card/method');
    expect(s.verdictOf('node:1', b)).toBeNull();
    expect(s.verdictOf('group:g', [])?.verdict).toBe('rejected'); // groups are untouched
  });
});
