import { Link } from 'react-router-dom';
import { useEffect } from 'react';
import { useChat } from '../hooks/useChat';
import { useConfig } from '../context/ConfigContext';
import { ChatWindow } from '../components/ChatWindow';
import { InputBar } from '../components/InputBar';
import { SuggestionChips } from '../components/SuggestionChips';
import styles from './ChatPage.module.css';

export function ChatPage() {
  const { messages, isStreaming, suggestions, isSuggestionsLoading, model, suggestionsModel, sendMessage, clearHistory } = useChat();
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
          {(model || suggestionsModel) && (
            <dl className={styles.modelList}>
              {model && (
                <div className={styles.modelRow}>
                  <dt className={styles.modelLabel}>chat</dt>
                  <dd className={styles.modelValue} title={`Chat reply model: ${model}`}>{model}</dd>
                </div>
              )}
              {suggestionsModel && (
                <div className={styles.modelRow}>
                  <dt className={styles.modelLabel}>suggestions</dt>
                  <dd className={styles.modelValue} title={`Suggestions model: ${suggestionsModel}`}>{suggestionsModel}</dd>
                </div>
              )}
            </dl>
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

      <SuggestionChips
        suggestions={suggestions}
        isLoading={isSuggestionsLoading}
        onSelect={sendMessage}
      />

      <InputBar onSend={sendMessage} isStreaming={isStreaming} />
    </div>
  );
}
