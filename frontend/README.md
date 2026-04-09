# Frontend

React 19 chatbot UI built with Vite, React Router v7, and CSS Modules. Features a multi-page layout with a chat page and a settings page for system prompt, LLM provider, and chaos engineering controls. Communicates with the backend over REST, manages per-tab session IDs, renders assistant replies as Markdown, and shows context-aware follow-up suggestion chips.

---

## Key files

| File | Role |
|---|---|
| `src/App.jsx` | React Router shell: `/` → ChatPage, `/config` → ConfigPage |
| `src/main.jsx` | Entry point; wraps App in BrowserRouter and ConfigProvider |
| `src/context/ConfigContext.jsx` | Global state for app config + chaos config; polls chaos every 5s |
| `src/hooks/useChat.js` | Chat state and API logic: messages, session ID, suggestions |
| `src/pages/ChatPage.jsx` | Chat page: header, chaos banner, message list, chips, input bar |
| `src/pages/ConfigPage.jsx` | Settings page: system prompt, provider, chaos presets and controls |
| `src/components/ChatWindow.jsx` | Scrollable message list; auto-scrolls to the latest message |
| `src/components/MessageBubble.jsx` | Renders a single message; Markdown + GFM for assistant replies, plain text for user messages |
| `src/components/InputBar.jsx` | Textarea and send button; Enter sends, Shift+Enter inserts a newline |
| `src/components/SuggestionChips.jsx` | Pill buttons for follow-up questions; clicking a chip sends that text as a new message |
| `vite.config.js` | Vite config; defines the `/api` → `localhost:8000` dev-server proxy |

---

## Configuration

### Environment variables

The frontend uses `.env.local` for local environment-specific configuration (gitignored by the `*.local` pattern).

**Required variable:**

- `VITE_DYNATRACE_RUM_URL` — Full URL to your Dynatrace RUM JavaScript tag (injected into `index.html` at build time)

**Setup:**

```bash
# Copy the example file
cp .env.example .env.local

# Edit .env.local and replace the placeholder with your actual Dynatrace RUM URL
# Get your URL from: Dynatrace > Web Applications > Your App > ... > Edit > Setup
```

`.env.example` is committed to the repo as a template; `.env.local` contains your actual values and stays out of version control.

### Dev proxy

In development, all `/api/*` requests are proxied to the backend at `http://localhost:8000` by the Vite dev server. See `vite.config.js`:

```js
server: {
  proxy: {
    '/api': {
      target: 'http://localhost:8000',
      changeOrigin: true,
    },
  },
}
```

---

## Running locally

The backend must be running first (see [backend/README.md](../backend/README.md)).

```bash
cd frontend
npm install
npm run dev
```

Open `http://localhost:5173`.

Other scripts:

```bash
npm run build    # production build → dist/
npm run preview  # serve the production build locally
npm run lint     # run ESLint
```



---

## Key behaviours

### Routing

- Two routes: `/` (ChatPage) and `/config` (ConfigPage).
- The chat page header includes a "Settings" link to `/config` and a "Clear" button to reset the conversation.
- The settings page provides controls for system prompt, LLM provider, and chaos engineering.

### Session ID

- A UUID is generated via `crypto.randomUUID()` when the page loads and is stable for the lifetime of the tab.
- Reloading the page creates a new session — previous messages are lost from both the UI and the server.

### System prompt and provider

- The system prompt and LLM provider are managed on the `/config` settings page via `ConfigContext`.
- Changes are saved to the backend immediately via `PATCH /api/config` and take effect on the next chat message.
- The `useChat` hook reads configuration from `ConfigContext` and does **not** send `system_prompt` or `provider` in request bodies — the server uses its own stored config.

### Chaos engineering

- `ConfigContext` fetches chaos config on mount and polls every 5 seconds to stay in sync.
- When any chaos setting is active, an orange warning banner appears on the chat page.
- The settings page (`/config`) provides preset buttons (healthy, slow_llm, flaky_network, rate_limited, degraded) and granular controls for LLM failures, latency injection, and HTTP error rates.

### Starter suggestions

- When the conversation is empty (on load, or after clearing history), the frontend calls `POST /api/chat/starters` with an empty body (server uses its own config) and displays the results as suggestion chips.
- Starter chips are refreshed whenever `appConfig.system_prompt` changes while the conversation is empty.

### Follow-up suggestions

- After each assistant reply, the backend returns up to 3 follow-up question strings.
- These are displayed as chips below the reply.
- Clicking a chip sends that question as a new message and clears the chips.
- Chips are also cleared immediately when the user sends a new message.

### Markdown rendering

Assistant messages are rendered as Markdown using `react-markdown` with `remark-gfm`, supporting code blocks, tables, links, and lists.

---

## Styling

- Each component has a co-located `.module.css` file (e.g. `ChatWindow.module.css`).
- No external CSS framework is used — all styling is plain CSS with modern flexbox/grid.
- Global resets and fonts are in `src/index.css`.
