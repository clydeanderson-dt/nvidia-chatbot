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
    rate_limit_after_n: 5,
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

  const [chaosPresets, setChaosPresets] = useState([]);
  const [loading, setLoading] = useState(true);

  // Fetch configs on mount
  useEffect(() => {
    async function fetchConfigs() {
      try {
        const [chaosRes, presetsRes] = await Promise.all([
          fetch('/api/chaos'),
          fetch('/api/chaos/presets'),
        ]);
        if (chaosRes.ok) setChaosConfig(await chaosRes.json());
        if (presetsRes.ok) {
          const data = await presetsRes.json();
          setChaosPresets(data.presets || []);
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
          const res = await fetch('/api/chaos');
          if (res.ok) {
            setChaosConfig(await res.json());
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

  const updateChaosConfig = useCallback(async (updates) => {
    try {
      const res = await fetch('/api/chaos', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updates),
      });
      if (res.ok) {
        const data = await res.json();
        setChaosConfig(data);
        return data;
      }
    } catch (err) {
      console.error('Failed to update chaos config:', err);
    }
    return null;
  }, []);

  const resetChaosConfig = useCallback(async () => {
    try {
      const res = await fetch('/api/chaos/reset', { method: 'POST' });
      if (res.ok) {
        const data = await res.json();
        setChaosConfig(data);
        return data;
      }
    } catch (err) {
      console.error('Failed to reset chaos config:', err);
    }
    return null;
  }, []);

  const applyPreset = useCallback(async (presetName) => {
    try {
      const res = await fetch(`/api/chaos/preset/${presetName}`, { method: 'POST' });
      if (res.ok) {
        const data = await res.json();
        setChaosConfig(data);
        return data;
      }
    } catch (err) {
      console.error('Failed to apply preset:', err);
    }
    return null;
  }, []);

  const refreshChaosConfig = useCallback(async () => {
    try {
      const res = await fetch('/api/chaos');
      if (res.ok) {
        setChaosConfig(await res.json());
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
        chaosPresets,
        loading,
        isAnyChaosActive,
        updateAppConfig,
        updateChaosConfig,
        resetChaosConfig,
        applyPreset,
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
