import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { apiBase, setApiBase, getURL, postBlob } from './requests';

describe('apiBase', () => {
  beforeEach(() => {
    setApiBase(null);
    window.history.replaceState({}, '', '/');
    document.querySelector('meta[name="dashi-api"]')?.remove();
    delete (globalThis as Record<string, unknown>).__DASHI_API__;
  });

  it('defaults to same-origin relative URLs', () => {
    // the section 10 production case: ExperimentTracking serves the bundle beside the API
    expect(apiBase()).toBe('');
    expect(getURL('get-card-ir')).toBe('/get-card-ir');
  });

  it('takes an explicit runtime override', () => {
    setApiBase('http://127.0.0.1:8080');
    expect(getURL('get-card-ir')).toBe('http://127.0.0.1:8080/get-card-ir');
  });

  it('normalises slashes on both sides', () => {
    setApiBase('http://127.0.0.1:8080/');
    expect(getURL('/get-card-ir')).toBe('http://127.0.0.1:8080/get-card-ir');
  });

  it('reads ?api= from the page URL', () => {
    window.history.replaceState({}, '', '/?api=http://localhost:9999');
    expect(getURL('cards')).toBe('http://localhost:9999/cards');
  });

  it('prefers an explicit override to ?api=', () => {
    window.history.replaceState({}, '', '/?api=http://from-query');
    setApiBase('http://from-code');
    expect(getURL('cards')).toBe('http://from-code/cards');
  });

  it('reads a <meta> tag injected by whatever serves the page', () => {
    const m = document.createElement('meta');
    m.setAttribute('name', 'dashi-api');
    m.setAttribute('content', 'http://from-meta');
    document.head.appendChild(m);
    expect(getURL('cards')).toBe('http://from-meta/cards');
  });
});

describe('postBlob', () => {
  const fetchMock = vi.fn();
  beforeEach(() => { vi.stubGlobal('fetch', fetchMock); setApiBase('http://127.0.0.1:8080'); });
  afterEach(() => { vi.unstubAllGlobals(); });

  it('hands back a zip with the name the server gave it', async () => {
    const body = new Blob(['z'], { type: 'application/zip' });
    fetchMock.mockResolvedValue(new Response(body, { headers: { 'Content-Type': 'application/zip', 'Content-Disposition': 'attachment; filename="mine.zip"' } }));
    const got = await postBlob('bundle-pipeline', { name: 'mine' });
    expect(got && 'blob' in got && got.filename).toBe('mine.zip');
    expect(fetchMock.mock.calls[0][0]).toBe('http://127.0.0.1:8080/bundle-pipeline');
  });
  // The failure envelope is JSON, so the caller can read the sentence.
  it('hands back the JSON when the server answered with one', async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ valid: false, errors: ['no'] }), { headers: { 'Content-Type': 'application/json' } }));
    const got = await postBlob('bundle-pipeline', {});
    expect(got).toEqual({ json: { valid: false, errors: ['no'] } });
  });
  // An answer that is neither the file nor the server's own JSON — a proxy's 404 page, a bare
  // 500 — is no answer: saving it as a zip would hand the author a broken file.
  it('is null when what came back is not the server\'s answer', async () => {
    fetchMock.mockResolvedValue(new Response('<html>404</html>', { status: 404, headers: { 'Content-Type': 'text/html' } }));
    expect(await postBlob('bundle-pipeline', {})).toBeNull();
    fetchMock.mockResolvedValue(new Response('', { status: 500 }));
    expect(await postBlob('bundle-pipeline', {})).toBeNull();
  });
  it('is null when the server cannot be reached', async () => {
    fetchMock.mockRejectedValue(new Error('down'));
    expect(await postBlob('bundle-pipeline', {})).toBeNull();
  });
});
