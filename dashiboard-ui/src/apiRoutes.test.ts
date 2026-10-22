import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { API_ROUTES } from './apiRoutes';

// The dev server forwards a route to the Julia server only if the route is on its list; one left
// off answers with Vite's own 404 page, which the form reads as "the server is down".

const sources = (dir: string): string[] =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sources(path);
    return /\.(ts|tsx)$/.test(name) && !/\.test\./.test(name) ? [path] : [];
  });

describe('the routes the form reaches', () => {
  // Calls go to the three JSON-RPC endpoints; a link names its route itself.
  const used = new Set<string>(['rpc', 'rpc-probe', 'rpc-stream']);
  for (const file of sources(join(__dirname))) {
    const text = readFileSync(file, 'utf8');
    for (const m of text.matchAll(/getURL\(\s*["'`]([a-z-]+)["'`]/g)) used.add(m[1]);
  }

  it('finds the link it is meant to check', () => {
    expect(used.has('get-processed-data')).toBe(true);
  });

  it('are all forwarded by the dev server', () => {
    const forwarded = new Set(API_ROUTES.map((route) => route.replace(/^\//, '')));
    expect([...used].filter((route) => !forwarded.has(route)).sort()).toEqual([]);
  });
});
