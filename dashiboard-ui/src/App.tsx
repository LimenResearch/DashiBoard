import { Title } from '@solidjs/meta';
import { Loading } from 'solid-js';
import { paths, Router } from './router';
import './App.css';

// The app root: the router and the site-wide layout live here. Pages are
// the modules under src/routes.
export default function App() {
  return (
    <Router>
      {(props) => (
        <>
          <Title>Solid App</Title>
          <nav class="bg-primary p-3">
            <a
              class="mx-0.5 inline-block rounded-lg px-3 py-1.5 font-semibold text-primary-foreground/80 no-underline transition-colors hover:bg-primary-foreground/10 hover:text-primary-foreground focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring"
              href={paths()}
            >
              Home
            </a>
          </nav>
          <Loading fallback={<main class="px-4 py-6">Loading…</main>}>
            {props.children}
          </Loading>
        </>
      )}
    </Router>
  );
}
