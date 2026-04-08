import { useState } from 'react';
import styles from './SystemPromptPanel.module.css';

export function SystemPromptPanel({ systemPrompt, onChange, locked = false }) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState(systemPrompt);

  function handleSet() {
    if (draft.trim() === systemPrompt.trim()) return;
    onChange(draft);
  }

  const isDirty = draft.trim() !== systemPrompt.trim();

  return (
    <div className={styles.panel}>
      <button
        className={styles.toggle}
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
      >
        <span className={styles.icon}>{open ? '▾' : '▸'}</span>
        System Prompt
      </button>

      {open && (
        <div className={styles.body}>
          <textarea
            className={`${styles.textarea}${locked ? ` ${styles.locked}` : ''}`}
            rows={4}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Describe the assistant's persona and behavior…"
            aria-label="System prompt"
            readOnly={locked}
          />
          {locked ? (
            <p className={styles.hint}>Clear the conversation to change the system prompt.</p>
          ) : (
            <div className={styles.footer}>
              <p className={styles.hint}>Click Set to apply and refresh suggestions.</p>
              <button
                className={styles.setBtn}
                onClick={handleSet}
                disabled={!isDirty}
              >
                Set
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
