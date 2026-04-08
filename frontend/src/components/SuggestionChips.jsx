import styles from './SuggestionChips.module.css';

export function SuggestionChips({ suggestions, onSelect }) {
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
