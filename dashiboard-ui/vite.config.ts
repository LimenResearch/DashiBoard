import tailwindcss from '@tailwindcss/vite';
import { fileRoutes } from 'filesystem-routing/vite';
import { defineConfig } from 'vitest/config';
import solid from '@solidjs/vite-plugin';

export default defineConfig({
  // Turnkey client mode: no index.html and no mount file — the plugin
  // generates the entries around src/App.tsx, wrapped in src/Document.tsx
  // (or a built-in shell). `vite build` prerenders the shell into
  // dist/client/index.html and emits a purely static dist/client.
  plugins: [
    // `extensions` makes @solidjs/vite-plugin also compile the `?pick=` route
    // modules the fileRoutes plugin emits (their ids end in a query string).
    solid({ start: true, extensions: ['.jsx', '.tsx'], diagnostics: true }), // add `ssr: true` for streaming SSR
    fileRoutes({ types: true }),
    // Scans source files for class names and generates their CSS into the
    // stylesheet that imports tailwindcss (src/App.css).
    tailwindcss(),
  ],
  server: {
    port: 3000,
    // Proxy the Julia API so the dev server is same-origin with it, exactly as it will be in
    // production when ExperimentTracking serves this bundle beside `api/v1` (decisions 10).
    // Without this the app only works if you remember `?api=...`, and a POST to an unproxied
    // path returns Vite's 404 HTML, which reads as "the server is down".
    // Point it elsewhere with DASHI_API=http://127.0.0.1:8090 pnpm dev
    proxy: Object.fromEntries(
      [
        '/get-acceptable-paths',
        '/load-files',
        '/get-card-widgets',
        '/get-card-ir',
        '/evaluate-pipeline',
        '/fetch-data',
        '/get-processed-data',
      ].map((route) => [
        route,
        { target: process.env.DASHI_API ?? 'http://127.0.0.1:8080', changeOrigin: true },
      ]),
    ),
  },
  test: {
    environment: 'jsdom',
    globals: false,
    setupFiles: ['./vitest-setup.ts'],
    // if you have few tests, try commenting this
    // out to improve performance:
    isolate: false,
  },
  build: {
    target: 'esnext',
    // Keep images as asset files instead of inlining them into the JS bundle.
    assetsInlineLimit: 0,
  },
});
