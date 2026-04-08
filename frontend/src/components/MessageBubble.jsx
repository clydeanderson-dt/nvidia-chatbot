import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import styles from './MessageBubble.module.css';

/**
 * Renders a single chat message.
 * @param {{ role: 'user'|'assistant', content: string, isStreaming: boolean }} props
 */
export function MessageBubble({ role, content, isStreaming }) {
  const isUser = role === 'user';

  return (
    <div className={`${styles.wrapper} ${isUser ? styles.userWrapper : styles.assistantWrapper}`}>
      <div className={`${styles.bubble} ${isUser ? styles.user : styles.assistant}`}>
        <span className={styles.label}>{isUser ? 'You' : 'Assistant'}</span>
        {isStreaming && !isUser && !content ? (
          <div className={styles.content}>
            <span className={styles.typingDots} aria-label="Thinking">
              <span /><span /><span />
            </span>
          </div>
        ) : isUser ? (
          <p className={styles.content}>{content}</p>
        ) : (
          <div className={styles.markdownContent}>
            <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
          </div>
        )}
      </div>
    </div>
  );
}
