// One checkbox with its label.
//
// Extracted because the markup existed twice — the categorical filter and the variable picker —
// and the two had drifted apart in the way that matters: one bound `onClick`, the other
// `onChange`. They are not the same event, and which one you get was an accident of which file
// you were in.
//
// Both copies also carried `form-checkbox`, a `@tailwindcss/forms` class. The plugin is not
// installed, so it compiled to nothing and had always been decoration on a comment. `accent-*`
// tints the native control instead: no plugin, no custom-drawn box, and it follows the token, so
// a host palette repaints it along with everything else.

type CheckboxProps = {
  label: string;
  /** What callers read back off the DOM. Defaults to the label, which is usually the same thing. */
  value?: string;
  checked: boolean;
  /** Receives the new state rather than the event — every caller wanted the boolean. */
  onChange: (checked: boolean) => void;
  disabled?: boolean;
};

export function Checkbox(props: CheckboxProps) {
  return (
    <label class="inline-flex items-center gap-1.5 py-0.5 text-body">
      <input
        type="checkbox"
        class="accent-primary"
        value={props.value ?? props.label}
        checked={props.checked}
        disabled={props.disabled ?? false}
        onChange={(event) => props.onChange(event.currentTarget.checked)}
      />
      <span class="truncate" title={props.label}>
        {props.label}
      </span>
    </label>
  );
}
