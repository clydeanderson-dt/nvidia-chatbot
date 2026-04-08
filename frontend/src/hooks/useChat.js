import { useState, useCallback, useEffect, useRef } from 'react';

/**
 * Core chat hook.
 *
 * Returns:
 *   messages       – array of { role: 'user'|'assistant', content: string }
 *   isStreaming     – true while a response is being received
 *   systemPrompt    – current system prompt string
 *   setSystemPrompt – update the system prompt (takes effect on the next send)
 *   sendMessage     – async fn(text: string)
 *   clearHistory    – clears UI state and server-side session memory
 */
function generateSessionId() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  // Fallback for non-secure contexts (plain HTTP).
  return '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, (c) =>
    (+c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (+c / 4)))).toString(16),
  );
}

export function useChat() {
  // Stable session ID for this browser tab (persists until page reload).
  const sessionId = useRef(generateSessionId()).current;

  const [messages, setMessages] = useState([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const [suggestions, setSuggestions] = useState([]);
  const [systemPrompt, setSystemPrompt] = useState(
    'You are a helpful, knowledgeable, and friendly AI assistant.',
  );
  const [llmProvider, setLlmProvider] = useState('nim_api');

  const fetchStarterSuggestions = useCallback(async () => {
    try {
      const response = await fetch('/api/chat/starters', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ system_prompt: systemPrompt, provider: llmProvider }),
      });
      if (!response.ok) return;
      const data = await response.json();
      setSuggestions(data.suggestions ?? []);
    } catch {
      // Starter suggestions are best-effort — never break the UI.
    }
  }, [systemPrompt, llmProvider]);

  // Fetch starter suggestions on mount and when the system prompt changes,
  // but only while no conversation is in progress.
  useEffect(() => {
    if (messages.length === 0) {
      fetchStarterSuggestions();
    }
  }, [systemPrompt]); // eslint-disable-line react-hooks/exhaustive-deps
  // ^ intentionally omits fetchStarterSuggestions and messages —
  //   this fires only on systemPrompt changes; clearHistory() handles the post-clear fetch.

  const sendMessage = useCallback(
    async (text) => {
      if (!text.trim() || isStreaming) return;

      // Clear stale suggestions immediately so the old chips disappear.
      setSuggestions([]);

      // Add the user message immediately.
      const userMsg = { role: 'user', content: text.trim() };
      setMessages((prev) => [...prev, userMsg]);

      // Add a placeholder assistant message that we'll fill in as tokens arrive.
      setMessages((prev) => [...prev, { role: 'assistant', content: '' }]);
      setIsStreaming(true);

      try {
        const response = await fetch('/api/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            session_id: sessionId,
            message: text.trim(),
            system_prompt: systemPrompt,
            provider: llmProvider,
          }),
        });

        if (!response.ok) {
          throw new Error(`Server error: ${response.status}`);
        }

        const data = await response.json();
        setMessages((prev) => {
          const updated = [...prev];
          updated[updated.length - 1] = { role: 'assistant', content: data.reply };
          return updated;
        });
        setSuggestions(data.suggestions ?? []);
      } catch (err) {
        console.error('Chat request failed:', err);
        setMessages((prev) => {
          const updated = [...prev];
          const last = updated[updated.length - 1];
          updated[updated.length - 1] = {
            ...last,
            content: 'Sorry, something went wrong. Please try again.',
          };
          return updated;
        });
        setSuggestions([]);
      } finally {
        setIsStreaming(false);
      }
    },
    [isStreaming, sessionId, systemPrompt, llmProvider],
  );

  const clearHistory = useCallback(async () => {
    try {
      await fetch(`/api/chat/${sessionId}`, { method: 'DELETE' });
    } catch (err) {
      console.error('Failed to clear server session:', err);
    }
    setMessages([]);
    setSuggestions([]);
    fetchStarterSuggestions();
  }, [sessionId, fetchStarterSuggestions]);

  return { messages, isStreaming, suggestions, systemPrompt, setSystemPrompt, llmProvider, setLlmProvider, sendMessage, clearHistory };
}
