import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { apiBase, setApiBase, getURL, postBlob, postRequest } from './requests';
import { failureOf, isRpcError } from './rpcError';

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

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const sent = (call: unknown[]) => JSON.parse((call[1] as RequestInit).body as string);

describe('postRequest', () => {
  const fetchMock = vi.fn();
  beforeEach(() => {
    fetchMock.mockReset(); vi.stubGlobal('fetch', fetchMock);
    setApiBase(null); document.querySelector('meta[name="dashi-api"]')?.remove();
  });
  afterEach(() => { vi.unstubAllGlobals(); });

  it('sends a JSON-RPC request to /rpc and hands back the result', async () => {
    fetchMock.mockResolvedValue(json({ jsonrpc: '2.0', id: 1, result: { files: [] } }));
    expect(await postRequest('list-files', {}, null)).toEqual({ files: [] });
    expect(fetchMock.mock.calls[0][0]).toBe('/rpc');
    expect(sent(fetchMock.mock.calls[0])).toEqual({ jsonrpc: '2.0', id: expect.any(Number), method: 'list-files', params: {} });
  });

  it('probes through /rpc-probe, as the run route', async () => {
    fetchMock.mockResolvedValue(json({ jsonrpc: '2.0', id: 1, result: {} }));
    await postRequest('probe-pipeline', { nodes: [] }, null);
    expect(fetchMock.mock.calls[0][0]).toBe('/rpc-probe');
    expect(sent(fetchMock.mock.calls[0]).method).toBe('evaluate-pipeline');
  });

  it('hands back a failure as {error}, read through failureOf', async () => {
    const error = { code: -32602, message: 'm', data: null };
    fetchMock.mockResolvedValue(json({ jsonrpc: '2.0', id: 1, error }));
    const got = await postRequest('list-files', {}, null);
    expect(got).toEqual({ error });
    expect(isRpcError(got) && failureOf(got)).toEqual({ errors: ['m'] });
    const data = { kind: 'pipeline', errors: ['e'], issues: [] };
    expect(failureOf({ error: { ...error, data } })).toEqual(data);
  });

  it('reads a streamed reply by its status', async () => {
    fetchMock.mockResolvedValue(json({ values: [1], length: 1 }));
    expect(await postRequest('fetch-data', {}, null)).toEqual({ values: [1], length: 1 });
    expect(fetchMock.mock.calls[0][0]).toBe('/rpc-stream');
    const error = { code: -32603, message: 'boom', data: null };
    fetchMock.mockResolvedValue(json({ jsonrpc: '2.0', id: 1, error }, 500));
    expect(await postRequest('fetch-data', {}, null)).toEqual({ error });
  });

  it('is its default when the server cannot be reached', async () => {
    fetchMock.mockRejectedValue(new Error('down'));
    expect(await postRequest('list-files', {}, 'def')).toBe('def');
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
    expect(fetchMock.mock.calls[0][0]).toBe('http://127.0.0.1:8080/rpc-stream');
    expect(sent(fetchMock.mock.calls[0]).method).toBe('bundle-pipeline');
  });
  // A refusal comes back as the JSON-RPC error, with a failing status.
  it('hands back the error when the server refused', async () => {
    const error = { code: -32602, message: 'm', data: { errors: ['no'] } };
    fetchMock.mockResolvedValue(json({ jsonrpc: '2.0', id: 1, error }, 400));
    expect(await postBlob('bundle-pipeline', {})).toEqual({ error });
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
