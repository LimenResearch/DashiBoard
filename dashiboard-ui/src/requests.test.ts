import { describe, it, expect, beforeEach } from 'vitest';
import { apiBase, setApiBase, getURL } from './requests';

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
