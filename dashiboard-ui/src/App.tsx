import { Title } from '@solidjs/meta';
import { createEffect, Loading, onSettled } from 'solid-js';
import { paths, Router } from './router';
import { ThemeToggle } from './components/ThemeToggle';
import { applyTheme, initialMode, setThemeMode, themeMode } from './theme';
import './App.css';

// The app root: the router and the site-wide layout live here. Pages are
// the modules under src/routes.
export default function App() {
  // Read the requested mode once, on the client. `onSettled` rather than module scope because
  // this renders on the server too, where there is no `window` — and once rather than reactively
  // because C5 says the URL is read at load and never again: a host changing the mode sends a
  // message, it does not re-navigate the frame, which would remount the app and lose its state.
  onSettled(() => {
    const prefersDark = window.matchMedia?.("(prefers-color-scheme: dark)").matches ?? false;
    setThemeMode(initialMode(window.location.search, prefersDark));
  });

  // Effects do not run during SSR, so the document is always there by the time this fires.
  createEffect(themeMode, (mode) => applyTheme(mode, document.documentElement));

  return (
    <Router>
      {(props) => (
        <>
          <Title>Solid App</Title>
          <nav class="flex items-center justify-between bg-primary p-3">
            <a
              class="mx-0.5 inline-block rounded-lg px-3 py-1.5 font-semibold text-primary-foreground/80 no-underline transition-colors hover:bg-primary-foreground/10 hover:text-primary-foreground focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring"
              href={paths()}
            >
              Home
            </a>
            <ThemeToggle />
          </nav>
          <Loading fallback={<main class="px-4 py-6">Loading…</main>}>
            {props.children}
          </Loading>
        </>
      )}
    </Router>
  );
}
