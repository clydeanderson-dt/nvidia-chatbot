# Frontend

React 19 chatbot UI built with Vite, React Router v7, and CSS Modules. A chat page and a settings page for system prompt, LLM provider, and read-only chaos status. Communicates with the backend over REST, manages per-tab session IDs, renders assistant replies as Markdown, and shows context-aware follow-up suggestion chips.

---

## Key files

| File | Role |
|---|---|
| `src/App.jsx` | React Router shell: `/` → ChatPage, `/config` → ConfigPage |
| `src/main.jsx` | Entry point; wraps App in BrowserRouter and ConfigProvider |
| `src/context/ConfigContext.jsx` | Global state for app config + chaos status; polls `/api/chaos/status` every 5s |
| `src/hooks/useChat.js` | Chat state and API logic: messages, session ID, suggestions |
| `src/pages/ChatPage.jsx` | Chat page: header, chaos banner, message list, chips, input bar |
| `src/pages/ConfigPage.jsx` | Settings page: system prompt, provider, read-only chaos status (DevCycle-controlled) |
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

For the full design rationale (routing, session lifecycle, system-prompt
and provider flow, starter/follow-up suggestions, chaos read-only model),
see [`docs/architecture.md`](../docs/architecture.md).

Component-specific notes:

- **Session ID** — generated once per browser tab via `crypto.randomUUID()`;
  reloading the page creates a new session.
- **Routing** — `/` is the chat page, `/config` is the settings page.
- **Markdown** — assistant messages render via `react-markdown` + `remark-gfm`
  (code blocks, tables, links, lists). User messages are plain text.
- **Chaos** — `ConfigContext` polls `/api/chaos/status` every 5s; chaos is
  read-only here (controlled by DevCycle). See
  [`docs/devcycle-openfeature.md`](../docs/devcycle-openfeature.md).

---

## Styling

- Each component has a co-located `.module.css` file (e.g. `ChatWindow.module.css`).
- No external CSS framework is used — all styling is plain CSS with modern flexbox/grid.
- Global resets and fonts are in `src/index.css`.
