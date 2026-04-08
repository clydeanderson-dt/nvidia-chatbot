import { useChat } from './hooks/useChat';
import { ChatWindow } from './components/ChatWindow';
import { InputBar } from './components/InputBar';
import { LLMProviderPanel } from './components/LLMProviderPanel';
import { SystemPromptPanel } from './components/SystemPromptPanel';
import { SuggestionChips } from './components/SuggestionChips';
import styles from './App.module.css';

function App() {
  const { messages, isStreaming, suggestions, systemPrompt, setSystemPrompt, llmProvider, setLlmProvider, sendMessage, clearHistory } =
    useChat();

  return (
    <div className={styles.shell}>
      <header className={styles.header}>
        <h1 className={styles.title}>AI Chatbot</h1>
        <button className={styles.clearBtn} onClick={clearHistory} title="Clear conversation">
          Clear
        </button>
      </header>

      <SystemPromptPanel systemPrompt={systemPrompt} onChange={setSystemPrompt} locked={messages.length > 0} />

      <LLMProviderPanel provider={llmProvider} onChange={setLlmProvider} locked={messages.length > 0} />

      <ChatWindow messages={messages} isStreaming={isStreaming} />

      <SuggestionChips suggestions={suggestions} onSelect={sendMessage} />

      <InputBar onSend={sendMessage} isStreaming={isStreaming} />
    </div>
  );
}

export default App;
