import { createContext, useContext, useState, useCallback, useEffect } from 'react';

const ConfigContext = createContext(null);

export function ConfigProvider({ children }) {
  const [appConfig, setAppConfig] = useState(() => ({
    system_prompt: localStorage.getItem('chatbot_system_prompt') ?? 'You are a helpful, knowledgeable, and friendly AI assistant.',
    provider: localStorage.getItem('chatbot_provider') ?? 'nim_api',
  }));

  const [chaosConfig, setChaosConfig] = useState({
    // LLM failures
    llm_delay_ms: 0,
    llm_error_rate: 0.0,
    rate_limit_enabled: false,
    malformed_response_rate: 0.0,
    empty_response_rate: 0.0,
    hallucination_enabled: false,
    token_limit_error_enabled: false,
    // Latency
    fixed_delay_ms: 0,
    random_delay_min_ms: 0,
    random_delay_max_ms: 0,
    spike_delay_ms: 0,
    spike_probability: 0.0,
    // HTTP errors
    http_500_rate: 0.0,
    http_503_rate: 0.0,
    session_error_rate: 0.0,
  });

  const [chaosVariation, setChaosVariation] = useState('unknown');
  const [loading, setLoading] = useState(true);

  // Fetch configs on mount
  useEffect(() => {
    async function fetchConfigs() {
      try {
        const statusRes = await fetch('/api/chaos/status');
        if (statusRes.ok) {
          const data = await statusRes.json();
          setChaosConfig(data.config);
          setChaosVariation(data.preset ?? 'unknown');
        }
      } catch (err) {
        console.error('Failed to fetch configs:', err);
      } finally {
        setLoading(false);
      }
    }
    fetchConfigs();
  }, []);

  // Refetch chaos config when tab becomes visible
  useEffect(() => {
    async function handleVisibilityChange() {
      if (!document.hidden) {
        try {
          const res = await fetch('/api/chaos/status');
          if (res.ok) {
            const data = await res.json();
            setChaosConfig(data.config);
            setChaosVariation(data.preset ?? 'unknown');
          }
        } catch (err) {
          // Silent fail
        }
      }
    }

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
  }, []);

  const updateAppConfig = useCallback((updates) => {
    setAppConfig((prev) => {
      const next = { ...prev, ...updates };
      if ('system_prompt' in updates) localStorage.setItem('chatbot_system_prompt', next.system_prompt);
      if ('provider' in updates) localStorage.setItem('chatbot_provider', next.provider);
      return next;
    });
  }, []);

  const refreshChaosConfig = useCallback(async () => {
    try {
      const res = await fetch('/api/chaos/status');
      if (res.ok) {
        const data = await res.json();
        setChaosConfig(data.config);
        setChaosVariation(data.preset ?? 'unknown');
      }
    } catch (err) {
      // Silent fail
    }
  }, []);

  const isAnyChaosActive =
    chaosConfig.llm_delay_ms > 0 ||
    chaosConfig.llm_error_rate > 0 ||
    chaosConfig.rate_limit_enabled ||
    chaosConfig.malformed_response_rate > 0 ||
    chaosConfig.empty_response_rate > 0 ||
    chaosConfig.hallucination_enabled ||
    chaosConfig.token_limit_error_enabled ||
    chaosConfig.fixed_delay_ms > 0 ||
    chaosConfig.random_delay_max_ms > 0 ||
    chaosConfig.spike_delay_ms > 0 ||
    chaosConfig.http_500_rate > 0 ||
    chaosConfig.http_503_rate > 0 ||
    chaosConfig.session_error_rate > 0;

  return (
    <ConfigContext.Provider
      value={{
        appConfig,
        chaosConfig,
        chaosVariation,
        loading,
        isAnyChaosActive,
        updateAppConfig,
        refreshChaosConfig,
      }}
    >
      {children}
    </ConfigContext.Provider>
  );
}

export function useConfig() {
  const ctx = useContext(ConfigContext);
  if (!ctx) {
    throw new Error('useConfig must be used within a ConfigProvider');
  }
  return ctx;
}
