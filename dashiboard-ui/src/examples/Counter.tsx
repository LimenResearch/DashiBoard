import { createSignal } from 'solid-js';

export default function Counter() {
  const [count, setCount] = createSignal(0);
  return (
    <button
      class="cursor-pointer rounded-sm border border-border inline-flex h-control-xs items-center px-2.5 text-control-xs hover:bg-muted"
      onClick={() => setCount(count() + 1)}
      type="button"
    >
      Clicks: {count()}
    </button>
  );
}
