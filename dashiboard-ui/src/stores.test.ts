import { describe, it, expect, beforeEach } from 'vitest';
import {
  emptyCards, importCards, exportCards, setCard, setCardField, addNode, removeNode, setNodeId,
  issuesForNode, fieldPath, type ProbeIssue,
  addGroup, removeGroup, renameGroup, setGroup,
  CARDS_STORE, type CardsStore,
} from './stores';
import { getCards } from './left-tabs/processing';

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
