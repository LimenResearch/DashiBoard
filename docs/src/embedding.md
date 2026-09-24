# Embedding the UI

The DashiBoard UI is built to run two ways: on its own, served by the Julia server, and inside
another application's page, as one menu of that application's own interface. This page calls that
application **the host**.

This page records what that relationship is, what exists today and what does not. **Most of it is
agreed direction rather than working code**, and the table says which is which, so nobody builds
against a contract that was never implemented.

Checked against the host's own code on 2026-09-24.

| piece | DashiBoard | the host |
|---|---|---|
| the frame | n/a | **not built** — no `iframe`, no embed route |
| API address at runtime | **done** | **done** — its service registry returns the resolved URL |
| light/dark mode in the frame URL | **done** | **not built** — no publisher |
| the token payload | **not built** | **not built** |
| one node ↔ one pipeline | n/a | shape exists; **the write path is not wired** |

## The mechanism: an iframe

The host embeds the UI as an `<iframe>` pointed at the address its own service registry resolves
for DashiBoard. That address is a runtime, user-editable value on both sides — which is
why the UI never bakes an API base into its bundle (`dashiboard-ui/src/requests.ts`): one build
serves same-origin behind the Julia server and through a dev proxy alike.

The host proposed this, and nothing since argues against it, but it has never been implemented or
ratified in code on either side. Treat it as the agreed direction.

## Theming across the frame

CSS custom properties do not cross a frame boundary, so both the *mode* and the *token values*
have to be sent explicitly.

### The mode, in the URL

`?theme=dark` (or `light`), read **once at load and never again**
(`dashiboard-ui/src/theme.ts`). Reading it at load is what lets the frame know the mode before its
first paint, so a light panel never flashes inside a dark application. A host must never
re-navigate the frame to change the mode: that remounts the app and destroys the work in it, which
is worse than the flash it would avoid. With no parameter the UI follows the operating system, and
its own toggle is a real control.

This is DashiBoard's design. The host has no theme publisher, so nothing on that side agrees to it
yet.

!!! warning "Known limitation: the host's mode is togglable at runtime"

    The host ships a theme toggle that defaults to the system preference, so a reader can change
    mode at any moment without navigating. Read-once means an embedded frame keeps the mode it was
    opened with until something reloads it. This is the strongest reason for the message channel
    below to exist; until it does, a frame can be a mode behind its host.

### The token values, by message

Everything else — the palette, the density and type metrics, and every mode change after the
first — is designed to arrive by `postMessage`, after the frame signals it is ready. Nothing sends
or receives this today.

Four rules, each of which fails silently if broken:

**Read computed styles, never stylesheet source.** Seven of the host's tokens are `var()` aliases
where they are written — including four colours (`--ring`, `--sidebar-ring`,
`--sidebar-primary-foreground`, and dark's `--destructive-foreground`). A source reader gets the
literal string `var(--primary)`, which means nothing in the frame: it resolves against the
*frame's* token or against nothing at all, giving a wrong colour with no error.
`getComputedStyle(...).getPropertyValue(...)` substitutes them. This is not hypothetical — the
host's own contrast test hit it, and its palette parser skipped what it could not parse, which
left the other mode's value in place and produced a confident wrong answer rather than a gap.

**Do not assume one value shape.** There are three: colours as bare `H S% L%` triplets, lengths
such as `2.5rem`, and **unitless ratios** such as `1.4286` for line heights. The ratios are
deliberately unitless so that leading follows whatever font size a host sets; a consumer that
treats every value as a triplet mangles the density and type tokens specifically.

**Send the whole set every time, never a delta.** Tokens derive from one another — `--ring` from
`--primary`, gradients from two others — so editing one declaration changes several computed
values. A host sending "what moved" omits the derived ones and leaves the frame's focus ring out
of step with its buttons. The full set is a few hundred bytes.

**Enumerate the properties; never list them by hand.** A written list is how density came to be
missing from the first version of this contract: colour was enumerated by hand and nobody thought
of density as something that varies. A payload that omits a token looks exactly like a complete
one.

Two figures worth knowing when building either end: the host declares **51 tokens on `:root` and
37 on `.dark`**, and the 14-token gap is deliberate — geometry and typography do not vary by mode,
so they are declared once. Anything that diffs the two blocks will read them as missing in dark;
computed styles make the question disappear. The metrics are nine `--control-<property>-<step>`
properties plus four `--text-*` ones.

## The data boundary

One node of the host's graph points at one whole pipeline, by pipeline id. An id goes in, a
selection comes back out. That is the entire relationship, and nothing
richer is warranted until something asks for it.

On the host's side the field exists and its editor sets it, but only in local component state:
the call that would persist it is defined and never invoked, and its "open DashiBoard" navigates
to its own page rather than to a frame. So a selection currently lasts until the page unmounts.

## Who owes what

Every unbuilt piece above belongs to the host: the frame, the token publisher, and the wiring that
persists a pipeline selection. On the DashiBoard side the mode parameter and the runtime-resolved
API address are done.

The one open question for DashiBoard is whether to stub the `postMessage` receiver before there is
anything to send it, so that the host can publish the moment it builds a publisher — against the
known limitation recorded above.
