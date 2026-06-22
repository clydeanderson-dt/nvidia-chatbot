import styles from './SuggestionChips.module.css';

export function SuggestionChips({ suggestions, isLoading = false, onSelect }) {
  if (isLoading) {
    return (
      <div className={styles.loading}>
        <span className={styles.spinner} aria-hidden="true" />
        <span className={styles.loadingText}>Generating suggestions...</span>
      </div>
    );
  }

  if (!suggestions || suggestions.length === 0) return null;

  return (
    <div className={styles.chips}>
      {suggestions.map((suggestion, index) => (
        <button
          key={index}
          className={styles.chip}
          onClick={() => onSelect(suggestion)}
        >
          {suggestion}
        </button>
      ))}
    </div>
  );
}
