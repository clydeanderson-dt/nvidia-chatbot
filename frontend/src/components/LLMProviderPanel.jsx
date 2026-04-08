import { useState } from 'react';
import styles from './LLMProviderPanel.module.css';

const PROVIDERS = [
  { value: 'nim_api', label: 'NVIDIA NIM API' },
  { value: 'self_hosted', label: 'Self-Hosted NIM' },
];

export function LLMProviderPanel({ provider, onChange, locked = false }) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState(provider);

  function handleApply() {
    if (draft === provider) return;
    onChange(draft);
  }

  const isDirty = draft !== provider;
  const currentLabel = PROVIDERS.find((p) => p.value === provider)?.label;

  return (
    <div className={styles.panel}>
      <button
        className={styles.toggle}
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
      >
        <span className={styles.icon}>{open ? '▾' : '▸'}</span>
        LLM Provider
        <span className={styles.current}>({currentLabel})</span>
      </button>

      {open && (
        <div className={styles.body}>
          <div className={`${styles.options}${locked ? ` ${styles.locked}` : ''}`}>
            {PROVIDERS.map(({ value, label }) => (
              <label key={value} className={styles.option}>
                <input
                  type="radio"
                  name="llm-provider"
                  value={value}
                  checked={draft === value}
                  onChange={() => !locked && setDraft(value)}
                  disabled={locked}
                />
                {label}
              </label>
            ))}
          </div>
          {locked ? (
            <p className={styles.hint}>Clear the conversation to change the LLM provider.</p>
          ) : (
            <div className={styles.footer}>
              <p className={styles.hint}>Choose which backend serves your requests.</p>
              <button
                className={styles.setBtn}
                onClick={handleApply}
                disabled={!isDirty}
              >
                Apply
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
