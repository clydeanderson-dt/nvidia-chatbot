import { Link } from 'react-router-dom';
import { useEffect } from 'react';
import { useChat } from '../hooks/useChat';
import { useConfig } from '../context/ConfigContext';
import { ChatWindow } from '../components/ChatWindow';
import { InputBar } from '../components/InputBar';
import { SuggestionChips } from '../components/SuggestionChips';
import styles from './ChatPage.module.css';

export function ChatPage() {
  const { messages, isStreaming, suggestions, model, sendMessage, clearHistory } = useChat();
  const { isAnyChaosActive, refreshChaosConfig } = useConfig();

  // Refresh chaos config when page loads
  useEffect(() => {
    refreshChaosConfig();
  }, [refreshChaosConfig]);

  return (
    <div className={styles.shell}>
      <header className={styles.header}>
        <div className={styles.titleGroup}>
          <h1 className={styles.title}>AI Chatbot</h1>
          {model && (
            <span className={styles.model} title="Current LLM model">
              {model}
            </span>
          )}
        </div>
        <div className={styles.headerActions}>
          <Link to="/config" className={styles.configLink}>
            Settings
          </Link>
          <button className={styles.clearBtn} onClick={clearHistory} title="Clear conversation">
            Clear
          </button>
        </div>
      </header>

      {isAnyChaosActive && (
        <div className={styles.chaosBanner}>
          ⚠️ Chaos mode active — some requests may fail or be delayed.{' '}
          <Link to="/config" className={styles.chaosLink}>Configure</Link>
        </div>
      )}

      <ChatWindow messages={messages} isStreaming={isStreaming} />

      <SuggestionChips suggestions={suggestions} onSelect={sendMessage} />

      <InputBar onSend={sendMessage} isStreaming={isStreaming} />
    </div>
  );
}
