import { useState, useCallback, useEffect, useRef } from 'react';
import { useConfig } from '../context/ConfigContext';

/**
 * Core chat hook.
 *
 * Returns:
 *   messages       – array of { role: 'user'|'assistant', content: string }
 *   isStreaming     – true while a response is being received
 *   sendMessage     – async fn(text: string)
 *   clearHistory    – clears UI state and server-side session memory
 *   suggestions     – array of follow-up question strings
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

  // Get config from context (server-side configuration)
  const { appConfig, refreshChaosConfig } = useConfig();

  const fetchStarterSuggestions = useCallback(async () => {
    try {
      // Server uses its own config if we don't override
      const response = await fetch('/api/chat/starters', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
body: JSON.stringify({
        system_prompt: appConfig.system_prompt,
        provider: appConfig.provider,
        session_id: sessionId,
      }),
    });
    if (!response.ok) return;
    const data = await response.json();
    setSuggestions(data.suggestions ?? []);
  } catch {
    // Starter suggestions are best-effort — never break the UI.
  }
}, [appConfig.system_prompt, appConfig.provider, sessionId]);

  // Fetch starter suggestions on mount and when app config changes,
  // but only while no conversation is in progress.
  useEffect(() => {
    if (messages.length === 0) {
      fetchStarterSuggestions();
    }
  }, [appConfig.system_prompt]); // eslint-disable-line react-hooks/exhaustive-deps

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
        // Server uses its own config — we just send the session/message
        const response = await fetch('/api/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            session_id: sessionId,
            message: text.trim(),
            system_prompt: appConfig.system_prompt,
            provider: appConfig.provider,
          }),
        });

        if (!response.ok) {
          // Try to parse error detail from response
          let errorMsg = 'Sorry, something went wrong. Please try again.';
          try {
            const errorData = await response.json();
            if (errorData.detail) {
              errorMsg = errorData.detail;
            }
          } catch {
            // If parsing fails, use default message
          }
          throw new Error(errorMsg);
        }

        const data = await response.json();
        setMessages((prev) => {
          const updated = [...prev];
          updated[updated.length - 1] = { role: 'assistant', content: data.reply };
          return updated;
        });
        setSuggestions(data.suggestions ?? []);
        // Refresh chaos config after receiving response
        refreshChaosConfig();
      } catch (err) {
        console.error('Chat request failed:', err);
        setMessages((prev) => {
          const updated = [...prev];
          const last = updated[updated.length - 1];
          updated[updated.length - 1] = {
            ...last,
            content: err.message || 'Sorry, something went wrong. Please try again.',
          };
          return updated;
        });
        setSuggestions([]);
      } finally {
        setIsStreaming(false);
      }
    },
    [isStreaming, sessionId, refreshChaosConfig, appConfig.system_prompt, appConfig.provider],
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
    // Refresh chaos config after clearing
    refreshChaosConfig();
  }, [sessionId, fetchStarterSuggestions, refreshChaosConfig]);

  return { messages, isStreaming, suggestions, sendMessage, clearHistory };
}
