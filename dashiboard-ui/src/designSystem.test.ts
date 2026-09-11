import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Invariants of the design system, as tests rather than as sweeps someone remembers to re-run.
//
// Borrowed from nexus-weaver-pro (2026-09-11), who made the same checks permanent after their
// §3c bug — a `.dark` block missing the status scales — went unnoticed for as long as dark mode
// was unreachable. Both checks below are ones this session ran by hand more than once, which is
// the argument for them existing.

const read = (p: string) => readFileSync(join(process.cwd(), p), 'utf8');

/** The declarations inside one top-level CSS block, by selector. */
function blockOf(css: string, selector: string): Set<string> {
  const open = css.indexOf(`${selector} {`);
  if (open === -1) throw new Error(`no ${selector} block in App.css`);
  let depth = 1;
  let i = open + `${selector} {`.length;
  while (depth > 0 && i < css.length) {
    if (css[i] === '{') depth += 1;
    else if (css[i] === '}') depth -= 1;
    i += 1;
  }
  const body = css.slice(open + `${selector} {`.length, i - 1);
  return new Set([...body.matchAll(/(--[a-z-]+)\s*:/g)].map((m) => m[1]));
}

function sourceFiles(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) sourceFiles(full, out);
    else if (/\.tsx?$/.test(entry) && !entry.includes('.test.')) out.push(full);
  }
  return out;
}

describe('the palette', () => {
  it('gives every token a dark value, except the one that is a length', () => {
    // This is nexus-weaver's §3c defect exactly: their `.dark` omitted the status scales and the
    // shadows, which was invisible only because dark mode could not be reached. Ours can be now,
    // but a missing dark value still fails silently in light — so it needs a test, not an eye.
    const css = read('src/App.css');
    const light = blockOf(css, ':root');
    const dark = blockOf(css, '.dark');
    expect([...light].filter((token) => !dark.has(token))).toEqual(['--radius']);
  });

  it('has no dark-only token, which would be a light mode with a hole in it', () => {
    const css = read('src/App.css');
    const light = blockOf(css, ':root');
    const dark = blockOf(css, '.dark');
    expect([...dark].filter((token) => !light.has(token))).toEqual([]);
  });
});

describe('colour', () => {
  it('never names a Tailwind palette colour directly', () => {
    // Every colour goes through a token, or a host payload cannot repaint it. A literal here is
    // not a style mistake — it is a hole in the theming contract, and it looks completely normal
    // in review.
    const RAMPS =
      'gray|blue|red|green|yellow|indigo|slate|zinc|sky|emerald|amber|rose|teal|cyan|violet|purple|orange|lime|stone|neutral';
    const literal = new RegExp(`\\b[a-z:-]*-(?:${RAMPS})-[0-9]{2,3}\\b|\\b(?:bg|text|border)-(?:white|black)\\b`);
    const offenders = sourceFiles('src')
      .map((file) => [file, read(file)] as const)
      .filter(([, body]) => literal.test(body))
      .map(([file]) => file);
    expect(offenders).toEqual([]);
  });
});
