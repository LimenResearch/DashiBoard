import { defineConfig } from 'vite';
import solidPlugin from 'vite-plugin-solid';
// FIXME: is there an established `fs` plugin for vite?
import fs from "vite-plugin-fs";

// import devtools from 'solid-devtools/vite';

export default defineConfig({
  plugins: [
    /* 
    Uncomment the following line to enable solid-devtools.
    For more info see https://github.com/thetarnav/solid-devtools/tree/main/packages/extension#readme
    */
    // devtools(),
    solidPlugin(),
    fs(),
  ],
  server: {
    port: 3000,
  },
  build: {
    target: 'esnext',
  },
});
