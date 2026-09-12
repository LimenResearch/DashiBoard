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
  it('gives every colour token a dark value', () => {
    // This is nexus-weaver's §3c defect exactly: their `.dark` omitted the status scales and the
    // shadows, which was invisible only because dark mode could not be reached. Ours can be now,
    // but a missing dark value still fails silently in light — so it needs a test, not an eye.
    //
    // The exceptions are enumerated rather than inferred. Every one is a *length*, which has no
    // light and dark form; listing them means adding a colour without a dark value still fails,
    // which is the whole point of the check.
    const MODE_INDEPENDENT = [
      '--radius',
      '--control-height-default', '--control-height-sm', '--control-height-xs',
      '--control-text-default', '--control-text-sm', '--control-text-xs',
      '--control-leading-default', '--control-leading-sm', '--control-leading-xs',
      '--text-detail', '--text-detail-leading',
    ];
    const css = read('src/App.css');
    const light = blockOf(css, ':root');
    const dark = blockOf(css, '.dark');
    expect([...light].filter((token) => !dark.has(token)).sort()).toEqual(
      [...MODE_INDEPENDENT].sort(),
    );
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

describe('density', () => {
  it('never sets a control height at the call site', () => {
    // The ratchet, borrowed from nexus-weaver: 100 height overrides accumulated there because
    // the system had no compact step for them to live in. Ours does, so a literal here is a call
    // site opting out of the one channel a host can resize us through — which no payload can
    // undo. Container heights (`h-80`, `h-96`) are not control heights and are left alone.
    const CONTROL_HEIGHT = /(?<![\w-])h-(?:[4-9]|1[0-2])(?![\w-])/;
    const offenders = sourceFiles('src')
      .map((file) => [file, read(file)] as const)
      // Strip comments first: prose about `h-10` is discussion, not a declaration.
      .map(([file, body]) => [file, body.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, '')] as const)
      .filter(([, body]) => CONTROL_HEIGHT.test(body))
      .map(([file]) => file);
    expect(offenders).toEqual([]);
  });
});

describe('the control scale', () => {
  const scale = () => {
    const css = read('src/App.css');
    const root = css.slice(css.indexOf(':root {'));
    const value = (token: string) =>
      root.match(new RegExp(`${token}:\\s*([^;]+);`))?.[1].trim();
    return value;
  };

  it('pins every step to the size it stands in for', () => {
    // nexus-weaver's sharpest point, and the uncomfortable one: the whole purpose of a token is
    // that it can be varied, which means nothing else in the system will ever notice if it is
    // varied by accident. Tokenising removes a guard rail at the same moment it adds a
    // capability. This is the rail put back — the numbers are the Tailwind sizes these replaced.
    const value = scale();
    expect(value('--control-height-default')).toBe('2.5rem'); // h-10
    expect(value('--control-height-sm')).toBe('2rem'); //        h-8
    expect(value('--control-height-xs')).toBe('1.75rem'); //     h-7
    expect(value('--control-text-default')).toBe('0.875rem'); // text-sm
    expect(value('--control-text-sm')).toBe('0.75rem'); //       text-xs
    expect(value('--control-text-xs')).toBe('0.75rem'); //       text-xs
    expect(value('--control-leading-default')).toBe('1.25rem'); // text-sm's leading
    expect(value('--control-leading-sm')).toBe('1rem'); //         text-xs's leading
    expect(value('--control-leading-xs')).toBe('1rem'); //         text-xs's leading
  });

  it('names a leading wherever it names a font size', () => {
    // Tailwind's `text-*` sets both; a token carrying only the size drops the leading silently,
    // and the control inherits whatever surrounds it. We shipped that for three commits.
    // Scoped to the control scale rather than to any `*-text-*` name: a looser pattern matches
    // third-party variables like `--choices-text-color`, where "text" is a noun, not a size.
    const css = read('src/App.css');
    const steps = [...css.matchAll(/--control-text-(\w+):/g)].map((m) => m[1]);
    const leadings = [...css.matchAll(/--control-leading-(\w+):/g)].map((m) => m[1]);
    expect(steps.length).toBeGreaterThan(0);
    expect(steps.filter((step) => !leadings.includes(step))).toEqual([]);
  });

  it('sets font size and leading together in every text utility', () => {
    const css = read('src/App.css');
    const utilities = [...css.matchAll(/@utility (text-[\w-]+) \{([^}]*)\}/g)];
    expect(utilities.length).toBeGreaterThan(0);
    const sizeOnly = utilities
      .filter(([, , body]) => body.includes('font-size') && !body.includes('line-height'))
      .map(([, name]) => name);
    expect(sizeOnly).toEqual([]);
  });
});
