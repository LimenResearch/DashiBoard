import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { API_ROUTES, DOCUMENT_ROUTES } from './apiRoutes';
import { endpointOf } from './requests';

// The dev server forwards a route to the Julia server only if the route is on its list; one left
// off answers with Vite's own 404 page, which the form reads as "the server is down".

const sources = (dir: string): string[] =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sources(path);
    return /\.(ts|tsx)$/.test(name) && !/\.test\./.test(name) ? [path] : [];
  });

describe('the routes the form reaches', () => {
  // A call reaches the endpoint `endpointOf` names for its method; a link names its route itself.
  const used = new Set<string>();
  const links = new Set<string>();
  for (const file of sources(join(__dirname))) {
    const text = readFileSync(file, 'utf8');
    for (const m of text.matchAll(/(?:postRequest|postBlob)\(\s*["'`]([a-z-]+)["'`]/g)) used.add(m[1]);
    for (const m of text.matchAll(/getURL\(\s*["'`]([a-z-]+)["'`]/g)) links.add(m[1]);
  }
  // The document routes are built from the kind, so they are named by the table they come from.
  for (const route of Object.values(DOCUMENT_ROUTES)) { used.add(`read-${route}`); used.add(`write-${route}`); }

  it('finds the calls and the link it is meant to check', () => {
    expect(used.has('list-files') && used.has('bundle-pipeline') && used.has('probe-pipeline')).toBe(true);
    expect(links.has('get-processed-data')).toBe(true);
  });

  it('are all forwarded by the dev server', () => {
    const forwarded = new Set(API_ROUTES.map((route) => route.replace(/^\//, '')));
    const reached = [...[...used].map((method) => endpointOf(method).endpoint), ...links];
    expect(reached.filter((route) => !forwarded.has(route)).sort()).toEqual([]);
  });
});
