import { useEffect, useRef } from 'react';
import { MessageBubble } from './MessageBubble';
import styles from './ChatWindow.module.css';

/**
 * Scrollable list of messages.
 * @param {{ messages: Array<{role,content}>, isStreaming: boolean }} props
 */
export function ChatWindow({ messages, isStreaming }) {
  const bottomRef = useRef(null);

  // Auto-scroll to the bottom whenever messages update.
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  return (
    <div className={styles.window}>
      {messages.length === 0 ? (
        <p className={styles.empty}>Send a message to start chatting.</p>
      ) : (
        messages.map((msg, idx) => {
          const isLastAssistant =
            isStreaming && idx === messages.length - 1 && msg.role === 'assistant';
          return (
            <MessageBubble
              key={idx}
              role={msg.role}
              content={msg.content}
              isStreaming={isLastAssistant}
            />
          );
        })
      )}
      <div ref={bottomRef} />
    </div>
  );
}
