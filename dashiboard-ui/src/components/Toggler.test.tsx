import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import { Toggler } from './Toggler';

afterEach(cleanup);

describe('Toggler', () => {
  it('shows its children only once opened', async () => {
    const { container, getByText } = render(() => (
      <Toggler name="TEMP" modified={false} onReset={() => {}}>
        <p>the filter</p>
      </Toggler>
    ));
    expect(container.textContent).not.toContain('the filter');
    fireEvent.click(getByText('TEMP'));
    await flush();
    expect(container.textContent).toContain('the filter');
  });

  it('resets without opening or closing the panel', async () => {
    // The reset control used to be a span *inside* the toggle button — interactive content
    // nested in a button, which is invalid HTML and forced an isEqualNode check to work out
    // which of the two had been hit. As siblings, each does one thing.
    let reset = 0;
    const { container, getByLabelText } = render(() => (
      <Toggler name="TEMP" modified onReset={() => { reset += 1; }}>
        <p>the filter</p>
      </Toggler>
    ));
    fireEvent.click(getByLabelText(/reset TEMP/i));
    await flush();
    expect(reset).toBe(1);
    expect(container.textContent).not.toContain('the filter'); // still closed
  });

  it('offers no reset when nothing has been modified', () => {
    const { queryByLabelText } = render(() => (
      <Toggler name="TEMP" modified={false} onReset={() => {}}>
        <p>the filter</p>
      </Toggler>
    ));
    expect(queryByLabelText(/reset TEMP/i)).toBeNull();
  });
});
