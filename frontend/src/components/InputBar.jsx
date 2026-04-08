import { useState } from 'react';
import styles from './InputBar.module.css';

/**
 * Text input + send button at the bottom of the chat.
 * @param {{ onSend: (text: string) => void, isStreaming: boolean }} props
 */
export function InputBar({ onSend, isStreaming }) {
  const [text, setText] = useState('');

  function handleSubmit(e) {
    e.preventDefault();
    if (!text.trim() || isStreaming) return;
    onSend(text);
    setText('');
  }

  function handleKeyDown(e) {
    // Send on Enter; allow Shift+Enter for a newline.
    if (e.key === 'Enter' && !e.shiftKey) {
      handleSubmit(e);
    }
  }

  return (
    <form className={styles.bar} onSubmit={handleSubmit}>
      <textarea
        className={styles.input}
        rows={1}
        placeholder="Type a message… (Enter to send)"
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={handleKeyDown}
        disabled={isStreaming}
        aria-label="Chat message input"
      />
      <button
        className={styles.send}
        type="submit"
        disabled={isStreaming || !text.trim()}
        aria-label="Send message"
      >
        {isStreaming ? '…' : 'Send'}
      </button>
    </form>
  );
}
