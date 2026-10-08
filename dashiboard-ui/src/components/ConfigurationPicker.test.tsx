import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { ConfigurationPicker } from './ConfigurationPicker';

afterEach(cleanup);

const TEXTS = { dense: 'name = "basic"\n[loss]\nname = "mse"\n', fuzzy: 'name = "fuzzy"\n' };
const mount = (over: Partial<Parameters<typeof ConfigurationPicker>[0]> = {}) => {
  const onChoose = vi.fn(); const onRefresh = vi.fn();
  const view = render(() => (
    <ConfigurationPicker
      id="n-model-variant" kind="model" options={['dense', 'fuzzy']} chosen="dense"
      text={(name) => TEXTS[name as keyof typeof TEXTS] ?? null}
      onChoose={onChoose} onRefresh={onRefresh} {...over}
    />
  ));
  return { ...view, onChoose, onRefresh };
};

describe('ConfigurationPicker', () => {
  it('offers the names, and shows the chosen file folded under them', () => {
    const { container } = mount();
    const select = container.querySelector('#n-model-variant') as HTMLSelectElement;
    expect([...select.options].map((o) => o.value)).toEqual(['dense', 'fuzzy']);
    const details = container.querySelector('details[data-configuration]') as HTMLDetailsElement;
    expect(details.open).toBe(false);
    expect(details.querySelector('pre')!.textContent).toBe(TEXTS.dense);
    expect(details.querySelector('summary')!.textContent).toMatch(/dense\.toml/);
  });

  // A configuration may be long and wide. It stays inside the card: the picker may shrink with
  // its row, and the file scrolls within a bounded box rather than push the form out.
  it('keeps the file inside its row, scrolling when it is larger', () => {
    const { container } = mount();
    const root = container.firstElementChild as HTMLElement;
    expect(root.className).toMatch(/\bmin-w-0\b/);
    expect(root.className).toMatch(/\bflex-1\b/);
    const details = container.querySelector('details[data-configuration]') as HTMLElement;
    expect(details.className).toMatch(/\bmin-w-0\b/);
    const pre = details.querySelector('pre')!;
    expect(pre.className).toMatch(/\boverflow-auto\b/);
    expect(pre.className).toMatch(/\bmax-h-\S+/);
  });

  it('hands over the name chosen, and asks again on the refresh button', async () => {
    const { container, onChoose, onRefresh } = mount();
    const select = container.querySelector('#n-model-variant') as HTMLSelectElement;
    select.value = 'fuzzy'; fireEvent.change(select); await flush();
    expect(onChoose).toHaveBeenCalledWith('fuzzy');
    fireEvent.click(container.querySelector('button[aria-label="refresh the model list"]')!);
    expect(onRefresh).toHaveBeenCalled();
  });

  // One configuration is not a question, but what it holds is still worth a look.
  it('draws no chooser for a lone name, and still shows its file', () => {
    const { container } = mount({ options: ['dense'] });
    expect(container.querySelector('select')).toBeNull();
    expect(container.querySelector('details[data-configuration] pre')!.textContent).toBe(TEXTS.dense);
    expect(container.textContent).toMatch(/dense/);
  });

  it('says so while the file is not known yet, and marks a name that is not on offer', () => {
    const { container } = mount({ text: () => null });
    expect(container.querySelector('details[data-configuration]')).toBeNull();
    cleanup();
    const foreign = mount({ chosen: 'gone' });
    const select = foreign.container.querySelector('select') as HTMLSelectElement;
    expect(select.className).toMatch(/border-warning/);
    expect(select.selectedOptions[0].textContent).toMatch(/gone/);
  });

  // A loaded card may hold a model with no name: one name on offer does not make it chosen.
  it('asks for the lone name when the document names none', async () => {
    const { container, onChoose } = mount({ options: ['dense'], chosen: undefined });
    const select = container.querySelector('select') as HTMLSelectElement;
    expect(select.className).toMatch(/border-warning/);
    select.value = 'dense'; fireEvent.change(select); await flush();
    expect(onChoose).toHaveBeenCalledWith('dense');
  });

  it('asks when nothing is chosen and there is a choice', () => {
    const { container } = mount({ chosen: undefined });
    const select = container.querySelector('select') as HTMLSelectElement;
    expect(select.className).toMatch(/border-warning/);
    expect(select.options[0].textContent).toMatch(/choose/);
  });
});
