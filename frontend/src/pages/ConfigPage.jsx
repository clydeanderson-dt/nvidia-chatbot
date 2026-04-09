import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useConfig } from '../context/ConfigContext';
import styles from './ConfigPage.module.css';

const PROVIDERS = [
  { value: 'nim_api', label: 'NVIDIA NIM API' },
  { value: 'self_hosted', label: 'Self-Hosted NIM' },
];

// Preset definitions matching backend chaos.py
const PRESETS = {
  healthy: {
    description: 'All chaos disabled',
    config: {
      llm_delay_ms: 0,
      llm_error_rate: 0.0,
      rate_limit_enabled: false,
      malformed_response_rate: 0.0,
      empty_response_rate: 0.0,
      hallucination_enabled: false,
      token_limit_error_enabled: false,
      fixed_delay_ms: 0,
      random_delay_min_ms: 0,
      random_delay_max_ms: 0,
      spike_delay_ms: 0,
      spike_probability: 0.0,
      http_500_rate: 0.0,
      http_503_rate: 0.0,
      session_error_rate: 0.0,
    },
  },
  slow_llm: {
    description: '5 second LLM delay',
    config: {
      llm_delay_ms: 5000,
    },
  },
  flaky_network: {
    description: '30% HTTP 500 errors + random delays',
    config: {
      http_500_rate: 0.3,
      random_delay_min_ms: 500,
      random_delay_max_ms: 2000,
    },
  },
  rate_limited: {
    description: '429 after 3 requests',
    config: {
      rate_limit_enabled: true,
      rate_limit_after_n: 3,
    },
  },
  degraded: {
    description: '20% LLM errors, 10% empty responses, 1s delay',
    config: {
      llm_error_rate: 0.2,
      empty_response_rate: 0.1,
      fixed_delay_ms: 1000,
    },
  },
};

/**
 * Determine which preset (if any) matches the current chaos config.
 * A preset matches if all its defined fields match the current config.
 */
function getActivePreset(chaosConfig) {
  for (const [presetName, preset] of Object.entries(PRESETS)) {
    const presetConfig = preset.config;
    const matches = Object.entries(presetConfig).every(
      ([key, value]) => chaosConfig[key] === value
    );
    if (matches) {
      return presetName;
    }
  }
  return null; // No preset matches (manually configured)
}

export function ConfigPage() {
  const {
    appConfig,
    chaosConfig,
    chaosPresets,
    loading,
    isAnyChaosActive,
    updateAppConfig,
    updateChaosConfig,
    applyPreset,
    refreshChaosConfig,
  } = useConfig();

  // Refresh chaos config when page loads
  useEffect(() => {
    refreshChaosConfig();
  }, [refreshChaosConfig]);

  // Local draft state for form fields
  const [systemPrompt, setSystemPrompt] = useState(appConfig.system_prompt);
  const [provider, setProvider] = useState(appConfig.provider);

  // Sync draft state when server config loads
  useEffect(() => {
    setSystemPrompt(appConfig.system_prompt);
    setProvider(appConfig.provider);
  }, [appConfig]);

  const handleSaveAppConfig = async () => {
    await updateAppConfig({ system_prompt: systemPrompt, provider });
  };

  const isAppConfigDirty =
    systemPrompt !== appConfig.system_prompt || provider !== appConfig.provider;

  const activePreset = getActivePreset(chaosConfig);

  if (loading) {
    return (
      <div className={styles.container}>
        <div className={styles.loading}>Loading configuration...</div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <Link to="/" className={styles.backLink}>← Back to Chat</Link>
        <h1 className={styles.title}>Configuration</h1>
      </header>

      {isAnyChaosActive && (
        <div className={styles.chaosBanner}>
          ⚠️ Chaos mode is active — failures may be injected into requests.
        </div>
      )}

      {/* App Settings Section */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>App Settings</h2>

        <div className={styles.field}>
          <label className={styles.label}>System Prompt</label>
          <textarea
            className={styles.textarea}
            rows={4}
            value={systemPrompt}
            onChange={(e) => setSystemPrompt(e.target.value)}
            placeholder="Describe the assistant's persona and behavior…"
          />
          <p className={styles.hint}>Defines the AI assistant's personality and behavior.</p>
        </div>

        <div className={styles.field}>
          <label className={styles.label}>LLM Provider</label>
          <div className={styles.radioGroup}>
            {PROVIDERS.map(({ value, label }) => (
              <label key={value} className={styles.radioLabel}>
                <input
                  type="radio"
                  name="provider"
                  value={value}
                  checked={provider === value}
                  onChange={() => setProvider(value)}
                />
                {label}
              </label>
            ))}
          </div>
          <p className={styles.hint}>Choose which LLM backend serves requests.</p>
        </div>

        <button
          className={styles.saveBtn}
          onClick={handleSaveAppConfig}
          disabled={!isAppConfigDirty}
        >
          Save App Settings
        </button>
      </section>

      {/* Chaos Presets Section */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>
          Chaos Presets
          {isAnyChaosActive && <span className={styles.activeTag}>Active</span>}
        </h2>
        <p className={styles.sectionHint}>Quick profiles for common failure scenarios.</p>

        <div className={styles.presetGrid}>
          {chaosPresets.map((preset) => {
            const isActive = preset === activePreset;
            const isHealthy = preset === 'healthy';
            return (
              <button
                key={preset}
                className={`${
                  styles.presetBtn
                } ${
                  isActive && isHealthy ? styles.presetHealthy : ''
                } ${
                  isActive && !isHealthy ? styles.presetActive : ''
                }`}
                onClick={() => applyPreset(preset)}
              >
                <span className={styles.presetName}>
                  {preset.replace(/_/g, ' ')}
                  {isActive && <span className={styles.activeIndicator}> ✓</span>}
                </span>
                <span className={styles.presetDesc}>{PRESETS[preset]?.description || ''}</span>
              </button>
            );
          })}
        </div>
      </section>

      {/* LLM Failures Section */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>LLM Failures</h2>

        <div className={styles.field}>
          <label className={styles.label}>
            LLM Delay: {chaosConfig.llm_delay_ms}ms
          </label>
          <input
            type="range"
            min="0"
            max="10000"
            step="500"
            value={chaosConfig.llm_delay_ms}
            onChange={(e) => updateChaosConfig({ llm_delay_ms: parseInt(e.target.value) })}
            className={styles.slider}
          />
        </div>

        <div className={styles.field}>
          <label className={styles.label}>
            LLM Error Rate: {(chaosConfig.llm_error_rate * 100).toFixed(0)}%
          </label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={chaosConfig.llm_error_rate}
            onChange={(e) => updateChaosConfig({ llm_error_rate: parseFloat(e.target.value) })}
            className={styles.slider}
          />
        </div>

        <div className={styles.field}>
          <label className={styles.label}>
            Empty Response Rate: {(chaosConfig.empty_response_rate * 100).toFixed(0)}%
          </label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={chaosConfig.empty_response_rate}
            onChange={(e) => updateChaosConfig({ empty_response_rate: parseFloat(e.target.value) })}
            className={styles.slider}
          />
        </div>

        <div className={styles.checkboxField}>
          <label className={styles.checkboxLabel}>
            <input
              type="checkbox"
              checked={chaosConfig.rate_limit_enabled}
              onChange={(e) => updateChaosConfig({ rate_limit_enabled: e.target.checked })}
            />
            Rate Limiting (429 after {chaosConfig.rate_limit_after_n} requests)
          </label>
        </div>

        <div className={styles.checkboxField}>
          <label className={styles.checkboxLabel}>
            <input
              type="checkbox"
              checked={chaosConfig.hallucination_enabled}
              onChange={(e) => updateChaosConfig({ hallucination_enabled: e.target.checked })}
            />
            Inject Hallucination Markers
          </label>
        </div>

        <div className={styles.checkboxField}>
          <label className={styles.checkboxLabel}>
            <input
              type="checkbox"
              checked={chaosConfig.token_limit_error_enabled}
              onChange={(e) => updateChaosConfig({ token_limit_error_enabled: e.target.checked })}
            />
            Token Limit Errors
          </label>
        </div>
      </section>

      {/* Latency Injection Section */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Latency Injection</h2>

        <div className={styles.field}>
          <label className={styles.label}>
            Fixed Delay: {chaosConfig.fixed_delay_ms}ms
          </label>
          <input
            type="range"
            min="0"
            max="5000"
            step="250"
            value={chaosConfig.fixed_delay_ms}
            onChange={(e) => updateChaosConfig({ fixed_delay_ms: parseInt(e.target.value) })}
            className={styles.slider}
          />
        </div>

        <div className={styles.field}>
          <label className={styles.label}>
            Random Delay: {chaosConfig.random_delay_min_ms}ms – {chaosConfig.random_delay_max_ms}ms
          </label>
          <div className={styles.rangeGroup}>
            <input
              type="number"
              min="0"
              max="5000"
              step="100"
              value={chaosConfig.random_delay_min_ms}
              onChange={(e) => updateChaosConfig({ random_delay_min_ms: parseInt(e.target.value) || 0 })}
              className={styles.numberInput}
              placeholder="Min"
            />
            <span>to</span>
            <input
              type="number"
              min="0"
              max="10000"
              step="100"
              value={chaosConfig.random_delay_max_ms}
              onChange={(e) => updateChaosConfig({ random_delay_max_ms: parseInt(e.target.value) || 0 })}
              className={styles.numberInput}
              placeholder="Max"
            />
          </div>
        </div>

        <div className={styles.field}>
          <label className={styles.label}>
            Spike Delay: {chaosConfig.spike_delay_ms}ms @ {(chaosConfig.spike_probability * 100).toFixed(0)}% probability
          </label>
          <div className={styles.rangeGroup}>
            <input
              type="number"
              min="0"
              max="30000"
              step="1000"
              value={chaosConfig.spike_delay_ms}
              onChange={(e) => updateChaosConfig({ spike_delay_ms: parseInt(e.target.value) || 0 })}
              className={styles.numberInput}
              placeholder="Delay ms"
            />
            <input
              type="range"
              min="0"
              max="1"
              step="0.1"
              value={chaosConfig.spike_probability}
              onChange={(e) => updateChaosConfig({ spike_probability: parseFloat(e.target.value) })}
              className={styles.slider}
              style={{ flex: 1 }}
            />
          </div>
        </div>
      </section>

      {/* HTTP Error Injection Section */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>HTTP Error Injection</h2>

        <div className={styles.field}>
          <label className={styles.label}>
            HTTP 500 Rate: {(chaosConfig.http_500_rate * 100).toFixed(0)}%
          </label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={chaosConfig.http_500_rate}
            onChange={(e) => updateChaosConfig({ http_500_rate: parseFloat(e.target.value) })}
            className={styles.slider}
          />
        </div>

        <div className={styles.field}>
          <label className={styles.label}>
            HTTP 503 Rate: {(chaosConfig.http_503_rate * 100).toFixed(0)}%
          </label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={chaosConfig.http_503_rate}
            onChange={(e) => updateChaosConfig({ http_503_rate: parseFloat(e.target.value) })}
            className={styles.slider}
          />
        </div>

        <div className={styles.field}>
          <label className={styles.label}>
            Session Error Rate: {(chaosConfig.session_error_rate * 100).toFixed(0)}%
          </label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={chaosConfig.session_error_rate}
            onChange={(e) => updateChaosConfig({ session_error_rate: parseFloat(e.target.value) })}
            className={styles.slider}
          />
        </div>
      </section>

      {/* Current Config Summary */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Current Configuration</h2>
        <pre className={styles.configJson}>
          {JSON.stringify({ app: appConfig, chaos: chaosConfig }, null, 2)}
        </pre>
      </section>
    </div>
  );
}
