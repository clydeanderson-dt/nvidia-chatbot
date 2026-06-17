import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useConfig } from '../context/ConfigContext';
import styles from './ConfigPage.module.css';

const PROVIDERS = [
  { value: 'nim_api', label: 'NVIDIA NIM API' },
  { value: 'self_hosted', label: 'Self-Hosted NIM' },
];

const DEVCYCLE_FEATURE_URL =
  'https://app.devcycle.com/o/org_SeGjnZQOwOYgQWYZ/p/nvidia-chatbot/features/chaos-preset';

function ReadOnlyRow({ label, value }) {
  return (
    <div className={styles.readonlyRow}>
      <span className={styles.readonlyLabel}>{label}</span>
      <span className={styles.readonlyValue}>{value}</span>
    </div>
  );
}

function pct(n) {
  return `${(n * 100).toFixed(0)}%`;
}

function ms(n) {
  return `${n}ms`;
}

function bool(b) {
  return b ? 'Enabled' : 'Disabled';
}

export function ConfigPage() {
  const {
    appConfig,
    chaosConfig,
    chaosVariation,
    loading,
    isAnyChaosActive,
    updateAppConfig,
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

  if (loading) {
    return (
      <div className={styles.container}>
        <div className={styles.loading}>Loading configuration...</div>
      </div>
    );
  }

  const variationLabel = chaosVariation && chaosVariation !== 'unknown' ? chaosVariation : '—';

  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <Link to="/" className={styles.backLink}>← Back to Chat</Link>
        <h1 className={styles.title}>Configuration</h1>
      </header>

      {isAnyChaosActive && (
        <div className={styles.chaosBanner}>
          ⚠️ Chaos mode is active — variation: <strong>{variationLabel}</strong> — failures may be injected into requests.
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

      {/* DevCycle banner */}
      <div className={styles.devcycleBanner}>
        <div className={styles.devcycleTitle}>🚩 Controlled by DevCycle Feature Flags</div>
        <div className={styles.devcycleBody}>
          Chaos scenarios are managed via DevCycle.{' '}
          <a href={DEVCYCLE_FEATURE_URL} target="_blank" rel="noopener noreferrer">
            View in DevCycle dashboard →
          </a>
        </div>
        <div className={styles.devcycleVariationRow}>
          <span className={styles.readonlyLabel}>Active variation</span>
          <span className={styles.variationBadge}>{variationLabel}</span>
        </div>
      </div>

      {/* LLM Failures Section (read-only) */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>LLM Failures</h2>
        <ReadOnlyRow label="LLM Delay" value={ms(chaosConfig.llm_delay_ms)} />
        <ReadOnlyRow label="LLM Error Rate" value={pct(chaosConfig.llm_error_rate)} />
        <ReadOnlyRow label="Empty Response Rate" value={pct(chaosConfig.empty_response_rate)} />
        <ReadOnlyRow label="Malformed Response Rate" value={pct(chaosConfig.malformed_response_rate)} />
        <ReadOnlyRow label="Rate Limiting" value={bool(chaosConfig.rate_limit_enabled)} />
        <ReadOnlyRow label="Hallucination Markers" value={bool(chaosConfig.hallucination_enabled)} />
        <ReadOnlyRow label="Token Limit Errors" value={bool(chaosConfig.token_limit_error_enabled)} />
      </section>

      {/* Latency Injection Section (read-only) */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Latency Injection</h2>
        <ReadOnlyRow label="Fixed Delay" value={ms(chaosConfig.fixed_delay_ms)} />
        <ReadOnlyRow
          label="Random Delay"
          value={`${ms(chaosConfig.random_delay_min_ms)} – ${ms(chaosConfig.random_delay_max_ms)}`}
        />
        <ReadOnlyRow
          label="Spike Delay"
          value={`${ms(chaosConfig.spike_delay_ms)} @ ${pct(chaosConfig.spike_probability)} probability`}
        />
      </section>

      {/* HTTP Error Injection Section (read-only) */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>HTTP Error Injection</h2>
        <ReadOnlyRow label="HTTP 500 Rate" value={pct(chaosConfig.http_500_rate)} />
        <ReadOnlyRow label="HTTP 503 Rate" value={pct(chaosConfig.http_503_rate)} />
        <ReadOnlyRow label="Session Error Rate" value={pct(chaosConfig.session_error_rate)} />
      </section>

      {/* Current Config Summary */}
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Current Configuration</h2>
        <pre className={styles.configJson}>
          {JSON.stringify({ app: appConfig, chaos: chaosConfig, variation: chaosVariation }, null, 2)}
        </pre>
      </section>
    </div>
  );
}
